import Charts
import SwiftUI

/// Read-only menu-bar quick look. Portfolio management lives in the main app.
struct ContentView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Privacy.key) private var hideValues = false
    @State private var overview: Overview?
    @State private var widgetWindow = WidgetWindowReference()

    private struct Revision: Hashable {
        let updated: Date?
        let trades: [Trade]
        let bonds: [Bond]
        let funds: [FundHolding]
        let fundPrices: Int
    }
    private var revision: Revision {
        Revision(updated: store.lastUpdated, trades: store.trades, bonds: store.bonds,
                 funds: funds.holdings, fundPrices: funds.holdingSeriesVersion)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let overview {
                    if overview.positions.isEmpty {
                        emptyState
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Portfolio").font(.caption).foregroundStyle(.secondary)
                            Text(overview.total.reais).font(.title2.weight(.semibold).monospacedDigit())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 14)
                        PerformanceSection(curves: overview.curves, ranges: [.quarter, .ytd, .year, .all], rangeKey: "widgetPortfolioRange")
                    }
                } else {
                    ProgressView("Loading portfolio…").padding(24)
                }
            }
            .id(hideValues)
            if !store.errors.isEmpty {
                Divider()
                Label("Some asset data is missing. Check Open Finance.", systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .help(store.errors.joined(separator: "\n"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
            }
            Divider()
            footer
        }
        .frame(width: 400)
        .background(WidgetWindowReader(reference: widgetWindow).frame(width: 0, height: 0))
        .task { funds.loadHoldings() }
        .task(id: revision) { overview = Overview(store: store, funds: funds) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.secondary)
            Text("No investments yet").font(.headline)
            Text("Open Cymba to add your investments and see your portfolio here.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(24)
    }

    private var footer: some View {
        HStack(spacing: 18) {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh(); funds.loadHoldings() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: store.isLoading)
            }
            .help("Refresh").disabled(store.isLoading || funds.holdingsLoading)
            HideValuesButton()
            Button {
                widgetWindow.window?.close()
                openWindow(id: "main")
                NSApp.activate()
            } label: {
                Label("Open app", systemImage: "macwindow")
            }.help("Open app")
        }
        .labelStyle(.iconOnly)
        .font(.callout).imageScale(.large).buttonStyle(.borderless)
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

/// Capture this widget's window so opening the app never closes the main window by mistake.
private final class WidgetWindowReference {
    weak var window: NSWindow?
}

private struct WidgetWindowReader: NSViewRepresentable {
    let reference: WidgetWindowReference

    final class WindowView: NSView {
        weak var reference: WidgetWindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.reference = reference
        return view
    }

    func updateNSView(_ view: WindowView, context: Context) {
        reference.window = view.window
    }
}

// MARK: - Performance chart

enum Series: Hashable {
    case portfolio
    case benchmark(BenchmarkID)

    var label: String {
        switch self {
        case .portfolio: String(localized: "Portfolio")
        case .benchmark(let id): id.label
        }
    }

    /// Fixed color per entity (palette slots 1–7). That many lines can't all be told apart by color alone, so the chart
    /// caps benchmarks at three and draws the rate-based ones dashed.
    func color(_ scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        return switch self {
        case .portfolio: Color(hex: dark ? 0x3987E5 : 0x2A78D6)
        case .benchmark(.cdi): Color(hex: dark ? 0xD95926 : 0xEB6834)
        case .benchmark(.ipca): Color(hex: dark ? 0x199E70 : 0x1BAF7A)
        case .benchmark(.sp500): Color(hex: dark ? 0xC98500 : 0xEDA100)
        case .benchmark(.ipcaPlus6): Color(hex: dark ? 0xD55181 : 0xE87BA4)
        case .benchmark(.ifix): Color(hex: 0x008300)
        case .benchmark(.ibov): Color(hex: dark ? 0x9A6FE8 : 0x7E4FD6)
        }
    }

    var isDashed: Bool {
        if case .benchmark(let id) = self { id.isRate } else { false }
    }

    func stroke(width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round, dash: isDashed ? [5, 3] : [])
    }

    func value(_ p: PerformancePoint) -> Double? {
        switch self {
        case .portfolio: p.portfolio
        case .benchmark(let id): p.benchmarks[id]
        }
    }
}

/// Two points picked by dragging across a chart; values in between are compounded returns.
struct ChartSelection {
    var from: PerformancePoint
    var to: PerformancePoint

    /// Change between the two points for a series of returns-since-start.
    func change(_ series: Series) -> Double? {
        guard let a = series.value(from), let b = series.value(to) else { return nil }
        return (1 + b) / (1 + a) - 1
    }
}

struct PerformanceSection: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.colorScheme) private var scheme
    @AppStorage private var range: ChartRange
    @State private var hoverDate: Date?
    @State private var dragStart: Date?
    @State private var dragEnd: Date?
    private let chartHeight: CGFloat
    /// Curves to show instead of the stocks' (the consolidated overview passes its own).
    private let curves: [ChartRange: [PerformancePoint]]?
    private let ranges: [ChartRange]

    init(chartHeight: CGFloat = 180, curves: [ChartRange: [PerformancePoint]]? = nil, ranges: [ChartRange] = ChartRange.allCases, rangeKey: String = "chartRange") {
        self.chartHeight = chartHeight
        self.curves = curves
        self.ranges = ranges
        _range = AppStorage(wrappedValue: ranges.contains(.ytd) ? .ytd : ranges[0], rangeKey)
    }

    var body: some View {
        let points = (curves ?? store.curves)[range] ?? []
        let selection = selection(points)
        let hovered = selection == nil ? nearest(hoverDate, in: points) : nil
        let shown = hovered ?? points.last
        // Enabled benchmarks keep their slot even while their data loads, so the layout never jumps.
        let series = [Series.portfolio] + store.enabledBenchmarks.map(Series.benchmark)
        let headline = selection.map { $0.change(.portfolio) } ?? shown?.portfolio

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline?.signedPercent ?? "…")
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .lineLimit(1).fixedSize()
                        .foregroundStyle((headline ?? 0).gainColor)
                    Text(selection.map(selectionCaption) ?? caption(hovered: hovered, points: points))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ranges) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }

            legend(series: series) { s in selection.map { $0.change(s) } ?? shown.flatMap { s.value($0) } }

            chart(points: points, series: series, hovered: hovered, selection: selection)
                .frame(height: chartHeight)
        }
        .padding(14)
        .onChange(of: range) { hoverDate = nil; dragStart = nil; dragEnd = nil }
    }

    private func nearest(_ date: Date?, in points: [PerformancePoint]) -> PerformancePoint? {
        date.flatMap { date in points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }

    private func selection(_ points: [PerformancePoint]) -> ChartSelection? {
        guard let a = nearest(dragStart, in: points), let b = nearest(dragEnd, in: points), a.date != b.date else { return nil }
        return a.date < b.date ? ChartSelection(from: a, to: b) : ChartSelection(from: b, to: a)
    }

    private func selectionCaption(_ s: ChartSelection) -> String {
        range == .day
            ? "\(s.from.date.formatted(date: .omitted, time: .shortened)) – \(s.to.date.formatted(date: .omitted, time: .shortened))"
            : "\(s.from.date.formatted(date: .abbreviated, time: .omitted)) – \(s.to.date.formatted(date: .abbreviated, time: .omitted))"
    }

    /// Legend doubling as the value readout (follows the crosshair, or shows the dragged range's change).
    /// Fixed 4-column grid, so values changing never reflow it.
    private func legend(series: [Series], value: @escaping (Series) -> Double?) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: 1 + BenchmarkID.maxEnabled), alignment: .leading, spacing: 6) {
            ForEach(series, id: \.self) { s in
                let value = value(s)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        LegendSwatch(series: s)
                        Text(s.label).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(value?.signedPercent ?? "—").monospacedDigit().lineLimit(1)
                        .padding(.leading, 17)
                }
            }
        }
        .font(.caption)
    }

    private func caption(hovered: PerformancePoint?, points: [PerformancePoint]) -> String {
        if let hovered {
            return range == .day
                ? hovered.date.formatted(date: .omitted, time: .shortened)
                : hovered.date.formatted(date: .abbreviated, time: .omitted)
        }
        guard let first = points.first else { return store.isLoading ? String(localized: "Loading prices…") : String(localized: "No data") }
        switch range {
        case .day:
            return Calendar.current.isDateInToday(first.date)
                ? String(localized: "today") : String(localized: "last session, \(first.date.formatted(.dateTime.weekday(.wide).day().month()))")
        case .week: return String(localized: "last 7 days")
        case .quarter: return String(localized: "last 3 months")
        case .ytd: return String(localized: "year to date")
        case .year: return String(localized: "last 12 months")
        case .threeYears: return String(localized: "last 3 years")
        case .fiveYears: return String(localized: "last 5 years")
        case .all: return String(localized: "since \(first.date.formatted(.dateTime.month(.abbreviated).year()))")
        }
    }

    private func chart(points: [PerformancePoint], series: [Series], hovered: PerformancePoint?, selection: ChartSelection?) -> some View {
        let domain = yDomain(points: points, series: series)
        let span = domain.upperBound - domain.lowerBound
        let digits = span < 0.03 ? 2 : span < 0.15 ? 1 : 0
        return Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            // Benchmarks first so the portfolio line sits on top.
            ForEach(series.reversed(), id: \.self) { s in
                ForEach(points) { p in
                    if let v = s.value(p) {
                        LineMark(x: .value("Date", p.date), y: .value("Return", v), series: .value("Series", s.label))
                            .foregroundStyle(s.color(scheme))
                            .lineStyle(s.stroke(width: s == .portfolio ? 2.5 : 2))
                    }
                }
                if let last = points.last, let v = s.value(last), hovered == nil, selection == nil {
                    PointMark(x: .value("Date", last.date), y: .value("Return", v))
                        .foregroundStyle(s.color(scheme))
                        .symbolSize(30)
                }
            }
            if let selection {
                let tint = (selection.change(.portfolio) ?? 0).gainColor
                RectangleMark(xStart: .value("From", selection.from.date), xEnd: .value("To", selection.to.date))
                    .foregroundStyle(tint.opacity(0.12))
                ForEach([selection.from, selection.to]) { p in
                    RuleMark(x: .value("Date", p.date))
                        .foregroundStyle(tint)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Date", p.date), y: .value("Return", p.portfolio))
                        .foregroundStyle(tint)
                        .symbolSize(60)
                }
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                ForEach(series, id: \.self) { s in
                    if let v = s.value(hovered) {
                        PointMark(x: .value("Date", hovered.date), y: .value("Return", v))
                            .foregroundStyle(s.color(scheme))
                            .symbolSize(45)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            hoverDate = proxy.value(atX: location.x - geo[plot].origin.x)
                        case .ended:
                            hoverDate = nil
                        }
                    }
                    // Drag across the chart to measure the change between two days, like Stocks.
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                guard let plot = proxy.plotFrame else { return }
                                let x = geo[plot].origin.x
                                if dragStart == nil { dragStart = proxy.value(atX: drag.startLocation.x - x) }
                                dragEnd = proxy.value(atX: drag.location.x - x)
                            }
                            .onEnded { _ in dragStart = nil; dragEnd = nil }
                    )
            }
        }
        .chartYScale(domain: domain)
        .chartXScale(domain: (points.first?.date ?? .now)...(points.last?.date ?? .now))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v.formatted(.percent.precision(.fractionLength(digits)))).font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.1))
                AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 6)) {
                    if let date = value.as(Date.self) {
                        Text(date, format: xFormat).font(.caption2).fixedSize()
                    }
                }
            }
        }
        .overlay {
            if points.count < 2 {
                Text(store.isLoading ? "Loading prices…" : "No prices for this range yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: range)
    }

    /// Fits the scale to the visible lines (plus 0%) so small moves stay readable.
    private func yDomain(points: [PerformancePoint], series: [Series]) -> ClosedRange<Double> {
        var lo = 0.0, hi = 0.0
        for p in points {
            for s in series {
                guard let v = s.value(p) else { continue }
                lo = min(lo, v)
                hi = max(hi, v)
            }
        }
        let pad = max((hi - lo) * 0.08, 0.0005)
        return (lo - pad)...(hi + pad)
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .day: .dateTime.hour().minute()
        case .week: .dateTime.weekday(.abbreviated)
        case .quarter: .dateTime.day().month(.abbreviated)
        case .ytd, .year: .dateTime.month(.abbreviated)
        case .threeYears, .fiveYears: .dateTime.month(.abbreviated).year(.twoDigits)
        case .all: .dateTime.year()
        }
    }
}

/// Legend key: a short line in the series color, dashed like the series.
struct LegendSwatch: View {
    @Environment(\.colorScheme) private var scheme
    let series: Series

    var body: some View {
        Canvas { context, size in
            var path = Path()
            path.move(to: CGPoint(x: 1, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
            context.stroke(path, with: .color(series.color(scheme)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: series.isDashed ? [4, 2.5] : []))
        }
        .frame(width: 12, height: 6)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
