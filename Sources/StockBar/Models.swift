import Foundation

enum TradeKind: String, Codable, CaseIterable, Identifiable {
    case buy, sell
    var id: String { rawValue }
    var label: String { self == .buy ? "Buy" : "Sell" }
}

/// Only what the user knows offhand: prices come from the market history for that date.
struct Trade: Codable, Identifiable, Hashable {
    var id = UUID()
    var ticker: String
    var kind: TradeKind
    var date: Date
    var quantity: Double
    /// Price paid per share, in the stock's own currency (dollars for US stocks).
    var price: Double?

    var dayKey: Int { DayKey.from(date) }
    var signedQuantity: Double { kind == .buy ? quantity : -quantity }
}

/// Daily adjusted closes (dividends and splits folded in), so returns are total returns.
struct PriceHistory: Codable, Sendable {
    var days: [Int]
    var prices: [Double]
    var name: String?
    /// Cash per share by ex-date, in the stock's own currency (Yahoo's dividend events).
    var dividends: [ExDividend]?

    /// Last close on or before `day` (trades on weekends/holidays use the previous session).
    func price(onOrBefore day: Int) -> Double? {
        var lo = 0, hi = days.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if days[mid] <= day { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? prices[lo - 1] : nil
    }

    var last: Double? { prices.last }
    var previous: Double? { prices.count > 1 ? prices[prices.count - 2] : nil }
}

struct ExDividend: Codable, Sendable, Hashable {
    var day: Int
    var amount: Double
}

enum DividendKind: String, Hashable {
    case dividend, jcp, income
    var label: String {
        switch self {
        case .dividend: "Dividend"
        case .jcp: "JCP"
        case .income: "Income"
        }
    }
}

/// A cash payment on a held stock: per-share amount times today's quantity, in reais.
struct DividendPayment: Identifiable, Hashable {
    var ticker: String
    var kind: DividendKind
    /// Last day to hold the stock to get it ("data com"), or the ex-date when that's all the source gives.
    var recordDay: Int
    /// nil while the company hasn't set it (common for JCP), or when the source only has ex-dates.
    var paymentDay: Int?
    /// Yahoo's events only carry the ex-date; B3's announcements carry the record and payment dates.
    var datedByExDate = false
    var perShare: Double
    var quantity: Double
    var amount: Double

    var id: String { "\(ticker)-\(kind.rawValue)-\(recordDay)-\(paymentDay ?? 0)-\(perShare)" }
    /// The month it lands in: payment day, or the record day while that's unknown.
    var day: Int { paymentDay ?? recordDay }

    func isPaid(asOf today: Int) -> Bool {
        datedByExDate ? recordDay <= today : paymentDay.map { $0 <= today } ?? false
    }
}

/// One session of 5-minute prices; `last` is the live price.
struct IntradaySeries: Sendable {
    var day: Int
    var times: [Date]
    var prices: [Double]
    var previousClose: Double
    var last: Double

    func price(at time: Date) -> Double? {
        guard let i = times.lastIndex(where: { $0 <= time }) else { return nil }
        return prices[i]
    }
}

/// Notifies once when a ticker reaches a target, in its own currency: buy alerts fire at or below it, sell alerts at or above.
/// A fired alert switches itself off; switching it back on re-arms it.
struct PriceAlert: Codable, Identifiable, Hashable {
    var id = UUID()
    var ticker: String
    var target: Double
    var kind: TradeKind
    var isEnabled = true
    var triggeredAt: Date?

    func isMet(by price: Double) -> Bool { kind == .buy ? price <= target : price >= target }
    var condition: String { kind == .buy ? "at or below" : "at or above" }
}

struct Holding: Identifiable {
    var ticker: String
    var name: String?
    var quantity: Double
    /// Average price paid per share, in the stock's own currency.
    var averagePrice: Double?
    var weight: Double = 0

    var id: String { ticker }
    var isUS: Bool { !MarketData.isB3(ticker) }
}

enum BenchmarkID: String, CaseIterable, Identifiable, Codable {
    case cdi, ipca, sp500, ipcaPlus6, ifix, ibov
    var id: String { rawValue }

    /// More lines than this can't all be told apart by color, so the chart caps them.
    static let maxEnabled = 3

    /// Rate-based benchmarks are drawn dashed — a second cue besides color.
    var isRate: Bool { self == .cdi || self == .ipca || self == .ipcaPlus6 }

    var label: String {
        switch self {
        case .cdi: "CDI"
        case .ipca: "IPCA"
        case .sp500: "S&P 500"
        case .ipcaPlus6: "IPCA+6%"
        case .ifix: "IFIX"
        case .ibov: "IBOV"
        }
    }

    var detail: String {
        switch self {
        case .cdi: "Interbank deposit rate, the usual fixed-income yardstick. Banco Central, series 12."
        case .ipca: "Official inflation. IBGE, via Banco Central series 433."
        case .sp500: "S&P 500 with dividends reinvested (^SP500TR), converted to reais at USD/BRL."
        case .ipcaPlus6: "Inflation plus a 6% real return a year — a typical long-term target."
        case .ifix: "B3's real-estate fund (FII) index, with distributions reinvested. Starts Dec 2010."
        case .ibov: "Ibovespa, B3's main stock index (a total-return index), via Yahoo (^BVSP)."
        }
    }
}

/// Return since the start of the chart's range, for the portfolio and each benchmark that has data.
struct PerformancePoint: Identifiable {
    var date: Date
    var portfolio: Double
    var benchmarks: [BenchmarkID: Double] = [:]

    var id: Date { date }
}

/// Daily (CDI) or monthly (IPCA) rate, in percent, keyed by yyyymmdd.
struct RatePoint: Codable, Sendable {
    var day: Int
    var rate: Double
}

/// Dates as yyyymmdd integers, so trade dates and market dates compare without time-zone surprises.
enum DayKey {
    static func from(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return c.year! * 10_000 + c.month! * 100 + c.day!
    }

    static func date(_ key: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: key / 10_000, month: key / 100 % 100, day: key % 100, hour: 12))!
    }

    /// Parses BCB's "dd/MM/yyyy".
    static func parse(_ string: String) -> Int? {
        let parts = string.split(separator: "/").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[2] * 10_000 + parts[1] * 100 + parts[0]
    }

    static func daysInMonth(_ key: Int) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date(key))?.count ?? 30
    }
}
