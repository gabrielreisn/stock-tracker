import Foundation
import Observation

enum FundRange: String, CaseIterable, Identifiable {
    case halfYear = "6M", ytd = "YTD", year = "1Y", threeYears = "3Y", fiveYears = "5Y"
    var id: String { rawValue }

    /// First day inside the range; the range's 0% is the last share price before it.
    var startDay: Int {
        let cal = Calendar.current
        let start: Date = switch self {
        case .halfYear: cal.date(byAdding: .month, value: -6, to: .now)!
        case .ytd: cal.date(from: cal.dateComponents([.year], from: .now))!
        case .year: cal.date(byAdding: .year, value: -1, to: .now)!
        case .threeYears: cal.date(byAdding: .year, value: -3, to: .now)!
        case .fiveYears: cal.date(byAdding: .year, value: -5, to: .now)!
        }
        return DayKey.from(start)
    }
}

/// A fund on the comparison chart. Its color slot sticks while it's selected, so removing one doesn't repaint the others.
struct ComparedFund: Codable, Identifiable, Hashable {
    var fund: FundInfo
    var slot: Int
    var id: String { fund.id }
}

struct FundPoint: Identifiable {
    var date: Date
    var returns: [String: Double] = [:]
    var cdi: Double?
    var id: Date { date }
}

/// One calendar year of the fact sheet's monthly returns table.
struct FundYear: Identifiable {
    var year: Int
    var months: [Int: Double] = [:]
    var total: Double?
    var cdi: Double?
    var id: Int { year }
}

struct FundStats {
    var totalReturn: Double
    var volatility: Double?
    var maxDrawdown: Double
    var percentOfCDI: Double?
    var firstDay: Int
}

@MainActor
@Observable
final class FundStore {
    enum IndexState: Equatable { case idle, loading, ready, failed(String) }

    static let maxSelected = 6

    private(set) var indexState: IndexState = .idle
    private(set) var selected: [ComparedFund] = [] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(selected), forKey: "comparedFunds") }
    }
    var range: FundRange {
        didSet {
            UserDefaults.standard.set(range.rawValue, forKey: "fundRange")
            reload()
        }
    }
    private(set) var points: [FundPoint] = []
    private(set) var stats: [String: FundStats] = [:]
    private(set) var isLoading = false
    private(set) var progress = (done: 0, total: 0)
    private(set) var error: String?

    /// Funds held, with CVM price histories by CNPJ (see FundHoldings.swift).
    var holdings: [FundHolding] = FundStore.loadHoldingsFile()
    var holdingSeries: [String: PriceHistory] = [:] { didSet { holdingSeriesVersion += 1 } }
    /// Bumped whenever the histories change, including when older months arrive.
    var holdingSeriesVersion = 0
    var holdingsLoading = false
    var registryDetails: [String: FundDetails] = [:]

    private var index: [FundInfo] = []
    /// Accent- and case-folded "name manager category cnpj" per index entry, for search.
    private var haystacks: [String] = []
    private var histories: [String: PriceHistory] = [:]
    /// End-of-month net assets, shareholders and flows per fund, oldest first.
    private(set) var summaries: [String: [(month: Int, summary: MonthSummary)]] = [:]
    private var details: [String: FundDetails]?
    private var loadTask: Task<Void, Never>?
    private let portfolio: PortfolioStore

    init(portfolio: PortfolioStore) {
        self.portfolio = portfolio
        range = FundRange(rawValue: UserDefaults.standard.string(forKey: "fundRange") ?? "") ?? .year
        if let data = UserDefaults.standard.data(forKey: "comparedFunds"),
           let saved = try? JSONDecoder().decode([ComparedFund].self, from: data) {
            selected = saved
        }
    }

    /// Called when the window opens: the fund list once, prices whenever they're missing.
    func start() {
        if indexState != .ready && indexState != .loading { loadIndex() }
        if histories.isEmpty, !selected.isEmpty { reload() } else { recompute() }
    }

    private func loadIndex() {
        indexState = .loading
        Task {
            do {
                let funds = try await CVM.fundIndex()
                let haystacks = await Task.detached(priority: .userInitiated) {
                    funds.map { Self.fold("\($0.name) \($0.manager ?? "") \($0.category ?? "") \($0.cnpj)") }
                }.value
                index = funds
                self.haystacks = haystacks
                indexState = .ready
            } catch {
                indexState = .failed("Couldn't download the fund list from CVM")
            }
        }
    }

    // MARK: - Search

    /// CNPJs match on their digits (punctuation optional); anything else needs every word to appear in the
    /// name, manager or category. Name matches come first, then larger funds.
    func search(_ query: String) -> [FundInfo] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let digits = trimmed.filter(\.isNumber)
        let isCNPJ = digits.count >= 4 && trimmed.allSatisfy { $0.isNumber || ".-/ ".contains($0) }
        let folded = Self.fold(trimmed)
        let words = folded.split(separator: " ")

        var matches: [(fund: FundInfo, rank: Int)] = []
        for (i, fund) in index.enumerated() {
            if isCNPJ {
                if fund.cnpj.contains(digits) { matches.append((fund, fund.cnpj.hasPrefix(digits) ? 0 : 1)) }
                continue
            }
            let haystack = haystacks[i]
            guard words.allSatisfy({ haystack.contains($0) }) else { continue }
            let name = haystack.prefix(fund.name.count)
            let rank = name.hasPrefix(folded) ? 0 : words.allSatisfy({ name.contains($0) }) ? 1 : 2
            matches.append((fund, rank))
        }
        return matches
            .sorted { ($0.rank, -($0.fund.netAssets ?? 0)) < ($1.rank, -($1.fund.netAssets ?? 0)) }
            .prefix(40)
            .map(\.fund)
    }

    private nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    // MARK: - Selection

    func add(_ fund: FundInfo) {
        guard selected.count < Self.maxSelected, !selected.contains(where: { $0.id == fund.id }) else { return }
        let used = Set(selected.map(\.slot))
        selected.append(ComparedFund(fund: fund, slot: (0..<Self.maxSelected).first { !used.contains($0) } ?? 0))
        reload()
    }

    func remove(_ fund: ComparedFund) {
        selected.removeAll { $0.id == fund.id }
        histories[fund.id] = nil
        summaries[fund.id] = nil
        recompute()
    }

    // MARK: - Fact sheet

    /// Registry details, read from disk the first time a fact sheet opens.
    func details(for id: String) async -> FundDetails? {
        if details == nil { details = await CVM.fundDetails() }
        return details?[id]
    }

    /// Month-by-month returns (last price of each month against the month before) over the loaded range, newest year first.
    func monthlyReturns(_ id: String) -> [FundYear] {
        guard let h = histories[id] else { return [] }
        var monthEnds: [(month: Int, day: Int, price: Double)] = []
        for (day, price) in zip(h.days, h.prices) {
            if monthEnds.last?.month == day / 100 { monthEnds[monthEnds.count - 1] = (day / 100, day, price) }
            else { monthEnds.append((day / 100, day, price)) }
        }
        var years: [Int: FundYear] = [:]
        var yearStart: [Int: (day: Int, price: Double)] = [:]
        for (previous, current) in zip(monthEnds, monthEnds.dropFirst()) {
            let year = current.month / 100
            years[year, default: FundYear(year: year)].months[current.month % 100] = current.price / previous.price - 1
            if yearStart[year] == nil { yearStart[year] = (previous.day, previous.price) }
            if let start = yearStart[year] {
                years[year]?.total = current.price / start.price - 1
                if let from = portfolio.cdiLevel(at: start.day), let to = portfolio.cdiLevel(at: current.day) {
                    years[year]?.cdi = to / from - 1
                }
            }
        }
        return years.values.sorted { $0.year > $1.year }
    }

    func history(_ id: String) -> PriceHistory? { histories[id] }

    /// Vertical scale fitted to the visible lines (plus 0%), so small moves stay readable.
    var yDomain: ClosedRange<Double> {
        var lo = 0.0, hi = 0.0
        for p in points {
            for v in p.returns.values { lo = min(lo, v); hi = max(hi, v) }
            if let c = p.cdi { lo = min(lo, c); hi = max(hi, c) }
        }
        let pad = max((hi - lo) * 0.08, 0.002)
        return (lo - pad)...(hi + pad)
    }

    // MARK: - Prices

    /// Fetches every month in the range (plus the one before, for the starting price) for all selected funds.
    func reload() {
        loadTask?.cancel()
        let ids = Set(selected.map(\.id))
        guard !ids.isEmpty else { histories = [:]; recompute(); return }
        let startMonth = max(CVM.firstMonth, DayKey.from(Calendar.current.date(byAdding: .month, value: -1, to: DayKey.date(range.startDay))!) / 100)
        let months = Self.months(from: startMonth, to: DayKey.from(.now) / 100)

        isLoading = true
        error = nil
        progress = (0, months.count)
        loadTask = Task {
            var collected: [String: [(day: Int, quota: Double)]] = [:]
            var collectedSummaries: [String: [(month: Int, summary: MonthSummary)]] = [:]
            var failed = false
            // A few at a time: each month is a ~10 MB download.
            for chunk in stride(from: 0, to: months.count, by: 4) {
                let batch = months[chunk..<min(chunk + 4, months.count)]
                let results = await withTaskGroup(of: (Int, MonthData?).self) { group in
                    for month in batch { group.addTask { (month, try? await CVM.month(month, for: ids)) } }
                    return await group.reduce(into: []) { $0.append($1) }
                }
                guard !Task.isCancelled else { return }
                for (month, result) in results {
                    guard let result else { failed = true; continue }
                    for (id, rows) in result.quotas { collected[id, default: []].append(contentsOf: rows) }
                    for (id, summary) in result.summaries { collectedSummaries[id, default: []].append((month, summary)) }
                }
                progress.done += batch.count
            }
            histories = collected.mapValues { rows in
                let sorted = rows.sorted { $0.day < $1.day }
                return PriceHistory(days: sorted.map(\.day), prices: sorted.map(\.quota))
            }
            summaries = collectedSummaries.mapValues { $0.sorted { $0.month < $1.month } }
            if failed { error = "Some months couldn't be downloaded from CVM" }
            isLoading = false
            recompute()
        }
    }

    private static func months(from start: Int, to end: Int) -> [Int] {
        var result: [Int] = [], m = start
        while m <= end {
            result.append(m)
            m = m % 100 == 12 ? (m / 100 + 1) * 100 + 1 : m + 1
        }
        return result
    }

    /// Returns since the range's start for each fund (from its first price, for funds that started later) and CDI.
    func recompute() {
        let start = range.startDay
        let funds = selected.compactMap { s in histories[s.id].map { (id: s.id, history: $0) } }
        guard !funds.isEmpty else { points = []; stats = [:]; return }

        let baseDay = funds.compactMap { f in f.history.days.last { $0 < start } }.max()
        var axis = Set(funds.flatMap { $0.history.days.filter { $0 >= start } }).sorted()
        if let baseDay { axis.insert(baseDay, at: 0) }
        guard let first = axis.first else { points = []; stats = [:]; return }

        let cdiBase = portfolio.cdiLevel(at: first)
        var newStats: [String: FundStats] = [:]
        var bases: [String: (day: Int, price: Double)] = [:]
        for f in funds {
            guard let i = f.history.days.lastIndex(where: { $0 <= first }) ?? f.history.days.firstIndex(where: { $0 >= first }) else { continue }
            bases[f.id] = (f.history.days[i], f.history.prices[i])
        }

        var all = axis.map { day -> FundPoint in
            var point = FundPoint(date: DayKey.date(day))
            for f in funds {
                guard let base = bases[f.id], day >= base.day, let price = f.history.price(onOrBefore: day) else { continue }
                point.returns[f.id] = price / base.price - 1
            }
            if let cdiBase, let level = portfolio.cdiLevel(at: day) { point.cdi = level / cdiBase - 1 }
            return point
        }

        for f in funds {
            guard let base = bases[f.id] else { continue }
            let prices = zip(f.history.days, f.history.prices).filter { $0.0 >= base.day }.map(\.1)
            guard let last = prices.last else { continue }
            let total = last / base.price - 1
            let daily = zip(prices, prices.dropFirst()).map { log($1 / $0) }
            var volatility: Double?
            if daily.count > 20 {
                let mean = daily.reduce(0, +) / Double(daily.count)
                let variance = daily.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(daily.count - 1)
                volatility = sqrt(variance * 252)
            }
            var peak = 0.0, drawdown = 0.0
            for p in prices { peak = max(peak, p); drawdown = min(drawdown, p / peak - 1) }
            var percentOfCDI: Double?
            if let from = portfolio.cdiLevel(at: base.day), let to = portfolio.cdiLevel(at: f.history.days.last!), to > from {
                percentOfCDI = total / (to / from - 1)
            }
            newStats[f.id] = FundStats(totalReturn: total, volatility: volatility, maxDrawdown: drawdown, percentOfCDI: percentOfCDI, firstDay: base.day)
        }

        // Keeps the chart light over 5 years.
        if all.count > 500 {
            let step = Double(all.count - 1) / 499
            all = (0..<500).map { all[Int((Double($0) * step).rounded())] }
        }
        points = all
        stats = newStats
    }
}
