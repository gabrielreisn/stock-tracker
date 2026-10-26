import Charts
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case overview, stocks, bonds, funds, fgc, fundComparison, openFinance, settings
    var id: String { rawValue }
}

/// The full app window: portfolio and sections in a sidebar, the selected section on the right.
struct MainWindow: View {
    @Environment(FundStore.self) private var funds
    @AppStorage("mainSection") private var section: MainSection = .overview
    @AppStorage(Privacy.key) private var hideValues = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .id(hideValues)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            detail
                .id(hideValues)
                // No window title: the pages carry their own headings.
                .toolbar(removing: .title)
        }
        .frame(minWidth: 1120, minHeight: 720)
        .task { funds.loadHoldings() }
        // A menu bar app has no Dock icon; give it one while this window is open so it can be found with ⌘-Tab.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .overview: OverviewPage()
        case .stocks: StocksPage()
        case .bonds: BondsPage()
        case .funds: FundHoldingsPage()
        case .fgc: FGCPage()
        case .fundComparison: FundsWindow()
        case .openFinance: OpenFinancePage()
        case .settings:
            ScrollView { SettingsWindow().padding(.vertical, 20) }
                .frame(maxWidth: .infinity)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            PortfolioCard()
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)
            List(selection: Binding(get: { section == .settings ? nil : section }, set: { if let s = $0 { section = s } })) {
                Section {
                    Label("Overview", systemImage: "chart.pie").tag(MainSection.overview)
                }
                Divider()
                Label("Stocks", systemImage: "chart.line.uptrend.xyaxis").tag(MainSection.stocks)
                Label("Bonds", systemImage: "banknote").tag(MainSection.bonds)
                Label("Funds", systemImage: "building.columns").tag(MainSection.funds)
                Label("FGC Watcher", systemImage: "shield.lefthalf.filled").tag(MainSection.fgc)
                Label("Fund Comparison", systemImage: "chart.xyaxis.line").tag(MainSection.fundComparison)
                Label("Open Finance", systemImage: "building.2").tag(MainSection.openFinance)
            }
            .listStyle(.sidebar)
            Button { hideValues.toggle() } label: {
                Label(hideValues ? "Show values" : "Hide values", systemImage: hideValues ? "eye.slash" : "eye")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(hideValues ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .help(hideValues ? "Show amounts and quantities (⇧⌘H)" : "Hide amounts and quantities, for screenshots (⇧⌘H)")
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            Divider()
            Button { section = .settings } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(section == .settings ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
}

/// The portfolio at a glance, at the top of the sidebar.
private struct PortfolioCard: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds

    var body: some View {
        let pricer = store.bondPricer
        let bonds = store.bonds.reduce(0) { $0 + pricer.value($1).gross }
        let fundsValue = funds.holdings.reduce(0) { $0 + (funds.value($1)?.gross ?? 0) }
        let total = store.totalValue + bonds + fundsValue
        VStack(alignment: .leading, spacing: 4) {
            Text("Portfolio").font(.headline)
            Text(total > 0 ? total.reais : "—")
                .font(.title3.weight(.semibold).monospacedDigit())
            if bonds > 0 || fundsValue > 0 {
                Group {
                    Text("Stocks \(store.totalValue.compactReais)")
                    if bonds > 0 { Text("Bonds \(bonds.compactReais)") }
                    if fundsValue > 0 { Text("Funds \(fundsValue.compactReais)") }
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let change = store.dayChange {
                Text("Stocks \(change.signedPercent) today")
                    .font(.caption.monospacedDigit()).foregroundStyle(change.gainColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
    }
}

// MARK: - Stocks

struct StocksPage: View {
    @Environment(PortfolioStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PerformanceSection(chartHeight: 300)
                    .padding(6)
                    .card()
                StockHoldingsSection()
                DividendsSection()
            }
            .padding(24)
        }
    }
}

private struct DividendsSection: View {
    @Environment(PortfolioStore.self) private var store
    private static let brazil = Locale(identifier: "pt_BR")

    private var today: Int { DayKey.from(.now) }
    private var year: Int { today / 10_000 }

    var body: some View {
        let payments = store.dividends
        let thisYear = payments.filter { $0.day / 10_000 == year }
        let received = thisYear.filter { isPaid($0) }.reduce(0) { $0 + $1.amount }
        let upcoming = payments.filter { !isPaid($0) }.reduce(0) { $0 + $1.amount }

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Dividends").font(.title2.weight(.semibold))
                Spacer()
                Text("Received in \(String(year)): ").foregroundStyle(.secondary) + Text(received.reais).fontWeight(.semibold)
                if upcoming > 0 {
                    Text("Upcoming: ").foregroundStyle(.secondary) + Text(upcoming.reais).fontWeight(.semibold)
                }
            }
            .font(.callout.monospacedDigit())

            list(payments)
                .card()

            monthlyChart(thisYear)
                .frame(height: 220)
                .padding(16)
                .card()

            Text("Amounts are per-share payments times the quantity you hold today, before tax (JCP has 15% withheld; US dividends 30%). B3 companies from B3's announcements; FIIs and US stocks from Yahoo, dated by their ex-date.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func isPaid(_ p: DividendPayment) -> Bool { p.isPaid(asOf: today) }

    private func list(_ payments: [DividendPayment]) -> some View {
        VStack(spacing: 0) {
            if payments.isEmpty {
                Text(store.isLoading ? "Loading dividends…" : "No dividends this year on the stocks you hold.")
                    .foregroundStyle(.secondary).padding(24)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(payments) { p in
                            row(p)
                            if p.id != payments.last?.id { Divider().padding(.horizontal, 16) }
                        }
                    }
                }
                .frame(height: min(CGFloat(payments.count) * 49, 300))
            }
        }
    }

    private func row(_ p: DividendPayment) -> some View {
        let paid = isPaid(p)
        return HStack(spacing: 16) {
            Text(p.ticker).font(.body.weight(.semibold)).frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if p.datedByExDate {
                    Text(date(p.recordDay))
                    Text("Ex-date").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(p.paymentDay.map(date) ?? "Payment date not set")
                        .foregroundStyle(p.paymentDay == nil ? .secondary : .primary)
                    Text("Holders on \(date(p.recordDay))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)
            KindTag(kind: p.kind)
                .frame(width: 80, alignment: .leading)
            Text("\(p.quantity.quantity) × \(p.perShare.formatted(.number.precision(.fractionLength(2...6)).locale(Self.brazil)))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            if !paid {
                Text("Upcoming").font(.caption.weight(.medium)).foregroundStyle(.orange)
            }
            Text(p.amount.reais).font(.body.monospacedDigit().weight(.medium))
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .opacity(paid ? 1 : 0.75)
    }

    /// One bar per month of the current year, stacked by kind; months still to come are faded.
    private func monthlyChart(_ payments: [DividendPayment]) -> some View {
        struct Slice: Identifiable { var month: Int; var kind: DividendKind; var upcoming: Bool; var amount: Double; var id: String { "\(month)\(kind)\(upcoming)" } }
        var slices: [String: Slice] = [:]
        for p in payments {
            let slice = Slice(month: p.day / 100 % 100, kind: p.kind, upcoming: !isPaid(p), amount: 0)
            slices[slice.id, default: slice].amount += p.amount
        }
        let totals = Dictionary(grouping: slices.values, by: \.month).mapValues { $0.reduce(0) { $0 + $1.amount } }
        func monthDate(_ m: Int) -> Date { DayKey.date(year * 10_000 + m * 100 + 15) }

        return Chart {
            ForEach(Array(slices.values).sorted { $0.id < $1.id }) { s in
                BarMark(x: .value("Month", monthDate(s.month), unit: .month), y: .value("Amount", s.amount))
                    .foregroundStyle(by: .value("Kind", s.kind.label))
                    .opacity(s.upcoming ? 0.45 : 1)
            }
            ForEach(totals.sorted { $0.key < $1.key }, id: \.key) { month, total in
                PointMark(x: .value("Month", monthDate(month), unit: .month), y: .value("Amount", total))
                    .opacity(0)
                    .annotation(position: .top) {
                        Text(total.compactReais).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
            }
        }
        // Keys come from the same (translated) labels as the bars: a value missing from the scale crashes Charts.
        .chartForegroundStyleScale([DividendKind.dividend.label: Color(hex: 0x2A78D6), DividendKind.jcp.label: Color(hex: 0xEB6834),
                                    DividendKind.income.label: Color(hex: 0x1BAF7A)])
        .chartXScale(domain: monthDate(1).addingTimeInterval(-15 * 86_400)...monthDate(12).addingTimeInterval(16 * 86_400))
        .chartXAxis {
            AxisMarks(values: (1...12).map(monthDate)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel { if let v = value.as(Double.self) { Text(v.compactReais) } }
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .overlay { if payments.isEmpty { Text("Nothing paid this year yet").foregroundStyle(.secondary) } }
    }

    private func date(_ day: Int) -> String {
        DayKey.date(day).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Self.brazil))
    }
}

private struct KindTag: View {
    let kind: DividendKind

    var body: some View {
        let color: Color = switch kind {
        case .dividend: Color(hex: 0x2A78D6)
        case .jcp: Color(hex: 0xEB6834)
        case .income: Color(hex: 0x1BAF7A)
        }
        Text(kind.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

extension View {
    /// The rounded panel the sketch draws around each block.
    func card() -> some View {
        background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }
}
