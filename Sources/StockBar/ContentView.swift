import Charts
import SwiftUI

enum Screen { case overview, alerts }

struct ContentView: View {
    @State private var screen: Screen = .overview

    var body: some View {
        Group {
            switch screen {
            case .overview: OverviewView(screen: $screen)
            case .alerts: AlertsView(screen: $screen)
            }
        }
        .frame(width: 400)
    }
}

/// Title bar with a back button for the secondary screens.
struct ScreenHeader: View {
    let title: String
    @Binding var screen: Screen

    var body: some View {
        HStack(spacing: 8) {
            Button { screen = .overview } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Back")
            Text(title).font(.title2.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }
}

// MARK: - Overview

struct OverviewView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @AppStorage("mainSection") private var mainSection: MainSection = .stocks
    @AppStorage("chartRange") private var range: ChartRange = .ytd
    @Binding var screen: Screen

    var body: some View {
        VStack(spacing: 0) {
            if store.trades.isEmpty {
                emptyState
            } else {
                PerformanceSection()
                Divider()
                holdingsList
            }
            Divider()
            footer
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(.secondary)
            Text("No trades yet").font(.headline)
            Text("Add the stocks you hold and see how they did against CDI and IPCA.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Add your stocks") { open(.stocks) }.buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private var holdingsList: some View {
        HoldingsList(range: range)
    }

    private func open(_ section: MainSection) {
        mainSection = section
        openWindow(id: "main")
        NSApp.activate()
    }

    private var footer: some View {
        HStack(spacing: 18) {
            if let error = store.errors.first {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).lineLimit(1).help(store.errors.joined(separator: "\n"))
            } else if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
            }
            Spacer()
            Button { Task { await store.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, isActive: store.isLoading)
            }
            .help("Refresh")
            .disabled(store.isLoading)
            Button { screen = .alerts } label: { Image(systemName: "bell") }.help("Price alerts")
            Button { open(.stocks) } label: { Image(systemName: "list.bullet") }.help("Holdings")
            Button { open(.settings) } label: { Image(systemName: "gearshape") }.help("Settings")
        }
        .font(.callout)
        .imageScale(.large)
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Performance chart

enum Series: Hashable {
    case portfolio
    case benchmark(BenchmarkID)

    var label: String {
        switch self {
        case .portfolio: "Portfolio"
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
                        .foregroundStyle((headline ?? 0).gainColor)
                    Text(selection.map(selectionCaption) ?? caption(hovered: hovered, points: points))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(ranges) { Text($0.rawValue).tag($0) }
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
        guard let first = points.first else { return store.isLoading ? "Loading prices…" : "No data" }
        switch range {
        case .day:
            return Calendar.current.isDateInToday(first.date)
                ? "today" : "last session, \(first.date.formatted(.dateTime.weekday(.wide).day().month()))"
        case .quarter: return "last 3 months"
        case .ytd: return "year to date"
        case .year: return "last 12 months"
        case .threeYears: return "last 3 years"
        case .fiveYears: return "last 5 years"
        case .all: return "since \(first.date.formatted(.dateTime.month(.abbreviated).year()))"
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
        case .quarter: .dateTime.day().month(.abbreviated)
        case .ytd, .year: .dateTime.month(.abbreviated)
        case .threeYears, .fiveYears: .dateTime.month(.abbreviated).year(.twoDigits)
        case .all: .dateTime.year()
        }
    }
}

enum HoldingSort: String, CaseIterable {
    case weight, rangeReturn, today
}

/// Per-stock performance for the selected range, sortable by column.
struct HoldingsList: View {
    @Environment(PortfolioStore.self) private var store
    @AppStorage("holdingsSort") private var sort: HoldingSort = .rangeReturn
    let range: ChartRange

    private static let rowHeight: CGFloat = 40

    private var rows: [Holding] {
        let returns = store.tickerReturns[range] ?? [:], today = store.tickerReturns[.day] ?? [:]
        let key: (Holding) -> Double = switch sort {
        case .weight: { $0.weight }
        case .rangeReturn: { returns[$0.ticker] ?? -.infinity }
        case .today: { today[$0.ticker] ?? -.infinity }
        }
        return store.holdings.sorted { key($0) > key($1) }
    }

    var body: some View {
        let rows = rows
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { h in
                        HoldingRow(
                            holding: h,
                            path: store.tickerCurves[range]?[h.ticker] ?? [],
                            rangeReturn: store.tickerReturns[range]?[h.ticker],
                            dayChange: store.tickerReturns[.day]?[h.ticker],
                            showsDayChange: range != .day
                        )
                        .frame(height: Self.rowHeight)
                        Divider().padding(.leading, 14)
                    }
                }
            }
            // A ScrollView has no natural height, so size it to the rows (scrolling past 7).
            .frame(height: min(CGFloat(rows.count) * (Self.rowHeight + 1), 290))
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(store.holdings.count) stocks").frame(maxWidth: .infinity, alignment: .leading)
            sortButton("Weight", .weight).frame(width: 46, alignment: .trailing)
            sortButton(range.rawValue, .rangeReturn).frame(width: 74, alignment: .trailing)
            if range != .day {
                sortButton("Today", .today).frame(width: 60, alignment: .trailing)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func sortButton(_ title: String, _ column: HoldingSort) -> some View {
        Button { sort = column } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == column { Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)) }
            }
            .fontWeight(sort == column ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }
}

struct HoldingRow: View {
    let holding: Holding
    let path: [Double]
    let rangeReturn: Double?
    let dayChange: Double?
    let showsDayChange: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(holding.ticker).font(.callout.weight(.semibold))
                    if holding.isUS {
                        Text("US").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.5), lineWidth: 0.5))
                            .help("US stock — returns in reais, including the dollar's move")
                    }
                }
                Text("\(holding.quantity.quantity) shares").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)
            Sparkline(values: path, color: (rangeReturn ?? 0).gainColor)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
            Text(holding.weight.percent)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Text(rangeReturn?.signedPercent ?? "—")
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle((rangeReturn ?? 0).gainColor)
                .frame(width: 74, alignment: .trailing)
            if showsDayChange {
                Text(dayChange?.signedPercent ?? "—")
                    .font(.caption.monospacedDigit()).foregroundStyle((dayChange ?? 0).gainColor)
                    .frame(width: 60, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .help(holding.name ?? holding.ticker)
    }
}

/// Tiny return path for one stock over the selected range, with a faint 0% baseline.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let lo = (values + [0]).min(), let hi = (values + [0]).max(), hi > lo else { return }
            func y(_ v: Double) -> CGFloat { size.height - 1 - CGFloat((v - lo) / (hi - lo)) * (size.height - 2) }
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: y(0)))
            baseline.addLine(to: CGPoint(x: size.width, y: y(0)))
            context.stroke(baseline, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
            var line = Path()
            for (i, v) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1), y: y(v))
                if i == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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
