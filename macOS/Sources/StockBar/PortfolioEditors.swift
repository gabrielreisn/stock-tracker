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
        VStack(spacing: 0) {
            Form {
                TextField("Ticker", text: $ticker, prompt: Text("PETR4"))
                TextField("Quantity", text: $quantity, prompt: Text("100"))
                TextField("Average price", text: $price, prompt: Text("Optional"))
                if let held { LabeledContent("StockBar now", value: "\(held.quantity.quantity) shares") }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
            }
            .formStyle(.grouped)
            HStack {
                if held != nil {
                    Button("Remove", role: .destructive) { confirmRemove = true }
                        .confirmationDialog("Remove \(symbol) from StockBar?", isPresented: $confirmRemove) {
                            Button("Remove", role: .destructive) { store.removeStock(symbol); dismiss() }
                        }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    save()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text(held == nil ? "Add" : "Save") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(symbol.isEmpty || (parseNumber(quantity) ?? 0) <= 0 || checking)
            }
            .padding(16)
        }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
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
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("CNPJ", text: $cnpj, prompt: Text("00.000.000/0000-00"))
                            .onSubmit(autofill)
                        Button(action: autofill) {
                            if autofilling { ProgressView().controlSize(.mini) } else { Label("Autofill", systemImage: "wand.and.stars") }
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .disabled(cnpj.filter(\.isNumber).count != 14 || autofilling)
                        .help("Fill in the name, type, tax status and latest share price from CVM")
                    }
                } footer: {
                    if let autofillNote { Text(autofillNote).font(.caption).foregroundStyle(.secondary) }
                }
                TextField("Name", text: $holding.name)
                Picker("Type", selection: $holding.kind) {
                    Text("Fund (FIF)").tag(FundHoldingKind.fif)
                    Text("Receivables fund (FIDC)").tag(FundHoldingKind.fidc)
                    Text("Private equity fund (FIP)").tag(FundHoldingKind.fip)
                }
                TextField("Shares", text: $quantity)
                Toggle("Tax exempt", isOn: $holding.taxExempt)
                Picker("Purpose", selection: $holding.purpose) {
                    Text("Automatic (\(funds.inferredPurpose(of: holding).label))").tag(FundPurpose?.none)
                    ForEach(FundPurpose.allCases) { Text($0.label).tag(FundPurpose?.some($0)) }
                }
                Section {
                    TextField("Share price", text: $price, prompt: Text("Optional"))
                    DatePicker("Price date", selection: $priceDate, displayedComponents: .date)
                } footer: {
                    Text("Used until CVM has a newer price (FIDCs report monthly, FIPs quarterly).").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this fund?", isPresented: $confirmDelete) {
                            Button("Delete", role: .destructive) { funds.deleteHolding(holding); dismiss() }
                        }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    if let result { funds.saveHolding(result); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil)
            }
            .padding(16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
