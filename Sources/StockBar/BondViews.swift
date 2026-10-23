import Charts
import SwiftUI

enum BondSort: String {
    case issuer, issued, matures, rate, quantity, gross, tax, net, gain
}

/// Fixed-income holdings, grouped by type like a brokerage statement, valued from their terms.
struct BondsPage: View {
    @Environment(PortfolioStore.self) private var store
    @State private var editing: Bond?
    @AppStorage("bondSort") private var sort: BondSort = .matures
    @AppStorage("bondSortAscending") private var ascending = true

    /// Same colors as the maturities chart.
    static let indexerColors: KeyValuePairs<String, Color> = [
        BondIndexer.fixed.label: Color(hex: 0x2A78D6), BondIndexer.cdi.label: Color(hex: 0xEB6834),
        BondIndexer.cdiPlus.label: Color(hex: 0xEDA100), BondIndexer.ipca.label: Color(hex: 0x1BAF7A),
    ]

    static func color(_ indexer: BondIndexer) -> Color {
        indexerColors.first { $0.key == indexer.label }?.value ?? .gray
    }

    var body: some View {
        let pricer = store.bondPricer
        let valued = store.bonds.map { (bond: $0, value: pricer.value($0)) }
        let invested = valued.reduce(0) { $0 + $1.bond.invested }
        let gross = valued.reduce(0) { $0 + $1.value.gross }
        let tax = valued.reduce(0) { $0 + $1.value.incomeTax + $1.value.iof }

        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.spacing) {
                PageHeader(title: "Bonds") {
                    Button { editing = newBond() } label: { Label("Add bond", systemImage: "plus") }
                }
                if store.bonds.isEmpty {
                    emptyState
                } else {
                    TileRow {
                        SummaryTile(title: "Invested", value: invested.reais)
                        SummaryTile(title: "Gross value", value: gross.reais)
                        SummaryTile(title: "Income tax", value: tax > 0 ? "−" + tax.reais : "—")
                        SummaryTile(title: "Net value", value: (gross - tax).reais)
                        SummaryTile(title: "Gain", value: (gross - invested).reais,
                                    detail: invested > 0 ? (gross / invested - 1).signedPercent : nil, tint: (gross - invested).gainColor)
                    }
                    ForEach(BondKind.allCases) { kind in
                        let rows = valued.filter { $0.bond.kind == kind }
                        if !rows.isEmpty { section(kind, sorted(rows)) }
                    }
                    HStack(alignment: .top, spacing: PageLayout.spacing) {
                        allocation(valued)
                        maturityLadder(valued)
                    }
                    Text("Values are computed from each bond's terms the way banks mark them: business days over 252 with ANBIMA holidays, CDI compounded daily at the contracted share, IPCA stepped monthly on the issue-day anniversary. Income tax follows the regressive table (22.5% to 15%) on the gain; LCA, LCI, CRI, CRA and incentivized debentures are exempt.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PageLayout.padding)
        }
        .sheet(item: $editing) { BondForm(bond: $0).environment(store) }
    }

    private var emptyState: some View {
        EmptyPageState(symbol: "banknote", title: "No bonds yet",
                       message: "Add CDBs, LCAs and other fixed income with their rate and dates; their value is updated daily from CDI and IPCA.",
                       addTitle: "Add bond") { editing = newBond() }
    }

    private func newBond() -> Bond {
        let today = DayKey.from(.now)
        return Bond(kind: .cdb, issuer: "", code: "", issueDay: today, maturityDay: DayKey.addMonths(today, 24) / 100 * 100 + today % 100,
                    indexer: .fixed, rate: 0, quantity: 0)
    }

    // MARK: - Table

    private func sorted(_ rows: [(bond: Bond, value: BondValuation)]) -> [(bond: Bond, value: BondValuation)] {
        switch sort {
        case .issuer: rows.sorted(byText: { $0.bond.issuer }, ascending: ascending)
        case .issued: rows.sorted(by: { Double($0.bond.issueDay) }, ascending: ascending)
        case .matures: rows.sorted(by: { Double($0.bond.maturityDay) }, ascending: ascending)
        case .rate: rows.sorted(byText: { $0.bond.indexer.describe($0.bond.rate) }, ascending: ascending)
        case .quantity: rows.sorted(by: { $0.bond.quantity }, ascending: ascending)
        case .gross: rows.sorted(by: { $0.value.gross }, ascending: ascending)
        case .tax: rows.sorted(by: { $0.value.incomeTax + $0.value.iof }, ascending: ascending)
        case .net: rows.sorted(by: { $0.value.net }, ascending: ascending)
        case .gain: rows.sorted(by: { $0.bond.invested > 0 ? $0.value.gross / $0.bond.invested - 1 : nil }, ascending: ascending)
        }
    }

    private func section(_ kind: BondKind, _ rows: [(bond: Bond, value: BondValuation)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(kind.rawValue).font(.headline)
                if kind.isTaxExempt { Text("Tax exempt").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            header
            Divider()
            ForEach(rows, id: \.bond.id) { row in
                BondRow(bond: row.bond, value: row.value) { editing = row.bond }
                Divider().padding(.horizontal, 14)
            }
            let gross = rows.reduce(0) { $0 + $1.value.gross }
            let tax = rows.reduce(0) { $0 + $1.value.incomeTax + $1.value.iof }
            HStack(spacing: 8) {
                Text("Total").fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
                Text(gross.reais).frame(width: BondRow.money, alignment: .trailing)
                Text(tax > 0 ? tax.reais : "—").frame(width: BondRow.tax, alignment: .trailing)
                Text((gross - tax).reais).fontWeight(.semibold).frame(width: BondRow.money, alignment: .trailing)
                Text("").frame(width: BondRow.ret)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .card()
    }

    private var header: some View {
        HStack(spacing: 8) {
            column("Issuer", .issuer, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
            column("Issued", .issued, ascendingFirst: true).frame(width: BondRow.date, alignment: .leading)
            column("Matures", .matures, ascendingFirst: true).frame(width: BondRow.date, alignment: .leading)
            column("Rate", .rate, ascendingFirst: true).frame(width: BondRow.rate, alignment: .leading)
            column("Qty", .quantity).frame(width: BondRow.qty, alignment: .trailing)
            column("Gross", .gross).frame(width: BondRow.money, alignment: .trailing)
            column("Income tax", .tax).frame(width: BondRow.tax, alignment: .trailing)
            column("Net", .net).frame(width: BondRow.money, alignment: .trailing)
            column("Return", .gain).frame(width: BondRow.ret, alignment: .trailing)
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private func column(_ title: String, _ key: BondSort, ascendingFirst: Bool = false) -> some View {
        SortHeader(title: title, key: key, sort: $sort, ascending: $ascending, ascendingFirst: ascendingFirst)
    }

    // MARK: - Allocation and maturities

    /// Net value by indexer, with the bonds in each group named under it.
    private func allocation(_ valued: [(bond: Bond, value: BondValuation)]) -> some View {
        let total = valued.reduce(0) { $0 + $1.value.net }
        let groups = Dictionary(grouping: valued) { $0.bond.indexer }
            .map { (indexer: $0.key, bonds: $0.value.sorted { $0.value.net > $1.value.net }, net: $0.value.reduce(0) { $0 + $1.value.net }) }
            .sorted { $0.net > $1.net }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Allocation by indexer").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                Chart(groups, id: \.indexer) { g in
                    SectorMark(angle: .value("Net value", g.net), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(Self.color(g.indexer))
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.indexer) { g in
                        VStack(alignment: .leading, spacing: 3) {
                            AllocationLine(color: Self.color(g.indexer), title: g.indexer.label, value: g.net, total: total)
                            ForEach(g.bonds, id: \.bond.id) { b in
                                AllocationLine(title: "\(b.bond.issuer) · \(b.bond.indexer.describe(b.bond.rate))", value: b.value.net, total: total)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// Today's net value by the year it matures, split by indexer.
    private func maturityLadder(_ valued: [(bond: Bond, value: BondValuation)]) -> some View {
        struct Slice: Identifiable { var year: Int; var indexer: BondIndexer; var amount: Double; var id: String { "\(year)\(indexer)" } }
        var slices: [String: Slice] = [:]
        for v in valued {
            let s = Slice(year: v.bond.maturityDay / 10_000, indexer: v.bond.indexer, amount: 0)
            slices[s.id, default: s].amount += v.value.net
        }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Maturities").font(.headline)
            Chart(slices.values.sorted { $0.id < $1.id }) { s in
                BarMark(x: .value("Year", String(s.year)), y: .value("Net value", s.amount))
                    .foregroundStyle(by: .value("Indexer", s.indexer.label))
            }
            .chartForegroundStyleScale(Self.indexerColors)
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(v.compactReais) } }
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(minHeight: 220)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

/// One line of an allocation legend: a group (with its color, in bold) or an item under it (indented).
struct AllocationLine: View {
    var color: Color?
    let title: String
    let value: Double
    let total: Double

    var body: some View {
        HStack(spacing: 8) {
            if let color { Circle().fill(color).frame(width: 9, height: 9) }
            Text(title).lineLimit(1).fontWeight(color == nil ? .regular : .semibold)
            Spacer()
            Text(value.reais).monospacedDigit()
            Text(total > 0 ? (value / total).percent : "—").monospacedDigit().frame(width: 48, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .font(color == nil ? .caption : .callout)
        .foregroundStyle(color == nil ? .secondary : .primary)
        .padding(.leading, color == nil ? 17 : 0)
    }
}

private struct BondRow: View {
    static let date: CGFloat = 66, rate: CGFloat = 104, qty: CGFloat = 56, money: CGFloat = 96, tax: CGFloat = 80, ret: CGFloat = 60
    private static let brazil = Locale(identifier: "pt_BR")

    let bond: Bond
    let value: BondValuation
    let onEdit: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bond.issuer).lineLimit(1)
                    Text(bond.code).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(short(bond.issueDay)).frame(width: Self.date, alignment: .leading)
                Text(short(bond.maturityDay)).frame(width: Self.date, alignment: .leading)
                    .foregroundStyle(bond.maturityDay <= DayKey.from(.now) ? .orange : .primary)
                Text(bond.indexer.describe(bond.rate)).frame(width: Self.rate, alignment: .leading)
                Text(bond.quantity.quantity).frame(width: Self.qty, alignment: .trailing)
                Text(value.gross.reais).frame(width: Self.money, alignment: .trailing)
                Text(value.incomeTax + value.iof > 0 ? (value.incomeTax + value.iof).reais : "—").foregroundStyle(.secondary)
                    .frame(width: Self.tax, alignment: .trailing)
                Text(value.net.reais).fontWeight(.medium).frame(width: Self.money, alignment: .trailing)
                Text(bond.invested > 0 ? (value.gross / bond.invested - 1).signedPercent : "—")
                    .foregroundStyle(value.gain.gainColor)
                    .frame(width: Self.ret, alignment: .trailing)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 14)
            .frame(height: PageLayout.rowHeight)
            .background(hovering ? Color.accentColor.opacity(0.08) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }

    private var helpText: String {
        var lines = ["\(bond.kind.rawValue) \(bond.code) · \(bond.quantity.quantity) × \(value.unitValue.formatted(.number.precision(.fractionLength(6)).locale(Self.brazil)))",
                     "Invested \(bond.invested.reais)"]
        if let m = value.atMaturity { lines.append("At maturity (est.): \(m.reais) gross") }
        lines.append("Click to edit")
        return lines.joined(separator: "\n")
    }

    private func short(_ day: Int) -> String {
        DayKey.date(day).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(Self.brazil))
    }
}

/// Add or edit a bond; it's new when the store doesn't have its id yet.
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
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $bond.kind) {
                        ForEach(BondKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Issuer", text: $bond.issuer, prompt: Text("Banco Pine S/A"))
                    TextField("Issuer CNPJ", text: $cnpj, prompt: Text("Optional, for the FGC limit"))
                    TextField("Code", text: $bond.code, prompt: Text("CDB1269LEVF"))
                    DatePicker("Issued", selection: $issued, displayedComponents: .date)
                    DatePicker("Matures", selection: $matures, displayedComponents: .date)
                }
                Section {
                    Picker("Indexer", selection: $bond.indexer) {
                        ForEach(BondIndexer.allCases) { Text($0.label).tag($0) }
                    }
                    TextField(rateLabel, text: $rate, prompt: Text(ratePrompt))
                    TextField("Quantity", text: $quantity, prompt: Text("100"))
                    TextField("Unit price at issue (R$)", text: $unitPrice, prompt: Text("1000"))
                    if let q = parseNumber(quantity), let p = parseNumber(unitPrice) {
                        LabeledContent("Invested", value: (q * p).reais)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                        .confirmationDialog("Delete this bond?", isPresented: $confirmDelete) {
                            Button("Delete", role: .destructive) { store.deleteBond(bond); dismiss() }
                        }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") {
                    if let result { store.saveBond(result); dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil)
            }
            .padding(16)
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rateLabel: String {
        switch bond.indexer {
        case .fixed: "Rate (% a year)"
        case .cdi: "% of CDI"
        case .cdiPlus, .ipca: "Spread (% a year)"
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
