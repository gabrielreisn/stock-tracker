import SwiftUI
import Charts

struct PhoneTabs: View {
    @AppStorage(Privacy.key) private var privacy = false
    @Environment(AppModel.self) private var app
    @State private var tab = 0
    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { OverviewScreen() }.tabItem { Label("Overview", systemImage: "chart.pie") }.tag(0)
            NavigationStack { InvestmentsScreen() }.tabItem { Label("Investments", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
            NavigationStack { FinancesScreen() }.tabItem { Label("Finances", systemImage: "list.bullet.rectangle") }.tag(2)
            NavigationStack { SettingsScreen() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
        }
        .tint(CymbaTheme.text)
        .foregroundStyle(CymbaTheme.text)
        .id(privacy)
        .onChange(of: privacy) { WidgetSnapshot.update(portfolio: app.portfolio, funds: app.funds) }
        .onOpenURL { url in
            if url.scheme == "cymba-native" {
                tab = url.host == "settings" ? 3 : url.host == "investments" ? 1 : url.host == "finances" ? 2 : 0
            }
        }
    }
}

struct PrivacyButton: View {
    @AppStorage(Privacy.key) private var hidden = false
    var body: some View {
        Button { hidden.toggle() } label: { Label(hidden ? "Show values" : "Hide values", systemImage: hidden ? "eye.slash" : "eye") }
    }
}

struct MoneyRow: View {
    let title: String
    var detail: String = ""
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).foregroundStyle(CymbaTheme.text)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(CymbaTheme.secondary) }
            }
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium).monospacedDigit().foregroundStyle(CymbaTheme.text)
        }.font(.system(size: 14)).padding(.vertical, 4)
    }
}

extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255)/255, green: Double((hex >> 8) & 255)/255, blue: Double(hex & 255)/255) }
}
extension BenchmarkID {
    var color: Color {
        switch self {
        case .cdi: CymbaTheme.adaptive(0xeb6834, 0xd95926)
        case .ipca: CymbaTheme.adaptive(0x1baf7a, 0x199e70)
        case .sp500: CymbaTheme.adaptive(0xeda100, 0xc98500)
        case .ipcaPlus6: CymbaTheme.adaptive(0xe87ba4, 0xd55181)
        case .ifix: Color(hex: 0x008300)
        case .ibov: CymbaTheme.adaptive(0x7e4fd6, 0x9a6fe8)
        }
    }
}

struct ReturnsChart: View {
    let points: [PerformancePoint]
    let benchmarks: [BenchmarkID]
    @State private var selected: Date?
    @State private var start: Date?
    @State private var dragging = false
    private func nearest(_ date: Date) -> PerformancePoint? { points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    private var selection: PerformancePoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = selection ?? points.last {
                Text(p.date, style: .date).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
            }
            if let start, let end = selection, let base = nearest(start), base.portfolio > -1 {
                let change = (1 + end.portfolio) / (1 + base.portfolio) - 1
                Text("Selected period: \(change.signedPercent)").font(.caption.bold()).foregroundStyle(change.gainColor)
            }
            if points.isEmpty { CymbaCaption(text: "Return history unavailable") }
            else {
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Return", p.portfolio), series: .value("Series", "Portfolio"))
                            .foregroundStyle(CymbaTheme.text)
                        ForEach(benchmarks) { b in
                            if let v = p.benchmarks[b] {
                                LineMark(x: .value("Date", p.date), y: .value("Return", v), series: .value("Series", b.label))
                                    .foregroundStyle(b.color).lineStyle(StrokeStyle(lineWidth: 1, dash: b.isRate ? [4,3] : []))
                            }
                        }
                    }
                    if let p = selection { RuleMark(x: .value("Date", p.date)).foregroundStyle(CymbaTheme.secondary) }
                }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in AxisGridLine(); AxisValueLabel { if let number = value.as(Double.self) { Text(number.percent) } } } }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { gesture in
                                guard let frame = proxy.plotFrame else { return }
                                let x = gesture.location.x - geometry[frame].minX
                                let date: Date? = proxy.value(atX: x)
                                if !dragging { start = date; dragging = true }
                                selected = date
                            }.onEnded { _ in dragging = false })
                    }
                }
                .frame(height: 210)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        Text("━ " + String(localized: "Portfolio") + " · " + ((selection ?? points.last)?.portfolio.signedPercent ?? "—")).foregroundStyle(CymbaTheme.text)
                        ForEach(benchmarks) { b in
                            let current = selection ?? points.last
                            let value: Double? = current?.benchmarks[b]
                            let label = (b.isRate ? "┄ " : "━ ") + b.label + " · " + (value?.signedPercent ?? "—")
                            Text(label).foregroundStyle(b.color)
                        }
                    }.font(.system(size: 12))
                }
            }
        }
    }
}

struct RangePicker: View {
    @Binding var range: ChartRange
    var ranges = Overview.ranges
    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons
            ScrollView(.horizontal, showsIndicators: false) { buttons }
        }
    }
    private var buttons: some View {
        HStack(spacing: 4) {
            ForEach(ranges) { r in
                Button(r.label) { range = r }
                    .font(.system(size: 14)).foregroundStyle(CymbaTheme.text)
                    .frame(minWidth: 40, minHeight: 44).padding(.horizontal, 4)
                    .background(range == r ? CymbaTheme.selected : CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityAddTraits(range == r ? .isSelected : [])
            }
        }.buttonStyle(.plain)
    }
}

struct OverviewScreen: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @Environment(AppModel.self) private var app
    @AppStorage("overviewRange") private var savedRange = ChartRange.ytd.rawValue
    @State private var overview: Overview?
    private var range: ChartRange { ChartRange(rawValue: savedRange) ?? .ytd }
    var body: some View {
        CymbaPage {
            CymbaRootTitle(title: "Overview", identifier: "overview-title")
            CymbaCaption(text: "Personal account · Gross values in BRL")
            CymbaCard {
                CymbaCaption(text: "Total")
                Text((overview?.total ?? 0).reais).font(.system(size: 32, weight: .semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                if let last = overview?.curves[range]?.last, overview?.positions.isEmpty == false {
                    Text("\(last.portfolio.signedPercent) · \(range.label)").font(.system(size: 14)).foregroundStyle(last.portfolio >= 0 ? CymbaTheme.success : CymbaTheme.secondary)
                } else { Text("—").foregroundStyle(CymbaTheme.secondary) }
            }
            if let overview {
                VStack(spacing: 10) {
                    HStack(spacing: 10) { assetTile(.stocks, overview); assetTile(.bonds, overview) }
                    assetTile(.funds, overview)
                }
                CymbaCard {
                    CymbaHeading(title: "Performance", size: 18)
                    RangePicker(range: Binding(get: { range }, set: { savedRange = $0.rawValue }))
                    if store.isLoading { ProgressView().frame(maxWidth: .infinity) }
                    ReturnsChart(points: overview.positions.isEmpty ? [] : overview.curves[range] ?? [], benchmarks: store.enabledBenchmarks)
                    CymbaCaption(text: "Returns cover available histories only. Missing prices are excluded, not treated as zero.")
                }
                CymbaCard {
                    CymbaHeading(title: "Allocation", size: 18)
                    ZStack {
                        if overview.total > 0 {
                            Chart(overview.slices) { slice in
                                SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.66), angularInset: 2).foregroundStyle(slice.color)
                            }
                        } else { Circle().stroke(CymbaTheme.selected, lineWidth: 24).padding(12) }
                        VStack(spacing: 4) {
                            Text("Allocation").font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
                            Text(overview.total > 0 ? "100%" : "—").font(.system(size: 18, weight: .semibold))
                        }
                    }.frame(width: 160, height: 160).frame(maxWidth: .infinity).accessibilityLabel("Portfolio allocation")
                    ForEach(overview.slices) { slice in
                        HStack(spacing: 10) {
                            Text("●").foregroundStyle(slice.color)
                            Text(slice.label).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(slice.value.reais) · \((slice.value / max(overview.total, 1)).percent)")
                        }.font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
                    }
                }
                CymbaCard {
                    CymbaHeading(title: "Largest positions", size: 18)
                    ForEach(overview.positions.prefix(10)) { p in
                        HStack(spacing: 10) {
                            Text("●").foregroundStyle(p.assetClass.color)
                            VStack(alignment: .leading, spacing: 4) { Text(p.name).font(.system(size: 14)); Text(p.detail).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary) }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(p.value.reais).font(.system(size: 14))
                                Text((p.value / max(overview.total, 1)).percent).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
                            }
                        }
                    }
                    if overview.positions.isEmpty { CymbaCaption(text: "No valued positions") }
                }
            }
            if !store.errors.isEmpty { CymbaCard { ForEach(store.errors, id: \.self) { Text($0).font(.caption).foregroundStyle(CymbaTheme.warning) } } }
            Button("Refresh market data") { Task { await store.refresh(); recompute() } }.buttonStyle(CymbaActionStyle())
            CymbaCaption(text: "Today's holdings are treated as held throughout the range. Daily returns are weighted by the previous day's values. Bonds join on their issue date; statement-only funds count in value, not returns. Values are gross of tax.")
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await app.sync(force: true); await store.refresh(); recompute() }
        .task(id: store.lastUpdated) { recompute() }
        .task(id: funds.holdingSeriesVersion) { recompute() }
        .onChange(of: funds.holdings) { recompute() }
        .onChange(of: store.bonds) { recompute() }
    }
    private func assetTile(_ asset: AssetClass, _ overview: Overview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) { Text("●").foregroundStyle(asset.color); Text(asset.label) }.font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
            Text((overview.values[asset] ?? 0).reais).font(.system(size: 22, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            Text(overview.total > 0 ? ((overview.values[asset] ?? 0) / overview.total).percent : "Partial valuation").font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
            Text(overview.classReturns[range]?[asset].map { "\($0.signedPercent) · \(range.label)" } ?? "—").font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
    private func recompute() { overview = Overview(store: store, funds: funds) }
}

struct CymbaDestination<Destination: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var account = false
    var investment = false
    @ViewBuilder var destination: Destination
    var body: some View {
        NavigationLink { destination } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: investment ? 18 : 17, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 14)).foregroundStyle(CymbaTheme.secondary) }
                }
                Spacer(minLength: 0)
                if account { Text("Personal account").font(.system(size: 14)).foregroundStyle(CymbaTheme.secondary); Text("·").foregroundStyle(CymbaTheme.secondary) }
                Text("›").foregroundStyle(CymbaTheme.secondary)
            }.padding(investment ? 20 : 16).frame(minHeight: investment ? 64 : 60)
                .background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: investment ? 14 : 12))
        }.buttonStyle(.plain).accessibilityLabel(Text(title))
    }
}

struct InvestmentsScreen: View {
    var body: some View {
        CymbaPage(spacing: 12) {
            CymbaRootTitle(title: "Investments", identifier: "investments-title").padding(.bottom, 12)
            CymbaDestination(title: "Stocks", account: true, investment: true) { StocksScreen() }
            CymbaDestination(title: "Bonds", account: true, investment: true) { BondsScreen() }
            CymbaDestination(title: "Funds", account: true, investment: true) { FundsScreen() }
            CymbaDestination(title: "FGC Watcher", account: true, investment: true) { FGCScreen() }
        }.toolbar(.hidden, for: .navigationBar)
    }
}

struct FinancesScreen: View {
    var body: some View {
        CymbaPage(spacing: 12) {
            CymbaRootTitle(title: "Finances", identifier: "finances-title").padding(.bottom, 12)
            CymbaDestination(title: "Expenses") { ExpensesScreen() }
            CymbaDestination(title: "Bills", subtitle: "Due dates and recurring payments") { BillsScreen() }
            CymbaDestination(title: "Insights", subtitle: "Yearly spending and category trends") { InsightsScreen() }
            CymbaDestination(title: "Categories & limits") { CategoriesScreen() }
            CymbaDestination(title: "Open Finance") { OpenFinanceScreen() }
        }.toolbar(.hidden, for: .navigationBar)
    }
}
