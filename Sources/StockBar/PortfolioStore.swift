import Foundation
import Observation

enum ChartRange: String, CaseIterable, Identifiable {
    case day = "1D", quarter = "3M", ytd = "YTD", all = "All"
    var id: String { rawValue }

    static let earliestDay = 20100101

    /// First day inside the range; the range's 0% is the close before it.
    var startDay: Int {
        let cal = Calendar.current
        switch self {
        case .day: return DayKey.from(.now)
        case .quarter: return DayKey.from(cal.date(byAdding: .month, value: -3, to: .now)!)
        case .ytd: return DayKey.from(cal.date(from: cal.dateComponents([.year], from: .now))!)
        case .all: return Self.earliestDay
        }
    }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case dayChange, ytdReturn, ytdVersusCDI, iconOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dayChange: "Today's change"
        case .ytdReturn: "Year-to-date return"
        case .ytdVersusCDI: "Year-to-date vs CDI"
        case .iconOnly: "Icon only"
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

    var menuBarDisplay: MenuBarDisplay {
        didSet { UserDefaults.standard.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") }
    }

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
    private static let cdiURL = directory.appendingPathComponent("cdi-cache.json")
    private static let ipcaURL = directory.appendingPathComponent("ipca-cache.json")
    private static let ifixURL = directory.appendingPathComponent("ifix-cache.json")

    init() {
        menuBarDisplay = MenuBarDisplay(rawValue: UserDefaults.standard.string(forKey: "menuBarDisplay") ?? "") ?? .dayChange
        let saved = (UserDefaults.standard.stringArray(forKey: "benchmarks") ?? ["cdi", "ipca"]).compactMap(BenchmarkID.init)
        enabledBenchmarks = Array(BenchmarkID.allCases.filter(saved.contains).prefix(BenchmarkID.maxEnabled))
        load()
        loadBenchmarks()
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

    func update(_ trade: Trade) {
        guard let i = trades.firstIndex(where: { $0.id == trade.id }) else { return }
        trades[i] = trade
        save()
        recompute()
    }

    func delete(_ trade: Trade) {
        trades.removeAll { $0.id == trade.id }
        save()
        recompute()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.dataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        trades = (try? decoder.decode([Trade].self, from: data)) ?? []
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

        let intradayResults = await withTaskGroup(of: (String, IntradaySeries?).self) { group in
            for ticker in symbols.union(tickers.isEmpty ? [] : [MarketData.ifixSymbol]) {
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

        // Show fresh prices right away; the benchmarks can take a while on the first run.
        recompute()

        let staleBenchmarks = benchmarksFetchedAt.map { Date.now.timeIntervalSince($0) > 6 * 3600 } ?? true
        if staleBenchmarks, !tickers.isEmpty {
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

        var result = quantities.map { Holding(ticker: $0.key, name: histories[$0.key]?.name, quantity: $0.value) }
        let values = result.map { $0.quantity * (histories[$0.ticker]?.last ?? 0) }
        let total = values.reduce(0, +)
        if total > 0 {
            for i in result.indices { result[i].weight = values[i] / total }
        }
        holdings = result.sorted { $0.weight > $1.weight }

        let daily = dailyIndex(quantities, histories)
        let references = ReferenceSeries(sp500: histories[MarketData.sp500Symbol], ifix: liveIFIX())
        var newCurves: [ChartRange: [PerformancePoint]] = [.day: intradayCurve(quantities, intraday)]
        var newReturns: [ChartRange: [String: Double]] = [:]
        var newTickerCurves: [ChartRange: [String: [Double]]] = [:]
        newReturns[.day] = intraday.compactMapValues { $0.previousClose > 0 ? $0.last / $0.previousClose - 1 : nil }
        newTickerCurves[.day] = intraday.compactMapValues { s in
            s.previousClose > 0 ? downsampled([0] + s.prices.map { $0 / s.previousClose - 1 } + [s.last / s.previousClose - 1], limit: 80) : nil
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
    private struct ReferenceSeries {
        var sp500: PriceHistory?
        var ifix: PriceHistory?
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
        case .ipcaPlus5:
            guard !ipca.isEmpty else { return nil }
            let years = DayKey.date(day).timeIntervalSinceReferenceDate / (365.25 * 86_400)
            return ipca.level(at: day) * pow(1.05, years)
        case .sp500: return references.sp500?.price(onOrBefore: day)
        case .ifix: return references.ifix?.price(onOrBefore: day)
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
        let realDaily = pow(1.05, 1.0 / 252) - 1
        let sp500 = intraday[MarketData.sp500Symbol].flatMap { $0.day == session && $0.previousClose > 0 ? $0 : nil }
        let ifix = intraday[MarketData.ifixSymbol].flatMap { $0.day == session && $0.previousClose > 0 ? $0 : nil }
        let start = open.addingTimeInterval(-300)
        func point(_ time: Date, _ value: Double, sp500Price: Double?, ifixValue: Double?) -> PerformancePoint {
            let fraction = min(1, time.timeIntervalSince(start) / (7 * 3600))
            var point = PerformancePoint(date: time, portfolio: value / base - 1)
            if let cdiDaily { point.benchmarks[.cdi] = pow(1 + cdiDaily, fraction) - 1 }
            if let ipcaDaily {
                point.benchmarks[.ipca] = pow(1 + ipcaDaily, fraction) - 1
                point.benchmarks[.ipcaPlus5] = pow((1 + ipcaDaily) * (1 + realDaily), fraction) - 1
            }
            if let sp500, let sp500Price { point.benchmarks[.sp500] = sp500Price / sp500.previousClose - 1 }
            if let ifix, let ifixValue { point.benchmarks[.ifix] = ifixValue / ifix.previousClose - 1 }
            return point
        }

        var points = [point(start, base, sp500Price: sp500?.previousClose, ifixValue: ifix?.previousClose)]
        for time in times {
            let value = held.reduce(0) { $0 + $1.quantity * ($1.series.price(at: time) ?? $1.series.previousClose) }
            points.append(point(
                time, value,
                sp500Price: sp500.map { $0.price(at: time) ?? $0.previousClose },
                ifixValue: ifix.map { $0.price(at: time) ?? $0.previousClose }
            ))
        }
        // End on the live price, which can be newer than the last 5-minute bar.
        let live = held.reduce(0) { $0 + $1.quantity * $1.series.last }
        if let last = times.last { points[points.count - 1] = point(last, live, sp500Price: sp500?.last, ifixValue: ifix?.last) }
        return points
    }

    /// Keeps charts light: at most ~400 points, always including the first and last.
    private func downsampled<T>(_ points: [T], limit: Int = 400) -> [T] {
        guard points.count > limit else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { points[Int((Double($0) * step).rounded())] }
    }


    var dayChange: Double? { curves[.day]?.last?.portfolio }

    var menuBarTitle: String {
        guard !trades.isEmpty else { return "" }
        switch menuBarDisplay {
        case .dayChange: return dayChange?.signedPercent ?? ""
        case .ytdReturn: return curves[.ytd]?.last?.portfolio.signedPercent ?? ""
        case .ytdVersusCDI:
            guard let last = curves[.ytd]?.last, let cdi = last.benchmarks[.cdi] else { return "" }
            return "\((last.portfolio - cdi).signedPoints) CDI"
        case .iconOnly: return ""
        }
    }
}
