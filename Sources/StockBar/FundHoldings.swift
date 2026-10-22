import Foundation

enum FundHoldingKind: String, Codable {
    /// Regular fund: daily share prices in CVM's daily reports.
    case fif
    /// Receivables fund: month-end share prices in CVM's monthly FIDC report.
    case fidc
    /// Private equity/infrastructure fund: reports quarterly, so only statement prices.
    case fip

    var label: String { rawValue.uppercased() }
}

/// Shares held in a fund. The statement price is a fallback for funds CVM reports late or rarely (FIDC, FIP);
/// whichever of it and CVM's latest price is newer is used.
struct FundHolding: Codable, Identifiable, Hashable {
    var id = UUID()
    /// CNPJ digits.
    var cnpj: String
    var name: String
    var kind: FundHoldingKind
    var quantity: Double
    /// Exempt from income tax for individuals (incentivized infrastructure funds).
    var taxExempt: Bool
    var statementPrice: Double?
    var statementDay: Int?
}

struct FundHoldingValue {
    enum Source { case cvmDaily, cvmMonthly, statement }

    var price: Double
    var day: Int
    var source: Source
    var gross: Double
    /// From CVM's history, as of its latest price.
    var month: Double?
    var ytd: Double?
    var year: Double?
}

extension FundStore {
    static let holdingsURL = PortfolioStore.directory.appendingPathComponent("fund-holdings.json")

    static func loadHoldingsFile() -> [FundHolding] {
        (try? Data(contentsOf: holdingsURL)).flatMap { try? JSONDecoder().decode([FundHolding].self, from: $0) } ?? []
    }

    /// Price, value and returns for a holding from what's loaded.
    func value(_ h: FundHolding) -> FundHoldingValue? {
        let series = holdingSeries[h.cnpj]
        var price: Double?, day = 0, source = FundHoldingValue.Source.statement
        if let series, let last = series.days.last, let p = series.prices.last {
            (price, day, source) = (p, last, h.kind == .fidc ? .cvmMonthly : .cvmDaily)
        }
        if let sp = h.statementPrice, let sd = h.statementDay, sd > day {
            (price, day, source) = (sp, sd, .statement)
        }
        guard let price else { return nil }

        var value = FundHoldingValue(price: price, day: day, source: source, gross: price * h.quantity)
        if let series, let lastDay = series.days.last, let last = series.prices.last {
            func change(since start: Int) -> Double? {
                guard let base = series.price(onOrBefore: start), base > 0, series.days.first! <= start else { return nil }
                return last / base - 1
            }
            let date = DayKey.date(lastDay)
            value.month = change(since: DayKey.from(Calendar.current.date(byAdding: .month, value: -1, to: date)!))
            value.year = change(since: DayKey.from(Calendar.current.date(byAdding: .year, value: -1, to: date)!))
            value.ytd = change(since: lastDay / 10_000 * 10_000 - 10_000 + 1231)
        }
        return value
    }

    /// Latest prices and 13 months of history for the funds held: daily reports for FIFs, monthly reports for FIDCs.
    func loadHoldings() {
        guard !holdingsLoading else { return }
        holdingsLoading = true
        let current = DayKey.from(.now) / 100
        let months = (0...13).map { DayKey.addMonths(current * 100 + 1, -$0) / 100 }
        let daily = Set(holdings.filter { $0.kind == .fif }.map(\.cnpj))
        let monthly = Set(holdings.filter { $0.kind == .fidc }.map(\.cnpj))
        Task {
            var rows: [String: [(day: Int, quota: Double)]] = [:]
            await withTaskGroup(of: [String: [(day: Int, quota: Double)]].self) { group in
                for month in months {
                    if !daily.isEmpty { group.addTask { (try? await CVM.month(month, for: daily))?.quotas ?? [:] } }
                    if !monthly.isEmpty {
                        group.addTask { await CVM.fidcQuotas(month: month, for: monthly).mapValues { [$0] } }
                    }
                }
                for await result in group {
                    for (id, r) in result { rows[id, default: []].append(contentsOf: r) }
                }
            }
            holdingSeries = rows.mapValues { r in
                let sorted = r.sorted { $0.day < $1.day }
                return PriceHistory(days: sorted.map(\.day), prices: sorted.map(\.quota))
            }
            holdingsLoading = false
        }
    }
}
