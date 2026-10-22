import Charts
import SwiftUI

/// The funds held, valued at the latest share price from CVM (or the statement, when that's newer).
struct FundHoldingsPage: View {
    @Environment(FundStore.self) private var funds
    @Environment(\.colorScheme) private var scheme
    private static let brazil = Locale(identifier: "pt_BR")

    var body: some View {
        let rows = funds.holdings.map { (holding: $0, value: funds.value($0)) }
            .sorted { ($0.value?.gross ?? 0) > ($1.value?.gross ?? 0) }
        let total = rows.reduce(0) { $0 + ($1.value?.gross ?? 0) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Funds").font(.title2.weight(.semibold))
                    if funds.holdingsLoading { ProgressView().controlSize(.small).padding(.leading, 6) }
                    Spacer()
                }
                if rows.isEmpty {
                    Text("No funds held.").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(40)
                } else {
                    HStack(spacing: 10) {
                        tile("Gross value", total.reais)
                        tile("Last month", weighted(rows, \.month))
                        tile("Year to date", weighted(rows, \.ytd))
                        tile("Last 12 months", weighted(rows, \.year))
                    }
                    table(rows)
                    allocation(rows, total: total)
                    Text("Prices come from CVM: daily reports for regular funds (a day or two behind), monthly reports for FIDCs, and only the statement price for FIPs, which report quarterly. The newer of CVM's price and the statement's is used. Returns are from CVM's history, as of its latest price; holdings without it show —. Values are gross: income tax depends on what you paid for the shares.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
        .task { funds.loadHoldings() }
    }

    /// Value-weighted return over the funds that have one.
    private func weighted(_ rows: [(holding: FundHolding, value: FundHoldingValue?)], _ key: KeyPath<FundHoldingValue, Double?>) -> String {
        var sum = 0.0, weight = 0.0
        for r in rows {
            guard let v = r.value, let x = v[keyPath: key] else { continue }
            sum += x * v.gross
            weight += v.gross
        }
        return weight > 0 ? (sum / weight).signedPercent : "—"
    }

    private func table(_ rows: [(holding: FundHolding, value: FundHoldingValue?)]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Fund").frame(maxWidth: .infinity, alignment: .leading)
                Text("Shares").frame(width: 110, alignment: .trailing)
                Text("Share price").frame(width: 120, alignment: .trailing)
                Text("Gross value").frame(width: 110, alignment: .trailing)
                Text("1M").frame(width: 64, alignment: .trailing)
                Text("YTD").frame(width: 64, alignment: .trailing)
                Text("12M").frame(width: 64, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            Divider()
            ForEach(rows, id: \.holding.id) { row in
                holdingRow(row.holding, row.value)
                Divider().padding(.horizontal, 14)
            }
            HStack {
                Text("Total").fontWeight(.semibold)
                Spacer()
                Text(rows.reduce(0) { $0 + ($1.value?.gross ?? 0) }.reais).fontWeight(.semibold).frame(width: 110, alignment: .trailing)
                Text("").frame(width: 64 * 3 + 16)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private func holdingRow(_ h: FundHolding, _ v: FundHoldingValue?) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(h.name).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(CVM.formatCNPJ(h.cnpj)).font(.caption.monospacedDigit()).textSelection(.enabled)
                    Tag(text: h.kind.label)
                    Tag(text: h.taxExempt ? "Tax exempt" : "Taxable", tint: h.taxExempt ? .green : .secondary)
                }
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(h.quantity.formatted(.number.precision(.fractionLength(0...8)).locale(Self.brazil)))
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
        .frame(height: 52)
    }

    private func percent(_ value: Double?) -> some View {
        Text(value?.signedPercent ?? "—")
            .foregroundStyle((value ?? 0).gainColor)
            .frame(width: 64, alignment: .trailing)
    }

    private func source(_ s: FundHoldingValue.Source) -> String {
        switch s {
        case .cvmDaily: "CVM"
        case .cvmMonthly: "CVM monthly"
        case .statement: "Statement"
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

    private func allocation(_ rows: [(holding: FundHolding, value: FundHoldingValue?)], total: Double) -> some View {
        let palette: [UInt32] = scheme == .dark
            ? [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x9A6FE8]
            : [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x7E4FD6]
        let valued = rows.compactMap { r in r.value.map { (name: r.holding.name, gross: $0.gross) } }
        return HStack(alignment: .center, spacing: 24) {
            Chart(Array(valued.enumerated()), id: \.offset) { i, r in
                SectorMark(angle: .value("Value", r.gross), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(Color(hex: palette[i % palette.count]))
            }
            .frame(width: 180, height: 180)
            VStack(alignment: .leading, spacing: 8) {
                Text("Allocation").font(.headline)
                ForEach(Array(valued.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: palette[i % palette.count])).frame(width: 9, height: 9)
                        Text(r.name).lineLimit(1)
                        Spacer()
                        Text((r.gross / max(total, 1)).percent).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(value.hasPrefix("+") ? .green : value.hasPrefix("-") || value.hasPrefix("−") ? .red : .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Tag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}
