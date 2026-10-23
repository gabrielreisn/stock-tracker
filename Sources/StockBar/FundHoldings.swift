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

/// What a fund is for, for the allocation chart.
enum FundPurpose: String, Codable, CaseIterable, Identifiable {
    case selic, credit, inflation, infrastructure, equities, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .selic: "Selic / DI"
        case .credit: "Private credit (CDI)"
        case .inflation: "Inflation (IPCA)"
        case .infrastructure: "Infrastructure (FIP)"
        case .equities: "Equities"
        case .other: "Other"
        }
    }

    /// From the name, the fund type and CVM's registered benchmark: Selic funds by name, IPCA/NTN-B benchmarks
    /// or names as inflation, FIDCs and credit funds as private credit, FIPs as infrastructure.
    static func infer(name: String, kind: FundHoldingKind, benchmark: String?, category: String?) -> FundPurpose {
        let n = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
        let b = (benchmark ?? "").uppercased(), c = (category ?? "").uppercased()
        if n.contains("SELIC") || c.contains("SOBERANO") && b.contains("DI") { return .selic }
        if n.contains("IPCA") || n.contains("INFLA") || b.contains("IPCA") || b.contains("NTN-B") || b.contains("IMA-B") { return .inflation }
        if kind == .fip { return .infrastructure }
        if c.contains("ACOES") || c.contains("AÇÕES") || n.contains(" ACOES") { return .equities }
        if kind == .fidc || n.contains("CRED") || n.contains(" CP ") || n.contains("CRPR") || c.contains("CREDITO") || c.contains("CRÉDITO") || b.contains("DI") { return .credit }
        return .other
    }
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
    /// Set by hand; nil means inferred (see `FundStore.purpose(of:)`).
    var purpose: FundPurpose?
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

    /// The holding's purpose: the one set by hand, or inferred with CVM's registered benchmark when known.
    func purpose(of h: FundHolding) -> FundPurpose {
        h.purpose ?? inferredPurpose(of: h)
    }

    func inferredPurpose(of h: FundHolding) -> FundPurpose {
        FundPurpose.infer(name: h.name, kind: h.kind, benchmark: registryDetails[h.cnpj]?.benchmark, category: registryDetails[h.cnpj]?.cvmClass)
    }

    /// Registry details for the funds held, for the purpose inference (read from the cached registry once).
    func loadRegistryDetails() async {
        guard registryDetails.isEmpty else { return }
        let all = await CVM.fundDetails()
        registryDetails = all.filter { id, _ in holdings.contains { $0.cnpj == id } }
    }

    func saveHolding(_ holding: FundHolding) {
        if let i = holdings.firstIndex(where: { $0.id == holding.id }) { holdings[i] = holding } else { holdings.append(holding) }
        saveHoldingsFile()
        loadHoldings()
    }

    func deleteHolding(_ holding: FundHolding) {
        holdings.removeAll { $0.id == holding.id }
        saveHoldingsFile()
    }

    private func saveHoldingsFile() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(holdings).write(to: Self.holdingsURL, options: .atomic)
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

    /// Prices for the funds held: the last 13 months first (latest price and returns), then back to 2021
    /// (CVM's first monthly files) for the overview's long ranges. Daily reports for FIFs, monthly for FIDCs.
    func loadHoldings() {
        guard !holdingsLoading else { return }
        holdingsLoading = true
        let current = DayKey.from(.now) / 100
        var months: [Int] = [], m = current
        while m >= CVM.firstMonth {
            months.append(m)
            m = DayKey.addMonths(m * 100 + 1, -1) / 100
        }
        let recent = Array(months.prefix(14)), older = Array(months.dropFirst(14))
        let daily = Set(holdings.filter { $0.kind == .fif }.map(\.cnpj))
        let monthly = Set(holdings.filter { $0.kind == .fidc }.map(\.cnpj))
        Task { @MainActor in
            var rows: [String: [(day: Int, quota: Double)]] = [:]
            @MainActor func publish() {
                holdingSeries = rows.mapValues { r in
                    let sorted = r.sorted { $0.day < $1.day }
                    return PriceHistory(days: sorted.map(\.day), prices: sorted.map(\.quota))
                }
            }
            // A few months at a time: each daily-report month is a ~10 MB download the first time.
            for (index, batch) in [recent, older].enumerated() {
                for chunk in stride(from: 0, to: batch.count, by: 4) {
                    let slice = batch[chunk..<min(chunk + 4, batch.count)]
                    await withTaskGroup(of: [String: [(day: Int, quota: Double)]].self) { group in
                        for month in slice {
                            if !daily.isEmpty { group.addTask { (try? await CVM.month(month, for: daily))?.quotas ?? [:] } }
                            if !monthly.isEmpty { group.addTask { await CVM.fidcQuotas(month: month, for: monthly).mapValues { [$0] } } }
                        }
                        for await result in group {
                            for (id, r) in result { rows[id, default: []].append(contentsOf: r) }
                        }
                    }
                }
                publish()
                if index == 0 { holdingsLoading = false }
            }
        }
    }
}
