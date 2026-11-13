import Foundation

/// Imports complete bank snapshots. Incomplete positions stay in Open Finance for manual review.
@MainActor
enum OpenFinanceImporter {
    static func apply(_ investments: [PluggyInvestment], completedItems: Set<String>, store: PortfolioStore, funds: FundStore, reconcile: Bool = true) -> [OpenFinanceChange] {
        let active = investments.filter { !OpenFinanceMatcher.isClosed($0) && ($0.quantity ?? 0) > 0 && completedItems.contains($0.itemId ?? "") }
        let groups = Dictionary(grouping: active) { inv in
            (inv.type ?? "") + ":" + (inv.type == "MUTUAL_FUND" ? cnpj(inv) ?? inv.id : OpenFinanceMatcher.normalizedCode(inv))
        }
        for entries in groups.values {
            guard let inv = entries.first else { continue }
            let matcher = OpenFinanceMatcher(store: store, funds: funds, investments: investments)
            guard matcher.target(of: inv) == nil else { continue }
            let quantity = entries.reduce(0) { $0 + ($1.quantity ?? 0) }
            let code = OpenFinanceMatcher.normalizedCode(inv)
            switch inv.type {
            case "EQUITY", "ETF":
                guard !code.isEmpty, code.range(of: #"^[A-Z][A-Z0-9.\-]{0,19}$"#, options: .regularExpression) != nil else { continue }
                let ticker = code.range(of: #"^[A-Z]{4}\d{1,2}F$"#, options: .regularExpression) != nil ? String(code.dropLast()) : code
                store.add(Trade(ticker: ticker, kind: .buy, date: .now, quantity: quantity, price: OpenFinanceMatcher.averagePrice(of: entries)))
            case "FIXED_INCOME":
                guard let bond = bond(inv, quantity: quantity, cost: OpenFinanceMatcher.averagePrice(of: entries)) else { continue }
                store.saveBond(bond)
            case "MUTUAL_FUND":
                guard let digits = cnpj(inv) else { continue }
                let name = inv.name ?? digits
                let text = "\(inv.subtype ?? "") \(name)".uppercased()
                let kind: FundHoldingKind = text.contains("FIDC") ? .fidc : text.contains("FIP") ? .fip : .fif
                let latest = entries.max { ($0.date ?? "") < ($1.date ?? "") } ?? inv
                let price = latest.value ?? latest.amount.flatMap { amount in latest.quantity.flatMap { $0 > 0 ? amount / $0 : nil } }
                funds.saveHolding(FundHolding(cnpj: digits, name: name, kind: kind, quantity: quantity,
                    taxExempt: text.contains("INCENT") || text.contains("INFRA"), statementPrice: price,
                    statementDay: latest.date.map(OpenFinanceMatcher.isoDayKey), statementFromOpenFinance: true))
            default: continue
            }
        }
        return reconcile ? OpenFinanceMatcher(store: store, funds: funds, investments: investments).reconcile(updatedItems: completedItems) : []
    }

    static func cnpj(_ inv: PluggyInvestment) -> String? {
        [inv.code, inv.number].compactMap { $0?.filter(\.isNumber) }.first { $0.count == 14 }
    }

    static func bond(_ inv: PluggyInvestment, quantity: Double, cost: Double?) -> Bond? {
        guard let cost, cost > 0,
              let start = (inv.issueDate ?? inv.purchaseDate).map(OpenFinanceMatcher.isoDayKey),
              let end = inv.dueDate.map(OpenFinanceMatcher.isoDayKey),
              validDay(start), validDay(end), end > start,
              let kind = bondKind(inv.subtype), inv.rate != nil || inv.fixedAnnualRate != nil else { return nil }
        let index = (inv.rateType ?? "").uppercased()
        let share = inv.rate ?? 0, fixed = inv.fixedAnnualRate ?? 0
        let indexer: BondIndexer
        let rate: Double
        if index.contains("IPCA") { indexer = .ipca; rate = fixed > 0 ? fixed : share }
        else if share == 0 { indexer = .fixed; rate = fixed }
        else if index.contains("CDI") || index == "DI" || index.contains("SELIC") { indexer = fixed > 0 ? .cdiPlus : .cdi; rate = fixed > 0 ? fixed : share }
        else { return nil }
        guard rate > 0, !OpenFinanceMatcher.normalizedCode(inv).isEmpty else { return nil }
        return Bond(kind: kind, issuer: inv.issuer ?? inv.name ?? "", issuerCNPJ: inv.issuerCNPJ,
                    code: OpenFinanceMatcher.normalizedCode(inv), issueDay: start, maturityDay: end,
                    indexer: indexer, rate: rate, quantity: quantity, unitPrice: cost)
    }
    private static func validDay(_ day: Int) -> Bool { day >= 19000101 && day <= 99991231 && DayKey.from(DayKey.date(day)) == day }
    private static func bondKind(_ subtype: String?) -> BondKind? {
        switch subtype?.uppercased() {
        case "CDB": .cdb
        case "LCA": .lca
        case "LCI": .lci
        case "LC": .lc
        case "CRI": .cri
        case "CRA": .cra
        case "DEBENTURE": .debenture
        case "INCENTIVIZED_DEBENTURE": .incentivizedDebenture
        default: nil
        }
    }
}
