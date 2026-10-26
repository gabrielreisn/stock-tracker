import Foundation

enum BondKind: String, Codable, CaseIterable, Identifiable {
    case cdb = "CDB", lca = "LCA", lci = "LCI", lc = "LC", cri = "CRI", cra = "CRA"
    case debenture = "Debênture", incentivizedDebenture = "Debênture incentivada"
    var id: String { rawValue }

    /// Guaranteed by the FGC (deposits and bank-issued paper); CRI, CRA and debentures aren't.
    var isFGCCovered: Bool { [.cdb, .lca, .lci, .lc].contains(self) }

    /// Exempt from income tax for individuals.
    var isTaxExempt: Bool { [.lca, .lci, .cri, .cra, .incentivizedDebenture].contains(self) }
}

enum BondIndexer: String, Codable, CaseIterable, Identifiable {
    /// `rate` is % a year.
    case fixed
    /// `rate` is % of CDI.
    case cdi
    /// `rate` is % a year on top of CDI.
    case cdiPlus
    /// `rate` is % a year on top of IPCA.
    case ipca
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: String(localized: "Fixed rate")
        case .cdi: String(localized: "% of CDI")
        case .cdiPlus: String(localized: "CDI + spread")
        case .ipca: String(localized: "IPCA + spread")
        }
    }

    func describe(_ rate: Double) -> String {
        let r = rate.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR")))
        return switch self {
        case .fixed: "\(r)% a.a."
        case .cdi: "\(r)% do CDI"
        case .cdiPlus: "CDI + \(r)%"
        case .ipca: "IPCA + \(r)%"
        }
    }
}

/// A fixed-income holding (CDB, LCA, …) bought at issue. Its value is computed from the terms,
/// the same way banks mark it: there's no public price feed for private bonds.
struct Bond: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: BondKind
    var issuer: String
    /// Issuer's CNPJ digits, for the FGC limit (filled from Open Finance when it has them).
    var issuerCNPJ: String?
    var code: String
    var issueDay: Int
    var maturityDay: Int
    var indexer: BondIndexer
    var rate: Double
    var quantity: Double
    /// Price per unit at issue (usually R$ 1.000).
    var unitPrice: Double = 1000

    var invested: Double { quantity * unitPrice }
}

struct BondValuation {
    var unitValue: Double
    var gross: Double
    var incomeTax: Double
    var iof: Double
    var net: Double { gross - incomeTax - iof }
    var gain: Double
    /// Rough value at maturity: exact for fixed rate, today's CDI or the last 12 months' IPCA carried forward otherwise.
    var atMaturity: Double?
}

/// Prices bonds from their terms with the conventions banks use (they reproduce brokerage statements to the cent):
/// business days over 252 with ANBIMA holidays; CDI compounded daily at the contracted share;
/// IPCA stepped on the issue day's monthly anniversary using the latest index published before each period ends.
struct BondPricer {
    /// CDI in % a day by business day, oldest first.
    var cdi: [RatePoint]
    /// IPCA in % a month, keyed by yyyymm.
    var ipca: [Int: Double]

    func value(_ bond: Bond, on day: Int = DayKey.from(.now)) -> BondValuation {
        let end = min(day, bond.maturityDay)
        let factor = growth(bond, from: bond.issueDay, to: end)
        let unit = bond.unitPrice * factor
        let gross = unit * bond.quantity
        let gain = max(0, gross - bond.invested)
        let heldDays = Calendar.current.dateComponents([.day], from: DayKey.date(bond.issueDay), to: DayKey.date(day)).day ?? 0
        let tax = bond.kind.isTaxExempt ? 0 : gain * Self.incomeTaxRate(days: heldDays)
        let iof = heldDays < 30 ? gain * Self.iofRate(days: heldDays) : 0

        var atMaturity: Double?
        if day < bond.maturityDay {
            let remaining = Double(BusinessDays.count(from: day, to: bond.maturityDay))
            let ahead: Double = switch bond.indexer {
            case .fixed: pow(1 + bond.rate / 100, remaining / 252)
            case .cdi: pow(1 + bond.rate / 100 * latestCDI, remaining)
            case .cdiPlus: pow(1 + latestCDI, remaining) * pow(1 + bond.rate / 100, remaining / 252)
            case .ipca: pow((1 + trailingIPCA) * (1 + bond.rate / 100), remaining / 252)
            }
            atMaturity = gross * ahead
        }
        return BondValuation(unitValue: unit, gross: gross, incomeTax: tax, iof: iof, gain: gross - bond.invested, atMaturity: atMaturity)
    }

    private func growth(_ bond: Bond, from start: Int, to end: Int) -> Double {
        guard end > start else { return 1 }
        let du = Double(BusinessDays.count(from: start, to: end))
        return switch bond.indexer {
        case .fixed: pow(1 + bond.rate / 100, du / 252)
        case .cdi: cdiFactor(from: start, to: end, share: bond.rate / 100)
        case .cdiPlus: cdiFactor(from: start, to: end, share: 1) * pow(1 + bond.rate / 100, du / 252)
        case .ipca: ipcaFactor(issue: start, to: end) * pow(1 + bond.rate / 100, du / 252)
        }
    }

    /// Π (1 + share × CDI) over business days in [start, end). Days CDI isn't published for yet repeat the latest rate.
    private func cdiFactor(from start: Int, to end: Int, share: Double) -> Double {
        var factor = 1.0
        var lo = 0, hi = cdi.count
        while lo < hi { let mid = (lo + hi) / 2; if cdi[mid].day < start { lo = mid + 1 } else { hi = mid } }
        var lastDay = start
        for p in cdi[lo...] where p.day < end {
            factor *= 1 + share * p.rate / 100
            lastDay = p.day
        }
        let missing = BusinessDays.count(from: max(start, DayKey.next(lastDay)), to: end)
        if missing > 0 { factor *= pow(1 + share * latestCDI, Double(missing)) }
        return factor
    }

    /// Inflation since issue, stepped on the issue day's monthly anniversary. Each anniversary period uses the
    /// latest IPCA published before it ends (IBGE publishes around the 10th); the running period accrues pro rata
    /// by business days, with the latest published IPCA standing in until its own is out.
    private func ipcaFactor(issue: Int, to end: Int) -> Double {
        let anchor = issue % 100
        var periodStart = DayKey.anniversary(of: anchor, inMonthOf: issue)
        if periodStart > issue { periodStart = DayKey.anniversary(of: anchor, inMonthOf: DayKey.addMonths(issue, -1)) }
        var factor = 1.0
        while true {
            let periodEnd = DayKey.anniversary(of: anchor, inMonthOf: DayKey.addMonths(periodStart, 1))
            let rate = ipca[latestIPCAMonth(publishedBefore: periodEnd)] ?? ipca[ipca.keys.max() ?? 0] ?? 0
            let from = max(periodStart, issue)
            let length = Double(BusinessDays.count(from: periodStart, to: periodEnd))
            if periodEnd >= end {
                let elapsed = Double(BusinessDays.count(from: from, to: end))
                return factor * pow(1 + rate / 100, length > 0 ? elapsed / length : 0)
            }
            let covered = Double(BusinessDays.count(from: from, to: periodEnd))
            factor *= pow(1 + rate / 100, length > 0 ? covered / length : 1)
            periodStart = periodEnd
        }
    }

    /// The month whose IPCA is the newest one out before `day` (IPCA for month m comes out around the 10th of m+1).
    private func latestIPCAMonth(publishedBefore day: Int) -> Int {
        let month = day / 100
        return day % 100 > 10 ? DayKey.addMonths(month * 100 + 1, -1) / 100 : DayKey.addMonths(month * 100 + 1, -2) / 100
    }

    private var latestCDI: Double { (cdi.last?.rate ?? 0) / 100 }

    /// Last 12 published months of IPCA, as a yearly rate.
    private var trailingIPCA: Double {
        let months = ipca.keys.sorted().suffix(12)
        return months.reduce(1.0) { $0 * (1 + (ipca[$1] ?? 0) / 100) } - 1
    }

    /// Regressive income tax on fixed income, by days held.
    static func incomeTaxRate(days: Int) -> Double {
        switch days {
        case ...180: 0.225
        case ...360: 0.20
        case ...720: 0.175
        default: 0.15
        }
    }

    /// IOF on gains redeemed within 30 days: 96% on day 1 down to 0% on day 30.
    static func iofRate(days: Int) -> Double {
        let table = [96, 93, 90, 86, 83, 80, 76, 73, 70, 66, 63, 60, 56, 53, 50, 46, 43, 40, 36, 33, 30, 26, 23, 20, 16, 13, 10, 6, 3, 0]
        guard days >= 1 else { return 1 }
        return days > 30 ? 0 : Double(table[days - 1]) / 100
    }
}

/// B3/ANBIMA business days: weekdays that aren't national holidays (including Carnival, Good Friday and Corpus Christi).
enum BusinessDays {
    private static let holidays: Set<Int> = {
        var set = Set<Int>()
        for year in 2000...2070 {
            for (m, d) in [(1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2), (11, 15), (12, 25)] { set.insert(year * 10_000 + m * 100 + d) }
            if year >= 2024 { set.insert(year * 10_000 + 1120) }  // Black Consciousness Day
            let easter = easterSunday(year)
            for offset in [-48, -47, -2, 60] {
                set.insert(DayKey.from(Calendar.current.date(byAdding: .day, value: offset, to: easter)!))
            }
        }
        return set
    }()

    /// Every business day from 2000 to 2070, sorted, so counting is two binary searches
    /// (pricing a bond on each day of a year would otherwise walk the calendar thousands of times).
    private static let all: [Int] = {
        var days: [Int] = [], date = DayKey.date(20000101)
        let stop = DayKey.date(20701231)
        while date <= stop {
            let day = DayKey.from(date)
            if !holidays.contains(day), !Calendar.current.isDateInWeekend(date) { days.append(day) }
            date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
        }
        return days
    }()

    private static func lowerBound(_ day: Int) -> Int {
        var lo = 0, hi = all.count
        while lo < hi { let mid = (lo + hi) / 2; if all[mid] < day { lo = mid + 1 } else { hi = mid } }
        return lo
    }

    static func isBusinessDay(_ day: Int) -> Bool {
        let i = lowerBound(day)
        return i < all.count && all[i] == day
    }

    /// Business days in [start, end).
    static func count(from start: Int, to end: Int) -> Int {
        end > start ? lowerBound(end) - lowerBound(start) : 0
    }

    /// The business days in [start, end].
    static func days(from start: Int, through end: Int) -> [Int] {
        Array(all[lowerBound(start)..<lowerBound(end + 1)])
    }

    /// Anonymous Gregorian algorithm.
    private static func easterSunday(_ year: Int) -> Date {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31, day = (h + l - 7 * m + 114) % 31 + 1
        return DayKey.date(year * 10_000 + month * 100 + day)
    }
}

extension DayKey {
    static func next(_ day: Int) -> Int { from(Calendar.current.date(byAdding: .day, value: 1, to: date(day))!) }

    static func addMonths(_ day: Int, _ months: Int) -> Int {
        var y = day / 10_000, m = day / 100 % 100 + months
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        return y * 10_000 + m * 100 + min(day % 100, 28) // only year and month matter to callers
    }

    /// The `anchor` day of the month containing `day`, clamped to the month's length.
    static func anniversary(of anchor: Int, inMonthOf day: Int) -> Int {
        let monthStart = day / 100 * 100 + 1
        return day / 100 * 100 + min(anchor, daysInMonth(monthStart))
    }
}
