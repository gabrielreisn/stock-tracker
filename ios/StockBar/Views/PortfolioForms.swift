import SwiftUI

/// Add or edit a stock: quantity and average price. Editing when the ticker is already held.
struct StockForm: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var ticker: String
    @State private var quantity: String
    @State private var price: String
    @State private var checking = false
    @State private var error: String?
    @State private var confirmRemove = false

    init(ticker: String, quantity: Double?, averagePrice: Double?) {
        _ticker = State(initialValue: ticker)
        _quantity = State(initialValue: quantity.map(\.editableQuantity) ?? "")
        _price = State(initialValue: averagePrice.map { $0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(Locale(identifier: "pt_BR"))) } ?? "")
    }

    private var symbol: String { ticker.trimmingCharacters(in: .whitespaces).uppercased() }
    private var held: Holding? { store.holdings.first { $0.ticker == symbol } }

    var body: some View {
        CymbaPage {
            CymbaCard {
                CymbaHeading(title: held == nil ? "Add stock" : "Edit stock")
                Text("Ticker").font(.system(size: 14))
                TextField("PETR4 / AAPL", text: $ticker).textFieldStyle(CymbaInputStyle(inset: true)).textInputAutocapitalization(.characters).autocorrectionDisabled().disabled(held != nil || checking).accessibilityLabel("Ticker")
                Text("Shares").font(.system(size: 14))
                TextField("Shares", text: $quantity).textFieldStyle(CymbaInputStyle(inset: true)).keyboardType(.decimalPad).disabled(checking)
                Text("Average price").font(.system(size: 14))
                TextField("Optional", text: $price).textFieldStyle(CymbaInputStyle(inset: true)).keyboardType(.decimalPad).disabled(checking).accessibilityLabel("Average price")
                CymbaCaption(text: "Use the stock currency: BRL for B3, USD for US. Leave average price empty to clear it.")
                if let error { Text(error).font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }.buttonStyle(CymbaActionStyle()).disabled(checking)
                    Button(checking ? "Checking…" : "Save") { save() }.buttonStyle(CymbaActionStyle(primary: true)).disabled(symbol.isEmpty || (parseNumber(quantity) ?? 0) <= 0 || checking || (!price.isEmpty && (parseNumber(price) ?? 0) <= 0))
                }
                if held != nil {
                    Button("Remove", role: .destructive) { confirmRemove = true }.buttonStyle(CymbaActionStyle())
                        .confirmationDialog("Remove stock?", isPresented: $confirmRemove) { Button("Remove", role: .destructive) { store.removeStock(symbol); dismiss() } }
                }
            }
        }
    }

    private func save() {
        guard let q = parseNumber(quantity), q > 0 else { return }
        let average = parseNumber(price).flatMap { $0 > 0 ? $0 : nil }
        if held != nil {
            store.setQuantity(symbol, to: q, averagePrice: average)
            dismiss()
            return
        }
        checking = true
        Task {
            defer { checking = false }
            guard (try? await MarketData.intraday(for: symbol)) != nil else {
                error = "Couldn't find a price for \(symbol)"
                return
            }
            store.add(Trade(ticker: symbol, kind: .buy, date: .now, quantity: q, price: average))
            dismiss()
        }
    }
}

/// Add or edit a fund held; new when the store doesn't have its id yet.
struct FundHoldingForm: View {
    @Environment(FundStore.self) private var funds
    @Environment(\.dismiss) private var dismiss
    @State private var holding: FundHolding
    @State private var cnpj: String
    @State private var quantity: String
    @State private var price: String
    @State private var priceDate: Date
    @State private var confirmDelete = false
    @State private var autofilling = false
    @State private var autofillNote: String?

    init(holding: FundHolding) {
        _holding = State(initialValue: holding)
        _cnpj = State(initialValue: CVM.formatCNPJ(holding.cnpj))
        _quantity = State(initialValue: holding.quantity > 0 ? holding.quantity.formatted(.number.precision(.fractionLength(0...8)).grouping(.never).locale(Locale(identifier: "pt_BR"))) : "")
        _price = State(initialValue: holding.statementPrice.map { $0.formatted(.number.precision(.fractionLength(0...8)).grouping(.never).locale(Locale(identifier: "pt_BR"))) } ?? "")
        _priceDate = State(initialValue: holding.statementDay.map(DayKey.date) ?? .now)
    }

    /// Name, type, tax status and the latest share price from CVM's registry and reports. Shares stay with the user.
    private func autofill() {
        let digits = cnpj.filter(\.isNumber)
        guard digits.count == 14, !autofilling else { return }
        autofilling = true
        autofillNote = "Looking up \(CVM.formatCNPJ(digits)) in CVM's registry…"
        Task {
            defer { autofilling = false }
            guard let fund = await CVM.registeredFund(cnpj: digits) else {
                autofillNote = "CVM's registry has no operating fund with this CNPJ."
                return
            }
            cnpj = CVM.formatCNPJ(digits)
            holding.name = fund.name
            switch fund.type {
            case "FIDC": holding.kind = .fidc
            case "FIP": holding.kind = .fip
            default: holding.kind = .fif
            }
            let folded = fund.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
            holding.taxExempt = folded.contains("INCENTIVAD") || folded.contains("INFRAESTRUTURA") || folded.contains("INFRA ")
            var filled = ["name", "type", "tax status"]
            if let quote = await CVM.latestQuota(cnpj: digits, type: fund.type) {
                price = quote.quota.formatted(.number.precision(.fractionLength(0...8)).grouping(.never).locale(Locale(identifier: "pt_BR")))
                priceDate = DayKey.date(quote.day)
                filled.append("share price of \(DayKey.date(quote.day).formatted(date: .abbreviated, time: .omitted))")
            }
            autofillNote = "Filled \(filled.joined(separator: ", ")) from CVM (\(fund.type)). Enter your shares."
                + (fund.type == "FIP" ? " FIPs don't publish daily prices: add the statement's." : "")
        }
    }

    private var isNew: Bool { !funds.holdings.contains { $0.id == holding.id } }

    private var result: FundHolding? {
        let digits = cnpj.filter(\.isNumber)
        guard digits.count == 14, !holding.name.trimmingCharacters(in: .whitespaces).isEmpty,
              let q = parseNumber(quantity), q > 0 else { return nil }
        var h = holding
        h.cnpj = digits
        h.quantity = q
        h.statementPrice = parseNumber(price).flatMap { $0 > 0 ? $0 : nil }
        h.statementDay = h.statementPrice == nil ? nil : DayKey.from(priceDate)
        // A price changed by hand is the user's own, not Open Finance's anymore.
        if h.statementPrice != holding.statementPrice || h.statementDay != holding.statementDay { h.statementFromOpenFinance = nil }
        return h
    }

    var body: some View {
        CymbaPage {
            CymbaHeading(title: isNew ? "Add fund" : "Edit fund", size: 22)
            HStack(alignment: .bottom, spacing: 12) {
                CymbaField(title: "CNPJ", text: $cnpj, prompt: "00.000.000/0000-00")
                Button { autofill() } label: { if autofilling { ProgressView() } else { Text("Autofill") } }.buttonStyle(CymbaActionStyle()).fixedSize(horizontal: true, vertical: false).disabled(cnpj.filter(\.isNumber).count != 14 || autofilling)
            }
            if let autofillNote { CymbaCaption(text: LocalizedStringKey(autofillNote)) }
            CymbaField(title: "Name", text: $holding.name)
            Picker("Type", selection: $holding.kind) { Text("Fund (FIF)").tag(FundHoldingKind.fif); Text("Receivables fund (FIDC)").tag(FundHoldingKind.fidc); Text("Private equity fund (FIP)").tag(FundHoldingKind.fip) }.tint(CymbaTheme.text)
            CymbaField(title: "Shares", text: $quantity, numeric: true)
            Toggle("Tax exempt", isOn: $holding.taxExempt).tint(CymbaTheme.accent)
            Picker("Purpose", selection: $holding.purpose) {
                Text("Automatic").tag(FundPurpose?.none)
                ForEach(FundPurpose.allCases) { Text($0.label).tag(FundPurpose?.some($0)) }
            }.tint(CymbaTheme.text)
            CymbaField(title: "Share price", text: $price, prompt: "Optional", numeric: true)
            DatePicker("Price date", selection: $priceDate, displayedComponents: .date).tint(CymbaTheme.accent)
            CymbaCaption(text: "Used until CVM has a newer price (FIDCs report monthly, FIPs quarterly).")
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(CymbaActionStyle())
                Button("Save") { if let result { funds.saveHolding(result); dismiss() } }.buttonStyle(CymbaActionStyle(primary: true)).disabled(result == nil)
            }
            if !isNew { Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(CymbaActionStyle()).confirmationDialog("Delete this fund?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { funds.deleteHolding(holding); dismiss() } } }
        }
    }
}

struct BondForm: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var bond: Bond
    @State private var issued: Date
    @State private var matures: Date
    @State private var rate: String
    @State private var quantity: String
    @State private var unitPrice: String
    @State private var confirmDelete = false
    @State private var cnpj: String

    init(bond: Bond) {
        _bond = State(initialValue: bond)
        _cnpj = State(initialValue: bond.issuerCNPJ.map(CVM.formatCNPJ) ?? "")
        _issued = State(initialValue: DayKey.date(bond.issueDay))
        _matures = State(initialValue: DayKey.date(bond.maturityDay))
        _rate = State(initialValue: bond.rate > 0 ? bond.rate.editableQuantity : "")
        _quantity = State(initialValue: bond.quantity > 0 ? bond.quantity.editableQuantity : "")
        _unitPrice = State(initialValue: bond.unitPrice.editableQuantity)
    }

    private var isNew: Bool { !store.bonds.contains { $0.id == bond.id } }

    private var result: Bond? {
        guard !bond.issuer.trimmingCharacters(in: .whitespaces).isEmpty,
              let r = parseNumber(rate), r > 0, let q = parseNumber(quantity), q > 0,
              let p = parseNumber(unitPrice), p > 0, issued < matures else { return nil }
        var b = bond
        b.issuer = b.issuer.trimmingCharacters(in: .whitespaces)
        b.code = b.code.trimmingCharacters(in: .whitespaces).uppercased()
        let digits = cnpj.filter(\.isNumber)
        guard digits.isEmpty || digits.count == 14 else { return nil }
        b.issuerCNPJ = digits.isEmpty ? nil : digits
        b.rate = r
        b.quantity = q
        b.unitPrice = p
        b.issueDay = DayKey.from(issued)
        b.maturityDay = DayKey.from(matures)
        return b
    }

    var body: some View {
        CymbaPage {
            CymbaHeading(title: isNew ? "Add bond" : "Edit bond", size: 22)
            Picker("Type", selection: $bond.kind) { ForEach(BondKind.allCases) { Text($0.rawValue).tag($0) } }.tint(CymbaTheme.text)
            CymbaField(title: "Issuer", text: $bond.issuer, prompt: "Banco Pine S/A", identifier: "bondIssuer")
            CymbaField(title: "Issuer CNPJ", text: $cnpj, prompt: "Optional, for the FGC limit")
            CymbaField(title: "Code", text: $bond.code, prompt: "CDB1269LEVF")
            DatePicker("Issued", selection: $issued, displayedComponents: .date).tint(CymbaTheme.accent)
            DatePicker("Matures", selection: $matures, displayedComponents: .date).tint(CymbaTheme.accent)
            Picker("Indexer", selection: $bond.indexer) { ForEach(BondIndexer.allCases) { Text($0.label).tag($0) } }.tint(CymbaTheme.text)
            CymbaField(title: LocalizedStringKey(rateLabel), text: $rate, prompt: LocalizedStringKey(ratePrompt), numeric: true)
            CymbaField(title: "Quantity", text: $quantity, prompt: "100", numeric: true)
            CymbaField(title: "Unit price at issue (R$)", text: $unitPrice, prompt: "1000", numeric: true)
            if let q = parseNumber(quantity), let p = parseNumber(unitPrice) { CymbaCard { MoneyRow(title: String(localized: "Invested"), value: (q * p).reais) } }
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }.buttonStyle(CymbaActionStyle())
                Button("Save") { if let result { store.saveBond(result); dismiss() } }.buttonStyle(CymbaActionStyle(primary: true)).disabled(result == nil)
            }
            if !isNew { Button("Delete", role: .destructive) { confirmDelete = true }.buttonStyle(CymbaActionStyle()).confirmationDialog("Delete this bond?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { store.deleteBond(bond); dismiss() } } }
        }
    }

    private var rateLabel: String {
        switch bond.indexer {
        case .fixed: String(localized: "Rate (% a year)")
        case .cdi: String(localized: "% of CDI")
        case .cdiPlus, .ipca: String(localized: "Spread (% a year)")
        }
    }

    private var ratePrompt: String {
        switch bond.indexer {
        case .fixed: "15,16"
        case .cdi: "92"
        case .cdiPlus: "1,5"
        case .ipca: "8,45"
        }
    }
}
