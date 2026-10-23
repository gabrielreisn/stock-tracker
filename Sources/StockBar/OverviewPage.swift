import Charts
import SwiftUI

enum AssetClass: String, CaseIterable, Identifiable {
    case stocks = "Stocks", bonds = "Bonds", funds = "Funds"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .stocks: Color(hex: 0x2A78D6)
        case .bonds: Color(hex: 0x1BAF7A)
        case .funds: Color(hex: 0xEB6834)
        }
    }
}

/// The whole portfolio: stocks, bonds and funds valued together, and one return curve for all of it.
struct Overview {
    static let ranges: [ChartRange] = [.quarter, .ytd, .year, .threeYears, .fiveYears, .all]

    struct Position: Identifiable {
        var name: String
        var detail: String
        var assetClass: AssetClass
        var value: Double
        var id: String { "\(assetClass.rawValue)-\(name)-\(detail)" }
    }

    /// The allocation donut's slices: like the asset classes, with stocks split by market.
    struct Slice: Identifiable {
        var label: String
        var color: Color
        var value: Double
        var id: String { label }
    }

    var values: [AssetClass: Double] = [:]
    var slices: [Slice] = []
    var positions: [Position] = []
    var curves: [ChartRange: [PerformancePoint]] = [:]
    var classReturns: [ChartRange: [AssetClass: Double]] = [:]
    var total: Double { values.values.reduce(0, +) }

    /// Each business day's return weights every holding by its value the day before, like the stock curve:
    /// stocks at their closes, bonds priced from their terms (from their issue day), funds at CVM's share prices.
    /// Holdings with no history (FIPs priced only from a statement) count in the value but not in the return.
    @MainActor
    init(store: PortfolioStore, funds: FundStore) {
        let today = DayKey.from(.now)
        let pricer = store.bondPricer

        // Today's values and the positions behind them.
        for h in store.holdings {
            positions.append(Position(name: h.ticker, detail: h.name ?? "", assetClass: .stocks, value: h.weight * store.totalValue))
        }
        for b in store.bonds {
            positions.append(Position(name: "\(b.kind.rawValue) \(b.issuer)", detail: "\(b.indexer.describe(b.rate)) · \(b.code)", assetClass: .bonds, value: pricer.value(b).gross))
        }
        for h in funds.holdings {
            positions.append(Position(name: h.name, detail: CVM.formatCNPJ(h.cnpj), assetClass: .funds, value: funds.value(h)?.gross ?? 0))
        }
        positions.sort { $0.value > $1.value }
        for p in positions { values[p.assetClass, default: 0] += p.value }

        let usStocks = store.holdings.filter(\.isUS).reduce(0) { $0 + $1.weight * store.totalValue }
        slices = [
            Slice(label: "Stocks B3", color: AssetClass.stocks.color, value: (values[.stocks] ?? 0) - usStocks),
            Slice(label: "Stocks US", color: Color(hex: 0x7E4FD6), value: usStocks),
            Slice(label: AssetClass.bonds.rawValue, color: AssetClass.bonds.color, value: values[.bonds] ?? 0),
            Slice(label: AssetClass.funds.rawValue, color: AssetClass.funds.color, value: values[.funds] ?? 0),
        ].filter { $0.value > 0 }

        // A value series per holding over the business days of the longest range, plus a few days for its base.
        let axis = BusinessDays.days(from: DayKey.addMonths(Overview.ranges.map(\.startDay).min()!, -1), through: today)
        guard axis.count > 1 else { return }
        var series: [(AssetClass, [Double?])] = []
        let stockPrices = store.stockHistoriesInReais()
        for h in store.holdings {
            guard let history = stockPrices[h.ticker], let first = history.days.first else { continue }
            series.append((.stocks, axis.map { $0 >= first ? history.price(onOrBefore: $0).map { $0 * h.quantity } : nil }))
        }
        for b in store.bonds {
            series.append((.bonds, axis.map { $0 >= b.issueDay && $0 <= b.maturityDay ? pricer.value(b, on: $0).gross : nil }))
        }
        for h in funds.holdings {
            guard let history = funds.holdingSeries[h.cnpj], let first = history.days.first else { continue }
            series.append((.funds, axis.map { $0 >= first ? history.price(onOrBefore: $0).map { $0 * h.quantity } : nil }))
        }

        // Chain-linked indices for the whole portfolio and each asset class.
        var index = 1.0
        var classIndex = Dictionary(uniqueKeysWithValues: AssetClass.allCases.map { ($0, 1.0) })
        var daily = [(day: axis[0], value: 1.0)]
        var classDaily: [AssetClass: [(day: Int, value: Double)]] = Dictionary(uniqueKeysWithValues: AssetClass.allCases.map { ($0, [(axis[0], 1.0)]) })
        for i in 1..<axis.count {
            var before = 0.0, after = 0.0
            var classBefore: [AssetClass: Double] = [:], classAfter: [AssetClass: Double] = [:]
            for (assetClass, values) in series {
                guard let v0 = values[i - 1], let v1 = values[i], v0 > 0 else { continue }
                before += v0; after += v1
                classBefore[assetClass, default: 0] += v0
                classAfter[assetClass, default: 0] += v1
            }
            if before > 0 { index *= after / before }
            daily.append((axis[i], index))
            for c in AssetClass.allCases {
                if let b = classBefore[c], b > 0 { classIndex[c]! *= classAfter[c]! / b }
                classDaily[c]!.append((axis[i], classIndex[c]!))
            }
        }

        for range in Overview.ranges {
            curves[range] = store.performance(of: daily, from: range.startDay)
            var returns: [AssetClass: Double] = [:]
            for c in AssetClass.allCases where values[c] ?? 0 > 0 {
                let d = classDaily[c]!
                guard let base = d.last(where: { $0.day < range.startDay }), let last = d.last, base.value > 0 else { continue }
                returns[c] = last.value / base.value - 1
            }
            classReturns[range] = returns
        }
    }
}

struct OverviewPage: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @AppStorage("overviewRange") private var range: ChartRange = .ytd
    @State private var overview: Overview?

    /// Recompute when prices, bonds or funds change, not on every hover redraw.
    private var fingerprint: String {
        [store.lastUpdated?.timeIntervalSince1970.description ?? "",
         store.holdings.map { "\($0.ticker)\($0.quantity)" }.joined(),
         store.bonds.map { "\($0.id)\($0.quantity)\($0.rate)" }.joined(),
         funds.holdings.map { "\($0.id)\($0.quantity)" }.joined(),
         String(funds.holdingSeriesVersion), String(funds.holdingsLoading)].joined(separator: "|")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview").font(.title2.weight(.semibold))
                if let overview {
                    tiles(overview)
                    PerformanceSection(chartHeight: 320, curves: overview.curves, ranges: Overview.ranges, rangeKey: "overviewRange")
                        .padding(6)
                        .card()
                    HStack(alignment: .top, spacing: 20) {
                        allocation(overview)
                        largest(overview)
                    }
                    Text("The curve treats today's holdings as held through the whole range: each day's return weights stocks, bonds and funds by their value the day before. Bonds are priced from their terms and join on their issue day; funds use CVM's share prices; holdings without a price history (FIPs) count in the total but not in the return. Values are gross of tax.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(24)
        }
        .task(id: fingerprint) { overview = Overview(store: store, funds: funds) }
    }

    private func tiles(_ o: Overview) -> some View {
        HStack(spacing: 10) {
            tile("Total", value: o.total, share: nil, change: o.curves[range]?.last?.portfolio)
            ForEach(AssetClass.allCases) { c in
                tile(c.rawValue, value: o.values[c] ?? 0, share: o.total > 0 ? (o.values[c] ?? 0) / o.total : nil,
                     change: o.classReturns[range]?[c], color: c.color)
            }
        }
    }

    private func tile(_ title: String, value: Double, share: Double?, change: Double?, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if let color { Circle().fill(color).frame(width: 8, height: 8) }
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let share { Text(share.percent).font(.caption).foregroundStyle(.tertiary) }
            }
            Text(value.reais).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(change.map { "\($0.signedPercent) \(range.rawValue)" } ?? "—")
                .font(.caption.monospacedDigit()).foregroundStyle((change ?? 0).gainColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func allocation(_ o: Overview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Allocation").font(.headline)
            HStack(spacing: 20) {
                Chart(o.slices) { s in
                    SectorMark(angle: .value("Value", s.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(s.color)
                }
                .frame(width: 160, height: 160)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(o.slices) { s in
                        HStack(spacing: 8) {
                            Circle().fill(s.color).frame(width: 9, height: 9)
                            Text(s.label)
                            Spacer()
                            Text(s.value.reais).monospacedDigit()
                            Text(o.total > 0 ? (s.value / o.total).percent : "—").monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                .frame(minWidth: 160)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func largest(_ o: Overview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Largest positions").font(.headline)
            ForEach(o.positions.prefix(10)) { p in
                HStack(spacing: 8) {
                    Circle().fill(p.assetClass.color).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(p.name).lineLimit(1)
                        Text(p.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(p.value.reais).monospacedDigit()
                    Text(o.total > 0 ? (p.value / o.total).percent : "").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .font(.callout)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
