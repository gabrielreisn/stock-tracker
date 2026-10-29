import Charts
import SwiftUI

enum FundSort: String {
    case name, shares, price, gross, month, ytd, year
}

/// The funds held, valued at the latest share price from CVM (or the statement, when that's newer).
struct FundHoldingsPage: View {
    @Environment(FundStore.self) private var funds
    @Environment(\.colorScheme) private var scheme
    @State private var editing: FundHolding?
    @AppStorage("fundSort") private var sort: FundSort = .gross
    @AppStorage("fundSortAscending") private var ascending = false
    private static let brazil = Locale(identifier: "pt_BR")
    private enum Width { static let shares: CGFloat = 110, price: CGFloat = 120, gross: CGFloat = 110, change: CGFloat = 64 }

    var body: some View {
        let rows = sorted(funds.holdings.map { (holding: $0, value: funds.value($0)) })
        let total = rows.reduce(0) { $0 + ($1.value?.gross ?? 0) }

        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.spacing) {
                PageHeader(title: "Funds") {
                    if funds.holdingsLoading { ProgressView().controlSize(.small) }
                    Button { editing = newFund() } label: {
                        Label("Add fund", systemImage: "plus")
                    }
                }
                if rows.isEmpty {
                    EmptyPageState(symbol: "building.columns", title: "No funds yet",
                                   message: "Add the funds you hold with their CNPJ and number of shares; their value follows CVM's daily share prices.",
                                   addTitle: "Add fund") { editing = newFund() }
                } else {
                    TileRow {
                        SummaryTile(title: "Gross value", value: total.reais)
                        returnTile("Last month", weighted(rows, \.month))
                        returnTile("Year to date", weighted(rows, \.ytd))
                        returnTile("Last 12 months", weighted(rows, \.year))
                    }
                    table(rows)
                    allocation(rows, total: total)
                    Text("Prices come from CVM: daily reports for regular funds (a day or two behind) and monthly reports for FIDCs. Each Open Finance sync brings the brokers' share price for FIDCs and FIPs (FIPs only report quarterly), and the newer of CVM's price and that one is used. Returns are from CVM's history, as of its latest price; holdings without it show —. Values are gross: income tax depends on what you paid for the shares.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(PageLayout.padding)
        }
        .sheet(item: $editing) { FundHoldingForm(holding: $0).environment(funds) }
        .task {
            funds.loadHoldings()
            await funds.loadRegistryDetails()
        }
    }

    private func newFund() -> FundHolding {
        FundHolding(cnpj: "", name: "", kind: .fif, quantity: 0, taxExempt: false)
    }

    /// Value-weighted return over the funds that have one.
    private func weighted(_ rows: [(holding: FundHolding, value: FundHoldingValue?)], _ key: KeyPath<FundHoldingValue, Double?>) -> Double? {
        var sum = 0.0, weight = 0.0
        for r in rows {
            guard let v = r.value, let x = v[keyPath: key] else { continue }
            sum += x * v.gross
            weight += v.gross
        }
        return weight > 0 ? sum / weight : nil
    }

    private func returnTile(_ title: LocalizedStringKey, _ value: Double?) -> SummaryTile {
        SummaryTile(title: title, value: value?.signedPercent ?? "—", tint: value.map(\.gainColor))
    }

    private func sorted(_ rows: [(holding: FundHolding, value: FundHoldingValue?)]) -> [(holding: FundHolding, value: FundHoldingValue?)] {
        switch sort {
        case .name: rows.sorted(byText: { $0.holding.name }, ascending: ascending)
        case .shares: rows.sorted(by: { $0.holding.quantity }, ascending: ascending)
        case .price: rows.sorted(by: { $0.value?.price }, ascending: ascending)
        case .gross: rows.sorted(by: { $0.value?.gross }, ascending: ascending)
        case .month: rows.sorted(by: { $0.value?.month }, ascending: ascending)
        case .ytd: rows.sorted(by: { $0.value?.ytd }, ascending: ascending)
        case .year: rows.sorted(by: { $0.value?.year }, ascending: ascending)
        }
    }

    private func column(_ title: LocalizedStringKey, _ key: FundSort, ascendingFirst: Bool = false) -> some View {
        SortHeader(title: title, key: key, sort: $sort, ascending: $ascending, ascendingFirst: ascendingFirst)
    }

    private func table(_ rows: [(holding: FundHolding, value: FundHoldingValue?)]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                column("Fund", .name, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                column("Shares", .shares).frame(width: Width.shares, alignment: .trailing)
                column("Share price", .price).frame(width: Width.price, alignment: .trailing)
                column("Gross value", .gross).frame(width: Width.gross, alignment: .trailing)
                column("1M", .month).frame(width: Width.change, alignment: .trailing)
                column("YTD", .ytd).frame(width: Width.change, alignment: .trailing)
                column("12M", .year).frame(width: Width.change, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            Divider()
            ForEach(rows, id: \.holding.id) { row in
                holdingRow(row.holding, row.value)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = row.holding }
                    .help("Click to edit")
                Divider().padding(.horizontal, 14)
            }
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text(rows.reduce(0) { $0 + ($1.value?.gross ?? 0) }.reais).fontWeight(.semibold).frame(width: Width.gross, alignment: .trailing)
                Text("").frame(width: Width.change * 3 + 16)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .card()
    }

    private func holdingRow(_ h: FundHolding, _ v: FundHoldingValue?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(CVM.formatCNPJ(h.cnpj)).font(.caption.monospacedDigit()).textSelection(.enabled)
                    Tag(text: "\(h.kind.label)")
                    Tag(text: h.taxExempt ? "Tax exempt" : "Taxable", tint: h.taxExempt ? .green : .secondary)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(h.quantity.shares)
                .frame(width: 110, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 1) {
                Text(v.map { $0.price.formatted(.number.precision(.fractionLength(8)).locale(Self.brazil)) } ?? "—")
                if let v {
                    Text("\(source(v.source)) · \(short(v.day))").font(.caption2)
                        .foregroundStyle(isStale(v) ? .orange : .secondary)
                }
            }
            .frame(width: 120, alignment: .trailing)
            Text(v?.gross.reais ?? "—").fontWeight(.medium).frame(width: 110, alignment: .trailing)
            percent(v?.month)
            percent(v?.ytd)
            percent(v?.year)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: PageLayout.rowHeight)
    }

    private func percent(_ value: Double?) -> some View {
        Text(value?.signedPercent ?? "—")
            .foregroundStyle((value ?? 0).gainColor)
            .frame(width: 64, alignment: .trailing)
    }

    private func source(_ s: FundHoldingValue.Source) -> String {
        switch s {
        case .cvmDaily: String(localized: "CVM")
        case .cvmMonthly: String(localized: "CVM monthly")
        case .statement: String(localized: "Statement")
        case .openFinance: "Open Finance"
        }
    }

    /// More than a week old: CVM hasn't caught up, or the statement price is all there is.
    private func isStale(_ v: FundHoldingValue) -> Bool {
        (Calendar.current.dateComponents([.day], from: DayKey.date(v.day), to: .now).day ?? 0) > 7
    }

    private func short(_ day: Int) -> String {
        DayKey.date(day).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(Self.brazil))
    }

    // MARK: - Allocation

    /// By purpose (Selic, credit, inflation…), with the funds in each group named under it.
    private func allocation(_ rows: [(holding: FundHolding, value: FundHoldingValue?)], total: Double) -> some View {
        let palette: [UInt32] = scheme == .dark
            ? [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x9A6FE8]
            : [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x7E4FD6]
        let valued = rows.compactMap { r in r.value.map { (holding: r.holding, gross: $0.gross) } }
        let groups = Dictionary(grouping: valued) { funds.purpose(of: $0.holding) }
            .map { (purpose: $0.key, funds: $0.value.sorted { $0.gross > $1.gross }, gross: $0.value.reduce(0) { $0 + $1.gross }) }
            .sorted { $0.gross > $1.gross }
        // Colors follow FundPurpose's order, so a group keeps its color as values move.
        func color(_ p: FundPurpose) -> Color { Color(hex: palette[(FundPurpose.allCases.firstIndex(of: p) ?? 0) % palette.count]) }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Allocation by purpose").font(.headline)
            HStack(alignment: .top, spacing: 20) {
                Chart(groups, id: \.purpose) { g in
                    SectorMark(angle: .value("Value", g.gross), innerRadius: .ratio(0.6), angularInset: 1.5)
                        .foregroundStyle(color(g.purpose))
                }
                .frame(width: 150, height: 150)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groups, id: \.purpose) { g in
                        VStack(alignment: .leading, spacing: 3) {
                            AllocationLine(color: color(g.purpose), title: g.purpose.label, value: g.gross, total: total)
                            ForEach(g.funds, id: \.holding.id) { f in
                                AllocationLine(title: f.holding.name, value: f.gross, total: total)
                            }
                        }
                    }
                    Text("Grouped from each fund's name, type and CVM benchmark; change a fund's purpose in its form.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

}

private struct Tag: View {
    let text: LocalizedStringKey
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}
