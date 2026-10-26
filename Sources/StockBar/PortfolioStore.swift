import Foundation
import Observation

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D", week = "1W", quarter = "3M", ytd = "YTD", year = "1Y", threeYears = "3Y", fiveYears = "5Y", all = "All"
    var id: String { rawValue }

    /// The short label on range pickers; the raw value stays the stored setting.
    var label: String {
        switch self {
        case .day: String(localized: "1D")
        case .week: String(localized: "1W")
        case .quarter: String(localized: "3M")
        case .ytd: String(localized: "YTD")
        case .year: String(localized: "1Y")
        case .threeYears: String(localized: "3Y")
        case .fiveYears: String(localized: "5Y")
        case .all: String(localized: "All")
        }
    }

    static let earliestDay = 20100101

    /// First day inside the range; the range's 0% is the close before it.
    var startDay: Int {
        let cal = Calendar.current
        switch self {
        case .day: return DayKey.from(.now)
        case .week: return DayKey.from(cal.date(byAdding: .day, value: -7, to: .now)!)
        case .quarter: return DayKey.from(cal.date(byAdding: .month, value: -3, to: .now)!)
        case .ytd: return DayKey.from(cal.date(from: cal.dateComponents([.year], from: .now))!)
        case .year: return DayKey.from(cal.date(byAdding: .year, value: -1, to: .now)!)
        case .threeYears: return DayKey.from(cal.date(byAdding: .year, value: -3, to: .now)!)
        case .fiveYears: return DayKey.from(cal.date(byAdding: .year, value: -5, to: .now)!)
        case .all: return Self.earliestDay
        }
    }
}

@MainActor
@Observable
final class PortfolioStore {
    private(set) var trades: [Trade] = []
    private(set) var holdings: [Holding] = []
    private(set) var curves: [ChartRange: [PerformancePoint]] = [:]
    private(set) var tickerReturns: [ChartRange: [String: Double]] = [:]
    /// Per-stock return paths for each range, for the list's sparklines.
    private(set) var tickerCurves: [ChartRange: [String: [Double]]] = [:]
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    private(set) var errors: [String] = []
    private(set) var alerts: [PriceAlert] = []
    /// This year's and upcoming cash payments on today's holdings, newest first.
    private(set) var dividends: [DividendPayment] = []
    /// Today's holdings at the latest prices, in reais.
    private(set) var totalValue: Double = 0
    private(set) var bonds: [Bond] = []

    /// Benchmarks drawn on the chart, in the fixed order of `BenchmarkID.allCases` (so colors never move).
    var enabledBenchmarks: [BenchmarkID] {
        didSet { UserDefaults.standard.set(enabledBenchmarks.map(\.rawValue), forKey: "benchmarks") }
    }

    func setBenchmark(_ id: BenchmarkID, enabled: Bool) {
        var set = Set(enabledBenchmarks)
        if enabled {
            guard set.count < BenchmarkID.maxEnabled else { return }
            set.insert(id)
        } else {
            set.remove(id)
        }
        enabledBenchmarks = BenchmarkID.allCases.filter(set.contains)
    }

    private var histories: [String: PriceHistory] = [:]
    /// B3's announcements per ticker; tickers B3 has none for (FIIs, ETFs) fall back to Yahoo's dividend events.
    private var b3Dividends: [String: [(kind: DividendKind, recordDay: Int, paymentDay: Int?, perShare: Double)]] = [:]
    private var intraday: [String: IntradaySeries] = [:]
    private var cdi = Benchmark(points: [], kind: .daily)
    private var ipca = Benchmark(points: [], kind: .monthly)
    private var historiesFetchedAt: Date?
    private var benchmarksFetchedAt: Date?
    private var cdiPoints: [RatePoint] = []
    private var ipcaPoints: [RatePoint] = []
    /// IFIX daily closes from B3 (cached on disk; Yahoo supplies today's live value).
    private var ifixHistory: PriceHistory?
    private var refreshLoop: Task<Void, Never>?
    private var refreshPending = false

    static let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StockBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    static let dataURL = directory.appendingPathComponent("trades.json")
    private static let alertsURL = directory.appendingPathComponent("alerts.json")
    private static let bondsURL = directory.appendingPathComponent("bonds.json")
    private static let cdiURL = directory.appendingPathComponent("cdi-cache.json")
    private static let ipcaURL = directory.appendingPathComponent("ipca-cache.json")
    private static let ifixURL = directory.appendingPathComponent("ifix-cache.json")

    init() {
        // IPCA+5% was replaced by IPCA+6%; carry the old choice over.
        let saved = (UserDefaults.standard.stringArray(forKey: "benchmarks") ?? ["cdi", "ipca"])
            .map { $0 == "ipcaPlus5" ? BenchmarkID.ipcaPlus6.rawValue : $0 }
            .compactMap(BenchmarkID.init)
        enabledBenchmarks = Array(BenchmarkID.allCases.filter(saved.contains).prefix(BenchmarkID.maxEnabled))
        load()
        loadAlerts()
        loadBonds()
        loadBenchmarks()
        AlertNotifier.shared.setUp()
        recompute()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    // MARK: - Trades

    func add(_ trade: Trade) {
        trades.append(trade)
        trades.sort { $0.date < $1.date }
        save()
        recompute()
        Task { await refresh() }
    }

    /// Average price of the buys that have one, weighted by quantity.
    func averagePrice(_ ticker: String) -> Double? {
        let priced = trades.filter { $0.ticker == ticker && $0.kind == .buy && $0.price != nil }
        let shares = priced.reduce(0) { $0 + $1.quantity }
        guard shares > 0 else { return nil }
        return priced.reduce(0) { $0 + $1.quantity * $1.price! } / shares
    }

    /// Sets a stock's holding to `quantity` at `averagePrice`, folding its trades into one
    /// (dated like the first, which nothing relies on).
    func setQuantity(_ ticker: String, to quantity: Double, averagePrice: Double?) {
        let first = trades.first { $0.ticker == ticker }
        trades.removeAll { $0.ticker == ticker }
        trades.append(Trade(ticker: ticker, kind: .buy, date: first?.date ?? .now, quantity: quantity, price: averagePrice))
        trades.sort { $0.date < $1.date }
        save()
        recompute()
    }

    func removeStock(_ ticker: String) {
        trades.removeAll { $0.ticker == ticker }
        save()
        recompute()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        trades = (try? decoder.decode([Trade].self, from: data)) ?? []
    }

    // MARK: - Bonds

    /// Prices bonds with the CDI and IPCA series loaded for the benchmarks.
    var bondPricer: BondPricer {
        BondPricer(cdi: cdiPoints, ipca: Dictionary(ipcaPoints.map { ($0.day / 100, $0.rate) }, uniquingKeysWith: { $1 }))
    }

    func saveBond(_ bond: Bond) {
        if let i = bonds.firstIndex(where: { $0.id == bond.id }) { bonds[i] = bond } else { bonds.append(bond) }
        bonds.sort { ($0.maturityDay, $0.issuer) < ($1.maturityDay, $1.issuer) }
        saveBonds()
    }

    func deleteBond(_ bond: Bond) {
        bonds.removeAll { $0.id == bond.id }
        saveBonds()
    }

    private func loadBonds() {
        guard let data = try? Data(contentsOf: Self.bondsURL) else { return }
        bonds = (try? JSONDecoder().decode([Bond].self, from: data)) ?? []
    }

    private func saveBonds() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(bonds).write(to: Self.bondsURL, options: .atomic)
    }

    // MARK: - Price alerts

    func addAlert(_ alert: PriceAlert) {
        alerts.append(alert)
        saveAlerts()
        Task { await refresh() }
    }

    /// Saving an edit re-arms the alert against the new target.
    func updateAlert(_ alert: PriceAlert) {
        guard let i = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[i] = alert
        saveAlerts()
        Task { await refresh() }
    }

    func setAlert(_ alert: PriceAlert, enabled: Bool) {
        guard let i = alerts.firstIndex(where: { $0.id == alert.id }) else { return }
        alerts[i].isEnabled = enabled
        if enabled { alerts[i].triggeredAt = nil }
        saveAlerts()
        checkAlerts()
    }

    func deleteAlert(_ alert: PriceAlert) {
        alerts.removeAll { $0.id == alert.id }
        saveAlerts()
    }

    /// Cumulative CDI level on a day (growth between two days is the ratio), for the fund comparison.
    func cdiLevel(at day: Int) -> Double? { cdi.isEmpty ? nil : cdi.level(at: day) }

    /// Latest price in the ticker's own currency (dollars for US stocks).
    func livePrice(_ ticker: String) -> Double? { intraday[ticker]?.last }

    /// Fires every armed alert whose target the latest price has reached, then disarms it.
    private func checkAlerts() {
        var fired = false
        for i in alerts.indices where alerts[i].isEnabled {
            guard let price = livePrice(alerts[i].ticker), alerts[i].isMet(by: price) else { continue }
            alerts[i].isEnabled = false
            alerts[i].triggeredAt = .now
            fired = true
            let alert = alerts[i]
            Task { await AlertNotifier.shared.send(alert, price: price) }
        }
        if fired { saveAlerts() }
    }

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: Self.alertsURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        alerts = (try? decoder.decode([PriceAlert].self, from: data)) ?? []
    }

    private func saveAlerts() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(alerts).write(to: Self.alertsURL, options: .atomic)
    }

    // MARK: - Benchmark cache

    /// Past CDI/IPCA rates never change, so they're cached on disk and only the recent tail is re-fetched.
    private func loadBenchmarks() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Self.cdiURL), let points = try? decoder.decode([RatePoint].self, from: data) {
            cdiPoints = points
            cdi = Benchmark(points: points, kind: .daily)
        }
        if let data = try? Data(contentsOf: Self.ipcaURL), let points = try? decoder.decode([RatePoint].self, from: data) {
            ipcaPoints = points
            ipca = Benchmark(points: points, kind: .monthly)
        }
        if let data = try? Data(contentsOf: Self.ifixURL) {
            ifixHistory = try? decoder.decode(PriceHistory.self, from: data)
        }
    }

    private func saveBenchmarks() {
        let encoder = JSONEncoder()
        try? encoder.encode(cdiPoints).write(to: Self.cdiURL, options: .atomic)
        try? encoder.encode(ipcaPoints).write(to: Self.ipcaURL, options: .atomic)
        if let ifixHistory { try? encoder.encode(ifixHistory).write(to: Self.ifixURL, options: .atomic) }
    }

    /// Past years never change: refetch only from the last cached year (or everything since 2010).
    private nonisolated func updatedIFIX(cached: PriceHistory?) async throws -> PriceHistory {
        let thisYear = Calendar.current.component(.year, from: .now)
        let firstYear = ChartRange.earliestDay / 10_000
        guard let cached, let first = cached.days.first, first / 10_000 <= firstYear, let last = cached.days.last else {
            return try await MarketData.b3IndexHistory("IFIX", fromYear: firstYear, toYear: thisYear)
        }
        let fromYear = last / 10_000
        let fresh = try await MarketData.b3IndexHistory("IFIX", fromYear: fromYear, toYear: thisYear)
        let cutoff = fromYear * 10_000
        let kept = zip(cached.days, cached.prices).filter { $0.0 < cutoff }
        return PriceHistory(days: kept.map(\.0) + fresh.days, prices: kept.map(\.1) + fresh.prices, name: "IFIX")
    }

    private nonisolated func updatedSeries(_ code: Int, cached: [RatePoint], overlapDays: Int) async throws -> [RatePoint] {
        let earliest = DayKey.date(ChartRange.earliestDay)
        // A cache that doesn't reach back to the first month of 2010 is refetched in full.
        guard let first = cached.first, first.day / 100 <= ChartRange.earliestDay / 100, let last = cached.last else {
            return try await MarketData.bcbSeries(code, from: earliest)
        }
        let from = DayKey.date(last.day).addingTimeInterval(-Double(overlapDays) * 86_400)
        let fresh = try await MarketData.bcbSeries(code, from: from)
        let cutoff = fresh.first?.day ?? Int.max
        return cached.filter { $0.day < cutoff } + fresh
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(trades).write(to: Self.dataURL, options: .atomic)
    }

    // MARK: - Market data

    func refresh() async {
        guard !isLoading else { refreshPending = true; return }
        isLoading = true
        await loadMarketData()
        recompute()
        isLoading = false
        if refreshPending {
            refreshPending = false
            await refresh()
        }
    }

    /// Intraday prices every refresh; daily history since 2010 and CDI/IPCA every 6 hours (or for new tickers).
    private func loadMarketData() async {
        var newErrors: [String] = []
        let tickers = Set(currentQuantities().keys)
        let earliest = DayKey.date(ChartRange.earliestDay)
        // Reference series ride along with the stocks: the dollar (for US prices) and the S&P 500 benchmark.
        let symbols = tickers.isEmpty ? [] : tickers.union(MarketData.referenceSymbols)

        let staleHistories = historiesFetchedAt.map { Date.now.timeIntervalSince($0) > 6 * 3600 } ?? true
        let needHistory = symbols.filter { staleHistories || histories[$0] == nil }
        let dailyResults = await withTaskGroup(of: (String, PriceHistory?).self) { group in
            for ticker in needHistory {
                group.addTask { (ticker, try? await MarketData.history(for: ticker, from: earliest)) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        for (ticker, history) in dailyResults {
            if let history { histories[ticker] = history } else { newErrors.append("No data for \(MarketData.displayName(ticker))") }
        }
        if staleHistories, !needHistory.isEmpty { historiesFetchedAt = .now }
        if !needHistory.isEmpty {
            let b3Tickers = tickers.filter(MarketData.isB3)
            let announced = await withTaskGroup(of: (String, [(kind: DividendKind, recordDay: Int, paymentDay: Int?, perShare: Double)]?).self) { group in
                for ticker in b3Tickers { group.addTask { (ticker, try? await MarketData.b3Dividends(for: ticker)) } }
                return await group.reduce(into: []) { $0.append($1) }
            }
            for (ticker, rows) in announced { b3Dividends[ticker] = rows }
        }

        let intradayResults = await withTaskGroup(of: (String, IntradaySeries?).self) { group in
            // Alerts can watch tickers that aren't held.
            let watched = Set(alerts.filter(\.isEnabled).map(\.ticker))
            for ticker in symbols.union(tickers.isEmpty ? [] : [MarketData.ifixSymbol]).union(watched) {
                group.addTask { (ticker, try? await MarketData.intraday(for: ticker)) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }
        for (ticker, series) in intradayResults {
            guard let series else { continue }
            intraday[ticker] = series
            // Keep the daily history's last point live between full reloads.
            if var h = histories[ticker], let lastDay = h.days.last {
                if lastDay == series.day { h.prices[h.prices.count - 1] = series.last }
                else if lastDay < series.day { h.days.append(series.day); h.prices.append(series.last) }
                histories[ticker] = h
            }
        }

        checkAlerts()
        // Show fresh prices right away; the benchmarks can take a while on the first run.
        recompute()

        let staleBenchmarks = benchmarksFetchedAt.map { Date.now.timeIntervalSince($0) > 6 * 3600 } ?? true
        if staleBenchmarks, !tickers.isEmpty || !bonds.isEmpty {
            do {
                async let newCDI = updatedSeries(12, cached: cdiPoints, overlapDays: 10)
                async let newIPCA = updatedSeries(433, cached: ipcaPoints, overlapDays: 70)
                async let newIFIX = updatedIFIX(cached: ifixHistory)
                (cdiPoints, ipcaPoints) = try await (newCDI, newIPCA)
                // IFIX comes from a different server; a failure there shouldn't hide CDI/IPCA.
                if let ifix = try? await newIFIX { ifixHistory = ifix } else { newErrors.append("Couldn't load IFIX from B3") }
                cdi = Benchmark(points: cdiPoints, kind: .daily)
                ipca = Benchmark(points: ipcaPoints, kind: .monthly)
                benchmarksFetchedAt = .now
                saveBenchmarks()
            } catch {
                newErrors.append("Couldn't load CDI/IPCA from Banco Central")
            }
        }

        errors = newErrors.sorted()
        lastUpdated = .now
    }

    // MARK: - Derived

    private func currentQuantities() -> [String: Double] {
        var quantities: [String: Double] = [:]
        for trade in trades {
            quantities[trade.ticker] = max(0, (quantities[trade.ticker] ?? 0) + trade.signedQuantity)
        }
        return quantities.filter { $0.value > 0.000001 }
    }

    /// Daily prices in reais: US stocks are converted at each day's USD/BRL close.
    /// Without the dollar, US stocks are left out rather than mixed in as if they were reais.
    private func pricesInReais() -> [String: PriceHistory] {
        var result = histories
        let dollar = histories[MarketData.dollarSymbol]
        for (ticker, h) in histories where MarketData.isInDollars(ticker) {
            guard let dollar, let firstRate = dollar.prices.first else { result[ticker] = nil; continue }
            result[ticker]?.prices = zip(h.days, h.prices).map { day, price in price * (dollar.price(onOrBefore: day) ?? firstRate) }
        }
        return result
    }

    private func intradayInReais() -> [String: IntradaySeries] {
        var result = intraday
        let dollar = intraday[MarketData.dollarSymbol]
        for (ticker, s) in intraday where MarketData.isInDollars(ticker) {
            guard let dollar else { result[ticker] = nil; continue }
            var converted = s
            converted.prices = zip(s.times, s.prices).map { time, price in price * (dollar.price(at: time) ?? dollar.previousClose) }
            converted.previousClose = s.previousClose * dollar.previousClose
            converted.last = s.last * dollar.last
            result[ticker] = converted
        }
        return result
    }

    private func recompute() {
        let quantities = currentQuantities()
        let histories = pricesInReais()
        let intraday = intradayInReais()

        var result = quantities.map { Holding(ticker: $0.key, name: histories[$0.key]?.name, quantity: $0.value, averagePrice: averagePrice($0.key)) }
        let values = result.map { $0.quantity * (histories[$0.ticker]?.last ?? 0) }
        let total = values.reduce(0, +)
        if total > 0 {
            for i in result.indices { result[i].weight = values[i] / total }
        }
        holdings = result.sorted { $0.weight > $1.weight }
        totalValue = total
        dividends = dividendPayments(quantities)

        let daily = dailyIndex(quantities, histories)
        let references = ReferenceSeries(sp500: histories[MarketData.sp500Symbol], ifix: liveIFIX(), ibov: histories[MarketData.ibovSymbol])
        var newCurves: [ChartRange: [PerformancePoint]] = [.day: intradayCurve(quantities, intraday)]
        var newReturns: [ChartRange: [String: Double]] = [:]
        var newTickerCurves: [ChartRange: [String: [Double]]] = [:]
        // A market that hasn't traded today (US before its open, weekends, holidays) shows no change rather than a stale one.
        let today = DayKey.from(.now, calendar: .b3)
        let tradedToday = intraday.filter { $0.value.day == today && $0.value.previousClose > 0 }
        newReturns[.day] = tradedToday.mapValues { $0.last / $0.previousClose - 1 }
        newTickerCurves[.day] = tradedToday.mapValues { s -> [Double] in
            let path: [Double] = s.prices.map { $0 / s.previousClose - 1 }
            return downsampled([0] + path + [s.last / s.previousClose - 1], limit: 80)
        }
        for range in ChartRange.allCases where range != .day {
            newCurves[range] = rebased(daily, from: range.startDay, references: references)
            newReturns[range] = histories.compactMapValues { h in
                // Close before the range starts, or the first close for stocks listed later.
                guard let base = h.price(onOrBefore: range.startDay - 1) ?? h.prices.first, let last = h.last else { return nil }
                return last / base - 1
            }
            newTickerCurves[range] = histories.compactMapValues { h in
                let baseIndex = h.days.lastIndex { $0 < range.startDay } ?? 0
                let base = h.prices[baseIndex]
                return downsampled(h.prices[baseIndex...].map { $0 / base - 1 }, limit: 80)
            }
        }
        curves = newCurves
        tickerReturns = newReturns
        tickerCurves = newTickerCurves
    }

    /// Payments landing this year or later, for today's quantities (trades carry no dates to say otherwise).
    /// B3 companies use B3's announcements (dividend vs JCP, with payment dates); everything else uses
    /// Yahoo's ex-dividend events, converted to reais at that day's dollar for US stocks.
    private func dividendPayments(_ quantities: [String: Double]) -> [DividendPayment] {
        let yearStart = DayKey.from(.now) / 10_000 * 10_000 + 101
        let dollar = histories[MarketData.dollarSymbol]
        var result: [DividendPayment] = []
        for (ticker, quantity) in quantities {
            if let rows = b3Dividends[ticker] {
                for r in rows where (r.paymentDay ?? r.recordDay) >= yearStart {
                    result.append(DividendPayment(ticker: ticker, kind: r.kind, recordDay: r.recordDay, paymentDay: r.paymentDay,
                                                  perShare: r.perShare, quantity: quantity, amount: r.perShare * quantity))
                }
            } else if let events = histories[ticker]?.dividends {
                let isUS = MarketData.isInDollars(ticker)
                for e in events where e.day >= yearStart {
                    let rate = isUS ? (dollar?.price(onOrBefore: e.day) ?? dollar?.last) : 1
                    guard let rate else { continue }
                    result.append(DividendPayment(ticker: ticker, kind: isUS ? .dividend : .income, recordDay: e.day, paymentDay: nil,
                                                  datedByExDate: true, perShare: e.amount, quantity: quantity, amount: e.amount * quantity * rate))
                }
            }
        }
        return result.sorted { ($0.day, $0.ticker) > ($1.day, $1.ticker) }
    }


    /// Growth of the current portfolio (today's quantities) held through every session since 2010.
    /// Each session's return weights stocks by their value at the previous close; stocks not yet listed are left out.
    private func dailyIndex(_ quantities: [String: Double], _ histories: [String: PriceHistory]) -> [(day: Int, value: Double)] {
        let held = quantities.compactMap { q in histories[q.key].map { (history: $0, quantity: q.value) } }
        let axis = Set(held.flatMap(\.history.days)).filter { $0 >= ChartRange.earliestDay }.sorted()
        guard let first = axis.first else { return [] }

        var index = 1.0
        var result = [(day: first, value: index)]
        for (previous, day) in zip(axis, axis.dropFirst()) {
            var before = 0.0, after = 0.0
            for h in held {
                guard let p0 = h.history.price(onOrBefore: previous), let p1 = h.history.price(onOrBefore: day) else { continue }
                before += h.quantity * p0
                after += h.quantity * p1
            }
            if before > 0 { index *= after / before }
            result.append((day, index))
        }
        return result
    }

    /// Market-index benchmarks, in reais.
    /// Stock prices in reais by ticker (US stocks at each day's dollar), for the consolidated overview.
    func stockHistoriesInReais() -> [String: PriceHistory] { pricesInReais() }

    /// Returns since `start` for any daily value series, with every benchmark alongside, like the stock curves.
    func performance(of daily: [(day: Int, value: Double)], from start: Int) -> [PerformancePoint] {
        let histories = pricesInReais()
        let references = ReferenceSeries(sp500: histories[MarketData.sp500Symbol], ifix: liveIFIX(), ibov: histories[MarketData.ibovSymbol])
        return rebased(daily, from: start, references: references)
    }

    private struct ReferenceSeries {
        var sp500: PriceHistory?
        var ifix: PriceHistory?
        var ibov: PriceHistory?
    }

    /// B3's IFIX history with today's live value from Yahoo on the end.
    private func liveIFIX() -> PriceHistory? {
        guard var h = ifixHistory, let lastDay = h.days.last else { return ifixHistory }
        if let live = intraday[MarketData.ifixSymbol] {
            if lastDay == live.day { h.prices[h.prices.count - 1] = live.last }
            else if lastDay < live.day { h.days.append(live.day); h.prices.append(live.last) }
        }
        return h
    }

    /// Cumulative level of a benchmark on a day; growth between two days is the ratio of their levels.
    private func benchmarkLevel(_ id: BenchmarkID, at day: Int, references: ReferenceSeries) -> Double? {
        switch id {
        case .cdi: return cdi.isEmpty ? nil : cdi.level(at: day)
        case .ipca: return ipca.isEmpty ? nil : ipca.level(at: day)
        case .ipcaPlus6:
            guard !ipca.isEmpty else { return nil }
            let years = DayKey.date(day).timeIntervalSinceReferenceDate / (365.25 * 86_400)
            return ipca.level(at: day) * pow(1.06, years)
        case .sp500: return references.sp500?.price(onOrBefore: day)
        case .ifix: return references.ifix?.price(onOrBefore: day)
        case .ibov: return references.ibov?.price(onOrBefore: day)
        }
    }

    private func rebased(_ daily: [(day: Int, value: Double)], from start: Int, references: ReferenceSeries) -> [PerformancePoint] {
        let baseIndex = daily.lastIndex { $0.day < start } ?? 0
        guard baseIndex < daily.count - 1 else { return [] }
        let base = daily[baseIndex]
        // A benchmark that starts later than the range (IFIX began Dec 2010) starts at 0% on its first day.
        let bases = Dictionary(uniqueKeysWithValues: BenchmarkID.allCases.compactMap { id in
            daily[baseIndex...].lazy.compactMap { self.benchmarkLevel(id, at: $0.day, references: references) }.first.map { (id, $0) }
        })
        let points = daily[baseIndex...].map { p in
            var point = PerformancePoint(date: DayKey.date(p.day), portfolio: p.value / base.value - 1)
            for (id, baseLevel) in bases where baseLevel > 0 {
                if let level = benchmarkLevel(id, at: p.day, references: references) { point.benchmarks[id] = level / baseLevel - 1 }
            }
            return point
        }
        return downsampled(points)
    }

    /// The latest session in 5-minute steps against the previous close. CDI and IPCA accrue
    /// their latest daily-equivalent rate evenly over the 7-hour session.
    private func intradayCurve(_ quantities: [String: Double], _ intraday: [String: IntradaySeries]) -> [PerformancePoint] {
        guard let session = intraday.values.map(\.day).max() else { return [] }
        let held = quantities.compactMap { q in
            intraday[q.key].flatMap { $0.day == session ? (series: $0, quantity: q.value) : nil }
        }
        let times = Set(held.flatMap(\.series.times)).sorted()
        let base = held.reduce(0) { $0 + $1.quantity * $1.series.previousClose }
        guard let open = times.first, base > 0 else { return [] }

        let cdiDaily = cdi.latestRate.map { $0 / 100 }
        let ipcaDaily = ipca.latestRate.map { pow(1 + $0 / 100, 1.0 / 21) - 1 }
        let realDaily = pow(1.06, 1.0 / 252) - 1
        // Market indices move with their own live prices against the previous close.
        let indices: [(id: BenchmarkID, series: IntradaySeries)] = [
            (.sp500, MarketData.sp500Symbol), (.ifix, MarketData.ifixSymbol), (.ibov, MarketData.ibovSymbol),
        ].compactMap { id, symbol in
            intraday[symbol].flatMap { $0.day == session && $0.previousClose > 0 ? (id, $0) : nil }
        }
        let start = open.addingTimeInterval(-300)
        func point(_ time: Date, _ value: Double, indexValue: (IntradaySeries) -> Double) -> PerformancePoint {
            let fraction = min(1, time.timeIntervalSince(start) / (7 * 3600))
            var point = PerformancePoint(date: time, portfolio: value / base - 1)
            if let cdiDaily { point.benchmarks[.cdi] = pow(1 + cdiDaily, fraction) - 1 }
            if let ipcaDaily {
                point.benchmarks[.ipca] = pow(1 + ipcaDaily, fraction) - 1
                point.benchmarks[.ipcaPlus6] = pow((1 + ipcaDaily) * (1 + realDaily), fraction) - 1
            }
            for (id, series) in indices { point.benchmarks[id] = indexValue(series) / series.previousClose - 1 }
            return point
        }

        var points = [point(start, base) { $0.previousClose }]
        for time in times {
            let value = held.reduce(0) { $0 + $1.quantity * ($1.series.price(at: time) ?? $1.series.previousClose) }
            points.append(point(time, value) { $0.price(at: time) ?? $0.previousClose })
        }
        // End on the live price, which can be newer than the last 5-minute bar.
        let live = held.reduce(0) { $0 + $1.quantity * $1.series.last }
        if let last = times.last { points[points.count - 1] = point(last, live) { $0.last } }
        return points
    }

    /// Keeps charts light: at most ~400 points, always including the first and last.
    private func downsampled<T>(_ points: [T], limit: Int = 400) -> [T] {
        guard points.count > limit else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }


    var dayChange: Double? { curves[.day]?.last?.portfolio }
}
