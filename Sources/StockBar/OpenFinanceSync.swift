import Foundation

/// A StockBar position an Open Finance investment refers to.
enum OpenFinanceTarget {
    case stock(Holding), bond(Bond), fund(FundHolding)

    var key: String {
        switch self {
        case .stock(let h): "stock-\(h.ticker)"
        case .bond(let b): "bond-\(b.id)"
        case .fund(let f): "fund-\(f.id)"
        }
    }
}

struct OpenFinanceMatch {
    var target: OpenFinanceTarget?
    var label = ""
    var ours = 0.0
    /// Open Finance's quantity, summed over entries with the same code.
    var quantity = 0.0
    /// For stocks: StockBar's average price and Open Finance's.
    var ourAverage: Double?
    var theirAverage: Double?
    var quantityMatches: Bool { OpenFinanceMatcher.same(ours, quantity) }
    /// Open Finance has an average price and StockBar has none, or one more than 0,5% away.
    var averageDiffers: Bool {
        guard let theirs = theirAverage else { return false }
        guard let ours = ourAverage else { return true }
        return abs(ours / theirs - 1) > 0.005
    }
    var matches: Bool { quantityMatches && !averageDiffers }
}

/// What a sync changed in StockBar to match Open Finance.
struct OpenFinanceChange: Identifiable {
    enum Kind {
        case quantity(from: Double, to: Double)
        case averagePrice
        case price(from: Double?, to: Double, day: Int)
        case removed
    }
    let id = UUID()
    var name: String
    var kind: Kind
}

/// Matches Open Finance investments to what StockBar tracks: stocks by ticker, bonds by code (or issuer and
/// maturity), funds by CNPJ (or name, when Open Finance doesn't give one).
@MainActor
struct OpenFinanceMatcher {
    let store: PortfolioStore
    let funds: FundStore
    let investments: [PluggyInvestment]

    /// Positions already sold come back with zero quantity and balance.
    nonisolated static func isClosed(_ inv: PluggyInvestment) -> Bool { (inv.balance ?? 0) == 0 && (inv.quantity ?? 0) == 0 }

    nonisolated static func normalizedCode(_ inv: PluggyInvestment) -> String {
        (inv.code ?? "").uppercased().replacingOccurrences(of: "CDB-", with: "").trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    nonisolated static func isoDayKey(_ iso: String) -> Int { Int(iso.prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0 }

    nonisolated static func same(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= max(0.0001, abs(b) * 0.0001) }

    var open: [PluggyInvestment] { investments.filter { !Self.isClosed($0) } }

    /// The StockBar position an investment refers to, and how to name it.
    func target(of inv: PluggyInvestment) -> (target: OpenFinanceTarget, label: String)? {
        let code = Self.normalizedCode(inv)
        switch inv.type {
        case "EQUITY", "ETF":
            if let h = store.holdings.first(where: { $0.ticker == code || $0.ticker + "F" == code }) { return (.stock(h), h.ticker) }
        case "FIXED_INCOME":
            let due = inv.dueDate.map(Self.isoDayKey)
            if let b = store.bonds.first(where: { !code.isEmpty && ($0.code == code || code.hasSuffix($0.code)) })
                ?? store.bonds.first(where: { $0.maturityDay == due && Self.fold(inv.issuer ?? inv.name ?? "").contains(Self.fold($0.issuer).prefix(10)) }) {
                return (.bond(b), b.code)
            }
        case "MUTUAL_FUND":
            let digits = [inv.code, inv.number, inv.issuerCNPJ, inv.name].compactMap { $0?.filter(\.isNumber) }
            if let f = funds.holdings.first(where: { h in digits.contains { $0.contains(h.cnpj) } }) { return (.fund(f), CVM.formatCNPJ(f.cnpj)) }
            // By name only when there's no CNPJ to go by: a different fund can share the first words of a name.
            if !digits.contains(where: { $0.count == 14 }),
               let f = funds.holdings.first(where: { Self.fold($0.name).prefix(12) == Self.fold(inv.name ?? "").prefix(12) }) {
                return (.fund(f), CVM.formatCNPJ(f.cnpj))
            }
        default: break
        }
        return nil
    }

    /// One investment against StockBar. The same asset can be split across entries (or institutions), so the
    /// open total of entries with its code is compared.
    func compare(_ inv: PluggyInvestment) -> OpenFinanceMatch {
        let code = Self.normalizedCode(inv)
        let siblings = code.isEmpty ? [inv] : open.filter { $0.type == inv.type && Self.normalizedCode($0) == code }
        var match = OpenFinanceMatch(quantity: siblings.reduce(0) { $0 + ($1.quantity ?? 0) })
        guard let (target, label) = target(of: inv) else { return match }
        (match.target, match.label) = (target, label)
        switch target {
        case .stock(let h):
            match.ours = h.quantity
            match.ourAverage = h.averagePrice
            match.theirAverage = Self.averagePrice(of: siblings)
        case .bond(let b): match.ours = b.quantity
        case .fund(let f): match.ours = f.quantity
        }
        return match
    }

    /// Across split entries, the average weighted by each one's quantity.
    private static func averagePrice(of entries: [PluggyInvestment]) -> Double? {
        let priced = entries.compactMap { s in s.averagePrice.map { (price: $0, quantity: s.quantity ?? 0) } }
        let shares = priced.reduce(0) { $0 + $1.quantity }
        return shares > 0 ? priced.reduce(0) { $0 + $1.price * $1.quantity } / shares : nil
    }

    /// Makes StockBar match Open Finance after a sync:
    /// - quantities of the positions it reports, summed across institutions, and stocks' average prices;
    /// - the price of FIDCs and FIPs, which CVM reports late or not at all. Regular funds keep CVM's daily price,
    ///   which is fresher than what the brokers share;
    /// - positions it reports only as fully withdrawn are removed.
    /// Positions Open Finance doesn't list at all (a pension fund, a broker that isn't connected) are left alone.
    func reconcile() -> [OpenFinanceChange] {
        struct Group { var target: OpenFinanceTarget; var label: String; var entries: [PluggyInvestment] = [] }
        var held: [String: Group] = [:], withdrawn: [String: Group] = [:]
        for inv in investments {
            guard let (target, label) = target(of: inv) else { continue }
            if Self.isClosed(inv) {
                withdrawn[target.key] = Group(target: target, label: label)
            } else {
                held[target.key, default: Group(target: target, label: label)].entries.append(inv)
            }
        }

        var changes: [OpenFinanceChange] = []
        for group in held.values {
            let quantity = group.entries.reduce(0) { $0 + ($1.quantity ?? 0) }
            switch group.target {
            case .stock(let h):
                let average = Self.averagePrice(of: group.entries)
                let averageDiffers = OpenFinanceMatch(ourAverage: h.averagePrice, theirAverage: average).averageDiffers
                guard !Self.same(h.quantity, quantity) || averageDiffers else { continue }
                store.setQuantity(h.ticker, to: quantity, averagePrice: average ?? h.averagePrice)
                changes.append(OpenFinanceChange(name: h.ticker, kind: Self.same(h.quantity, quantity) ? .averagePrice : .quantity(from: h.quantity, to: quantity)))
            case .bond(var b):
                guard !Self.same(b.quantity, quantity) else { continue }
                changes.append(OpenFinanceChange(name: "\(b.kind.rawValue) \(b.issuer)", kind: .quantity(from: b.quantity, to: quantity)))
                b.quantity = quantity
                store.saveBond(b)
            case .fund(var f):
                let before = f
                if !Self.same(f.quantity, quantity) {
                    changes.append(OpenFinanceChange(name: f.name, kind: .quantity(from: f.quantity, to: quantity)))
                    f.quantity = quantity
                }
                if f.kind != .fif, let priced = group.entries.filter({ ($0.value ?? 0) > 0 }).max(by: { ($0.quantity ?? 0) < ($1.quantity ?? 0) }),
                   var price = priced.value {
                    // Some brokers round the share price to cents; then the gross amount over the shares is closer.
                    if (price * 100).rounded() == price * 100, let amount = priced.amount, let shares = priced.quantity, amount > 0, shares > 0 {
                        price = amount / shares
                    }
                    let day = priced.date.map(Self.isoDayKey) ?? DayKey.from(.now)
                    if f.statementPrice.map({ abs($0 - price) > 1e-9 }) ?? true {
                        changes.append(OpenFinanceChange(name: f.name, kind: .price(from: funds.value(f)?.price, to: price, day: day)))
                    }
                    (f.statementPrice, f.statementDay, f.statementFromOpenFinance) = (price, day, true)
                }
                if f != before { funds.saveHolding(f) }
            }
        }
        for (key, group) in withdrawn where held[key] == nil {
            switch group.target {
            case .stock(let h):
                store.removeStock(h.ticker)
                changes.append(OpenFinanceChange(name: h.ticker, kind: .removed))
            case .bond(let b):
                store.deleteBond(b)
                changes.append(OpenFinanceChange(name: "\(b.kind.rawValue) \(b.issuer)", kind: .removed))
            case .fund(let f):
                funds.deleteHolding(f)
                changes.append(OpenFinanceChange(name: f.name, kind: .removed))
            }
        }
        return changes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
