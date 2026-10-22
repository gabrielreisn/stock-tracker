import Charts
import SwiftUI

/// Compares Brazilian funds' share-price returns against each other and CDI, from CVM's daily reports.
struct FundsWindow: View {
    @Environment(FundStore.self) private var funds
    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var hoverDate: Date?
    @State private var detail: ComparedFund?
    @State private var dragStart: Date?
    @State private var dragEnd: Date?
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var funds = funds
        VStack(alignment: .leading, spacing: 14) {
            search
                .zIndex(1)
            HStack(alignment: .center) {
                Text(funds.selected.isEmpty ? "Pick up to \(FundStore.maxSelected) funds to compare" : "\(funds.selected.count) of \(FundStore.maxSelected) funds")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if funds.isLoading {
                    ProgressView(value: Double(funds.progress.done), total: Double(max(funds.progress.total, 1)))
                        .frame(width: 120)
                    Text("Loading CVM reports \(funds.progress.done)/\(funds.progress.total)")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Picker("Range", selection: $funds.range) {
                    ForEach(FundRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            legend
            chart
                .frame(minHeight: 260)
            if !funds.stats.isEmpty { statsTable }
            footer
        }
        .padding(20)
        .frame(minWidth: 780, minHeight: 640)
        .task { funds.start() }
        .sheet(item: $detail) { FundDetailView(compared: $0).environment(funds) }
        .onChange(of: funds.range) { hoverDate = nil; dragStart = nil; dragEnd = nil }
    }

    // MARK: - Search

    private var search: some View {
        let results = funds.search(query)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .disabled(funds.indexState != .ready)
                    .onSubmit { if let first = results.first { pick(first) } }
                    .onExitCommand { query = "" }
                if funds.indexState == .loading { ProgressView().controlSize(.small) }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            if case .failed(let message) = funds.indexState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).padding(.top, 6)
            }
        }
        .overlay(alignment: .topLeading) {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty, funds.indexState == .ready {
                resultsList(results)
                    .offset(y: 46)
            }
        }
    }

    private var searchPrompt: String {
        switch funds.indexState {
        case .ready: "Search funds by name, CNPJ, manager or category"
        case .loading: "Downloading the fund list from CVM…"
        default: "Fund list unavailable"
        }
    }

    private func resultsList(_ results: [FundInfo]) -> some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                Text("No funds match “\(query)”").foregroundStyle(.secondary).padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { fund in
                            ResultRow(fund: fund, isSelected: funds.selected.contains { $0.id == fund.id }) { pick(fund) }
                                .disabled(funds.selected.count >= FundStore.maxSelected)
                            Divider()
                        }
                    }
                }
                // An overlay is only offered its anchor's height, so the list sets its own.
                .frame(height: min(CGFloat(results.count) * ResultRow.height, 460))
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
        .shadow(radius: 12, y: 4)
    }

    private func pick(_ fund: FundInfo) {
        funds.add(fund)
        query = ""
        searchFocused = true
    }

    // MARK: - Legend and chart

    /// The two points picked by dragging across the chart, oldest first.
    private var selection: (from: FundPoint, to: FundPoint)? {
        guard let a = nearest(dragStart), let b = nearest(dragEnd), a.date != b.date else { return nil }
        return a.date < b.date ? (a, b) : (b, a)
    }

    private func nearest(_ date: Date?) -> FundPoint? {
        date.flatMap { date in funds.points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) } }
    }

    /// Compounded change between the dragged points for one line.
    private func change(_ value: (FundPoint) -> Double?) -> Double? {
        guard let s = selection, let a = value(s.from), let b = value(s.to) else { return nil }
        return (1 + b) / (1 + a) - 1
    }

    /// Fund chips doubling as the value readout (they follow the crosshair, or show the dragged range's change).
    private var legend: some View {
        let shown = hoveredPoint ?? funds.points.last
        let dragging = selection != nil
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(funds.selected) { f in
                chip(color: color(f.slot), title: f.fund.name, value: dragging ? change { $0.returns[f.id] } : shown?.returns[f.id], dashed: false,
                     onOpen: { detail = f }, onRemove: { funds.remove(f) })
                .help("\(f.fund.name)\n\(f.fund.formattedCNPJ)\nClick for the fact sheet")
            }
            if !funds.selected.isEmpty {
                chip(color: cdiColor, title: "CDI", value: dragging ? change { $0.cdi } : shown?.cdi, dashed: true, onOpen: nil, onRemove: nil)
            }
        }
    }

    private func chip(color: Color, title: String, value: Double?, dashed: Bool, onOpen: (() -> Void)?, onRemove: (() -> Void)?) -> some View {
        HStack(spacing: 7) {
            Button { onOpen?() } label: {
                HStack(spacing: 7) {
                    Capsule().fill(color).frame(width: 14, height: 4)
                        .overlay { if dashed { Capsule().stroke(.background, style: StrokeStyle(lineWidth: 2, dash: [2, 2])) } }
                    Text(title).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(value?.signedPercent ?? "—").monospacedDigit().fontWeight(.medium)
                        .foregroundStyle((value ?? 0).gainColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Remove")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    }

    private var hoveredPoint: FundPoint? { selection == nil ? nearest(hoverDate) : nil }

    private var chart: some View {
        let points = funds.points
        let hovered = hoveredPoint
        return Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(points) { p in
                if let v = p.cdi {
                    LineMark(x: .value("Date", p.date), y: .value("Return", v), series: .value("Series", "CDI"))
                        .foregroundStyle(cdiColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                }
            }
            ForEach(funds.selected) { f in
                ForEach(points) { p in
                    if let v = p.returns[f.id] {
                        LineMark(x: .value("Date", p.date), y: .value("Return", v), series: .value("Series", f.id))
                            .foregroundStyle(color(f.slot))
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if let selection {
                RectangleMark(xStart: .value("From", selection.from.date), xEnd: .value("To", selection.to.date))
                    .foregroundStyle(Color.accentColor.opacity(0.1))
                ForEach([selection.from, selection.to]) { p in
                    RuleMark(x: .value("Date", p.date))
                        .foregroundStyle(Color.accentColor)
                }
                RuleMark(x: .value("Date", selection.from.date))
                    .opacity(0)
                    .annotation(position: .top, alignment: .leading) {
                        Text("\(selection.from.date.formatted(date: .abbreviated, time: .omitted)) – \(selection.to.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption.weight(.medium))
                    }
            }
            if let hovered {
                RuleMark(x: .value("Date", hovered.date))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .annotation(position: .top, alignment: .center) {
                        Text(hovered.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                ForEach(funds.selected) { f in
                    if let v = hovered.returns[f.id] {
                        PointMark(x: .value("Date", hovered.date), y: .value("Return", v))
                            .foregroundStyle(color(f.slot)).symbolSize(45)
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
        .chartYScale(domain: funds.yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(v.formatted(.percent.precision(.fractionLength(0...1)))) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.1))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: funds.range == .halfYear || funds.range == .ytd ? .dateTime.day().month(.abbreviated) : .dateTime.month(.abbreviated).year(.twoDigits))
                    }
                }
            }
        }
        .overlay {
            if points.count < 2 {
                VStack(spacing: 8) {
                    Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(funds.selected.isEmpty ? "Search for a fund above to start comparing" : funds.isLoading ? "Loading share prices…" : "No share prices in this range")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Stats

    private var statsTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 7) {
            GridRow {
                Text("Fund").gridColumnAlignment(.leading)
                Text("Return")
                Text("% of CDI")
                Text("Volatility")
                Text("Max drawdown")
                Text("Net assets")
            }
            .font(.caption).foregroundStyle(.secondary)
            Divider()
            ForEach(funds.selected) { f in
                if let s = funds.stats[f.id] {
                    GridRow {
                        Button { detail = f } label: {
                            HStack(spacing: 7) {
                                Circle().fill(color(f.slot)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.fund.name).lineLimit(1).truncationMode(.tail)
                                    Text(subtitle(f.fund, stats: s)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open the fact sheet")
                        Text(s.totalReturn.signedPercent).foregroundStyle(s.totalReturn.gainColor).fontWeight(.medium)
                        Text(s.percentOfCDI.map { ($0).formatted(.percent.precision(.fractionLength(0))) } ?? "—")
                        Text(s.volatility.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—")
                        Text(s.maxDrawdown < -0.00005 ? s.maxDrawdown.formatted(.percent.precision(.fractionLength(1))) : "—")
                            .foregroundStyle(s.maxDrawdown < -0.00005 ? .red : .secondary)
                        Text(f.fund.netAssets.map(\.compactReais) ?? "—").foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                }
            }
        }
        .font(.callout)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func subtitle(_ fund: FundInfo, stats: FundStats) -> String {
        var parts = [fund.formattedCNPJ]
        if let category = fund.category { parts.append(category) }
        if stats.firstDay >= funds.range.startDay {
            parts.append("since \(DayKey.date(stats.firstDay).formatted(date: .abbreviated, time: .omitted))")
        }
        return parts.joined(separator: " · ")
    }

    private var footer: some View {
        HStack {
            if let error = funds.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            Spacer()
            Text("Share prices net of fees from CVM's daily reports (1–2 days behind). Volatility is annualized from daily returns.")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    // MARK: - Colors

    /// Same categorical palette as the portfolio chart; CDI stays a neutral gray so it never looks like a fund.
    private func color(_ slot: Int) -> Color {
        let dark = scheme == .dark
        let palette: [UInt32] = dark
            ? [0x3987E5, 0xD95926, 0x199E70, 0xC98500, 0xD55181, 0x9A6FE8]
            : [0x2A78D6, 0xEB6834, 0x1BAF7A, 0xEDA100, 0xE87BA4, 0x7E4FD6]
        return Color(hex: palette[slot % palette.count])
    }

    private var cdiColor: Color { .secondary }
}

private struct ResultRow: View {
    static let height: CGFloat = 51
    let fund: FundInfo
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fund.name).lineLimit(1).truncationMode(.tail)
                    Text([fund.formattedCNPJ, fund.manager, fund.category].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else if let assets = fund.netAssets {
                    Text(assets.compactReais).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.height - 1)
            .contentShape(Rectangle())
            .background(hovering ? Color.accentColor.opacity(0.15) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
