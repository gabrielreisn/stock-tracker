import Charts
import SwiftUI

/// A year of spending, month over month: totals, one focusable chart with a trendline, and each category's trend.
struct InsightsPage: View {
    @Environment(ExpenseStore.self) private var expenses
    @State private var year = DayKey.from(.now) / 10_000
    /// What the main chart shows: every category summed, or one of them (nil is "No category").
    @State private var focus: Focus = .all
    @State private var hovered: Date?

    enum Focus: Hashable { case all, category(UUID?) }

    private static let brazil = Locale(identifier: "pt_BR")
    private var currentMonth: Int { DayKey.from(.now) / 100 }

    var body: some View {
        let data = YearData(expenses: expenses, year: year, currentMonth: currentMonth)
        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.spacing) {
                header
                tiles(data)
                mainChart(data)
                trends(data)
                grid(data)
                Text("Trends are a straight-line fit over the finished months, so the month in progress doesn't pull them down. Spending leaves out income, card bill payments, investments and transfers between your own accounts.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(PageLayout.padding)
        }
        .task(id: year) { await expenses.loadYear(year) }
    }

    // MARK: - Header and tiles

    private var header: some View {
        HStack(spacing: 12) {
            Text("Insights").font(.title2.weight(.semibold))
            Spacer()
            if let p = expenses.yearProgress {
                ProgressView(value: Double(p.done), total: Double(max(p.total, 1)))
                    .frame(width: 120)
                Text("Loading months…").font(.caption).foregroundStyle(.secondary)
            }
            Button { year -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(year <= currentMonth / 100 - 2)
                .help("Previous year")
            Text(String(year)).font(.title3.weight(.semibold).monospacedDigit()).frame(minWidth: 50)
            Button { year += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(year >= currentMonth / 100)
                .help("Next year")
        }
        .frame(height: 28)
    }

    private func tiles(_ d: YearData) -> some View {
        TileRow {
            SummaryTile(title: "Spent in the year", value: d.totalSpent.reais,
                        detail: d.finishedCount > 0 ? "over \(d.months.count) months" : nil)
            SummaryTile(title: "Average per month", value: d.averageSpent.reais,
                        detail: expenses.settings.totalLimit.map { "limit \($0.reais)" })
            SummaryTile(title: "Income", value: d.totalIncome.reais)
            SummaryTile(title: "Balance", value: (d.totalIncome - d.totalSpent).reais,
                        tint: d.totalIncome >= d.totalSpent ? .green : .red)
            if let top = d.highestMonth {
                SummaryTile(title: "Highest month", value: top.amount.reais,
                            detail: "\(DayKey.date(top.month * 100 + 1).formatted(.dateTime.month(.wide)).localizedCapitalized)")
            } else {
                SummaryTile(title: "Highest month", value: "—")
            }
        }
    }

    // MARK: - Main chart

    private func focusName(_ f: Focus) -> String {
        switch f {
        case .all: String(localized: "All categories")
        case .category(let id): expenses.category(id)?.name ?? String(localized: "No category")
        }
    }

    private func mainChart(_ d: YearData) -> some View {
        let series = d.series(focus)
        let limit: Double? = switch focus {
        case .all: expenses.settings.totalLimit
        case .category(let id): expenses.category(id)?.limit
        }
        let trend = d.trend(series)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Spending by month").font(.headline)
                Spacer()
                Picker("Focus", selection: $focus) {
                    Text("All categories").tag(Focus.all)
                    Divider()
                    ForEach(d.rows, id: \.id) { r in
                        Label(r.name, systemImage: r.symbol).tag(Focus.category(r.id))
                    }
                }
                .fixedSize()
            }
            Chart {
                ForEach(series) { p in
                    BarMark(x: .value("Month", p.date, unit: .month), y: .value("Spent", p.amount), width: .ratio(0.6))
                        .foregroundStyle(limit.map { p.amount > $0 } ?? false ? Color.red : Color.accentColor)
                        .opacity(p.finished ? 1 : 0.4)
                        .cornerRadius(3)
                }
                if let trend {
                    ForEach(trend) { p in
                        LineMark(x: .value("Month", p.date, unit: .month), y: .value("Trend", p.amount))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                }
                if let limit {
                    RuleMark(y: .value("Limit", limit))
                        .foregroundStyle(.red.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Limit").font(.caption2).foregroundStyle(.red)
                        }
                }
                if let hovered, let p = series.first(where: { Calendar.current.isDate($0.date, equalTo: hovered, toGranularity: .month) }) {
                    RuleMark(x: .value("Month", p.date, unit: .month))
                        .foregroundStyle(.secondary.opacity(0.15))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.date.formatted(.dateTime.month(.wide).year()).localizedCapitalized).font(.caption.weight(.semibold))
                                Text(p.amount.reais).font(.caption.monospacedDigit())
                                if !p.finished { Text("in progress").font(.caption2).foregroundStyle(.secondary) }
                            }
                            .padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                        }
                }
            }
            .chartXSelection(value: $hovered)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks { v in
                    AxisGridLine()
                    if !Privacy.isOn, let amount = v.as(Double.self) { AxisValueLabel(amount == 0 ? "R$ 0" : amount.compactReais) }
                }
            }
            .frame(height: 260)
            HStack(spacing: 16) {
                legend(color: .accentColor, "Spent")
                if trend != nil { legend(color: .orange, "Trend", dashed: true) }
                if limit != nil { legend(color: .red, "Limit", dashed: true) }
                Spacer()
                if let slope = d.slope(series) { trendLabel(slope, average: d.average(series)).font(.callout) }
            }
            .font(.caption)
        }
        .padding(16)
        .card()
    }

    private func legend(color: Color, _ title: LocalizedStringKey, dashed: Bool = false) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Path { p in p.move(to: CGPoint(x: 0, y: 1)); p.addLine(to: CGPoint(x: 14, y: 1)) }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 14, height: 2)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            Text(title).foregroundStyle(.secondary)
        }
    }

    /// Rising spending reads as bad news: red up, green down, grey when it's within 2% of the average a month.
    private func trendLabel(_ slope: Double, average: Double) -> some View {
        let steady = abs(slope) < max(average * 0.02, 1)
        let symbol = steady ? "arrow.right" : slope > 0 ? "arrow.up.right" : "arrow.down.right"
        let color: Color = steady ? .secondary : slope > 0 ? .red : .green
        return Label {
            Text(steady ? "steady" : "\((slope > 0 ? "+" : "−") + abs(slope).reais) a month")
                .monospacedDigit().lineLimit(1)
        } icon: { Image(systemName: symbol) }
        .foregroundStyle(color)
    }

    // MARK: - Category trends

    private func trends(_ d: YearData) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Categories").font(.headline).padding(.bottom, 10)
            HStack(spacing: 12) {
                Text("Category").frame(maxWidth: .infinity, alignment: .leading)
                Text("Months").frame(width: 150, alignment: .leading)
                Text("Average").frame(width: 110, alignment: .trailing)
                Text("Last month").frame(width: 110, alignment: .trailing)
                Text("Trend").frame(width: 180, alignment: .trailing)
                Text("Year").frame(width: 110, alignment: .trailing)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.bottom, 6)
            Divider()
            if d.rows.isEmpty {
                Text(expenses.yearProgress == nil ? "No spending this year." : "Loading…")
                    .foregroundStyle(.secondary).padding(.vertical, 20).frame(maxWidth: .infinity)
            }
            ForEach(d.rows, id: \.id) { r in
                trendRow(r, d)
                Divider().opacity(0.5)
            }
        }
        .padding(16)
        .card()
    }

    private func trendRow(_ r: YearData.Row, _ d: YearData) -> some View {
        let series = d.series(.category(r.id))
        let selected = focus == .category(r.id)
        let last = d.lastFinished.flatMap { m in series.first { $0.month == m } }?.amount ?? 0
        return Button { focus = selected ? .all : .category(r.id) } label: {
            HStack(spacing: 12) {
                Label(r.name, systemImage: r.symbol).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TrendSparkline(points: series, trend: d.trend(series), limit: expenses.category(r.id)?.limit)
                    .frame(width: 150, height: 26)
                Text(d.average(series).reais).monospacedDigit().frame(width: 110, alignment: .trailing)
                Text(last.reais).monospacedDigit().frame(width: 110, alignment: .trailing)
                    .foregroundStyle(expenses.category(r.id)?.limit.map { last > $0 } ?? false ? .red : .primary)
                Group {
                    if let slope = d.slope(series) { trendLabel(slope, average: d.average(series)) } else { Text("—").foregroundStyle(.tertiary) }
                }
                .frame(width: 180, alignment: .trailing)
                Text(r.total.reais).monospacedDigit().fontWeight(.medium).frame(width: 110, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 8).frame(height: 38)
            .background(selected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(selected ? "Show all categories in the chart" : "Show this category in the chart")
    }

    // MARK: - Month by month grid

    private func whole(_ v: Double) -> String {
        guard v != 0 else { return "–" }
        return Privacy.isOn ? "•••" : v.formatted(.number.precision(.fractionLength(0)).locale(Self.brazil))
    }

    private func grid(_ d: YearData) -> some View {
        // Always January to December, sharing the card's width, so every year's table is the same size.
        let nameWidth: CGFloat = 170
        let cell = { (v: Text) in v.lineLimit(1).minimumScaleFactor(0.8).padding(.leading, 8).frame(minWidth: 56, maxWidth: .infinity, alignment: .trailing) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Month by month").font(.headline)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("Category").frame(width: nameWidth, alignment: .leading)
                    ForEach(d.yearMonths, id: \.self) { m in
                        cell(Text(DayKey.date(m * 100 + 1).formatted(.dateTime.month(.abbreviated)).localizedCapitalized))
                    }
                    Text("Total").frame(width: 90, alignment: .trailing)
                }
                .font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
                Divider()
                ForEach(d.rows, id: \.id) { r in
                    let limit = expenses.category(r.id)?.limit
                    HStack(spacing: 0) {
                        Label(r.name, systemImage: r.symbol).lineLimit(1).frame(width: nameWidth, alignment: .leading)
                        ForEach(d.yearMonths, id: \.self) { m in
                            let v = d.amount(r.id, m)
                            cell(Text(whole(v)))
                                .foregroundStyle(limit.map { v > $0 } ?? false ? .red : v == 0 ? .secondary : .primary)
                        }
                        Text(whole(r.total)).fontWeight(.medium).frame(width: 90, alignment: .trailing)
                    }
                    .frame(height: 26)
                }
                Divider()
                HStack(spacing: 0) {
                    Text("Total").frame(width: nameWidth, alignment: .leading)
                    ForEach(d.yearMonths, id: \.self) { m in
                        let v = d.monthTotal(m)
                        cell(Text(whole(v)))
                            .foregroundStyle(expenses.settings.totalLimit.map { v > $0 } ?? false ? .red : v == 0 ? .secondary : .primary)
                    }
                    Text(whole(d.totalSpent)).frame(width: 90, alignment: .trailing)
                }
                .fontWeight(.semibold).frame(height: 28)
            }
            .font(.callout.monospacedDigit())
        }
        .padding(16)
        .card()
    }
}

/// A category's months as tiny bars with its trendline, for the categories table.
private struct TrendSparkline: View {
    let points: [YearData.Point]
    let trend: [YearData.Point]?
    let limit: Double?

    var body: some View {
        Chart {
            ForEach(points) { p in
                BarMark(x: .value("Month", p.date, unit: .month), y: .value("Spent", p.amount), width: .ratio(0.7))
                    .foregroundStyle(limit.map { p.amount > $0 } ?? false ? Color.red : Color.accentColor)
                    .opacity(p.finished ? 0.8 : 0.35)
            }
            if let trend {
                ForEach(trend) { p in
                    LineMark(x: .value("Month", p.date, unit: .month), y: .value("Trend", p.amount))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

/// One year's spending sliced by month and category, built from what the store has loaded.
struct YearData {
    struct Point: Identifiable {
        let month: Int
        let amount: Double
        let finished: Bool
        var id: Int { month }
        var date: Date { DayKey.date(month * 100 + 1) }
    }

    struct Row {
        let id: UUID?
        let name: String
        let symbol: String
        let total: Double
    }

    /// yyyymm, from the year's first month with spending up to the current month.
    let months: [Int]
    let currentMonth: Int
    private let spent: [Int: [UUID?: Double]]
    let totalIncome: Double
    /// Categories with spending this year, largest first.
    let rows: [Row]

    @MainActor
    init(expenses: ExpenseStore, year: Int, currentMonth: Int) {
        self.currentMonth = currentMonth
        yearMonths = (1...12).map { year * 100 + $0 }
        let months: [Int] = (1...12).map { year * 100 + $0 }.filter { $0 <= currentMonth }
        var spent: [Int: [UUID?: Double]] = [:]
        var income = 0.0
        for m in months {
            spent[m] = expenses.spending(month: m)
            for e in expenses.byMonth[m] ?? [] where e.kind == .income { income += e.amount }
        }
        self.spent = spent
        totalIncome = income
        // Months before the bank history starts would only be empty bars.
        let first = months.firstIndex { (spent[$0]?.values.reduce(0, +) ?? 0) > 0 } ?? months.count
        self.months = Array(months[first...])
        var totals: [UUID?: Double] = [:]
        for byCategory in spent.values { for (id, v) in byCategory { totals[id, default: 0] += v } }
        var rows: [Row] = []
        for (id, total) in totals where total > 0 {
            let c = expenses.category(id)
            rows.append(Row(id: id, name: c?.name ?? String(localized: "No category"), symbol: c?.symbol ?? "questionmark.circle", total: total))
        }
        self.rows = rows.sorted { $0.total > $1.total }
    }

    /// All twelve months, for the month-by-month table; ones not reached or before the history are empty.
    let yearMonths: [Int]

    func amount(_ id: UUID?, _ month: Int) -> Double { spent[month]?[id] ?? 0 }
    func monthTotal(_ month: Int) -> Double { spent[month]?.values.reduce(0, +) ?? 0 }
    var totalSpent: Double { months.reduce(0) { $0 + monthTotal($1) } }

    var finishedMonths: [Int] { months.filter { $0 < currentMonth } }
    var finishedCount: Int { finishedMonths.count }
    var lastFinished: Int? { finishedMonths.last }

    /// Over finished months, so the one in progress doesn't drag it down.
    var averageSpent: Double {
        let base = finishedMonths.isEmpty ? months : finishedMonths
        return base.isEmpty ? 0 : base.reduce(0) { $0 + monthTotal($1) } / Double(base.count)
    }

    var highestMonth: (month: Int, amount: Double)? {
        months.map { ($0, monthTotal($0)) }.filter { $0.1 > 0 }.max { $0.1 < $1.1 }
    }

    func series(_ focus: InsightsPage.Focus) -> [Point] {
        months.map { m in
            let v = switch focus { case .all: monthTotal(m); case .category(let id): amount(id, m) }
            return Point(month: m, amount: v, finished: m < currentMonth)
        }
    }

    func average(_ series: [Point]) -> Double {
        let done = series.filter(\.finished)
        return done.isEmpty ? 0 : done.reduce(0) { $0 + $1.amount } / Double(done.count)
    }

    /// Least-squares fit over finished months, starting at the first month with spending; needs three of them.
    private func fit(_ series: [Point]) -> (start: Int, slope: Double, intercept: Double)? {
        let done = series.filter(\.finished)
        guard let start = done.firstIndex(where: { $0.amount > 0 }) else { return nil }
        let ys = done[start...].map(\.amount)
        guard ys.count >= 3 else { return nil }
        let n = Double(ys.count), xs = ys.indices.map(Double.init)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let slope = sxx > 0 ? sxy / sxx : 0
        return (start, slope, my - slope * mx)
    }

    /// Reais a month the spending rises (or falls) by.
    func slope(_ series: [Point]) -> Double? { fit(series)?.slope }

    /// The fitted line across the finished months it was fitted on.
    func trend(_ series: [Point]) -> [Point]? {
        guard let f = fit(series) else { return nil }
        let done = series.filter(\.finished)
        return done[f.start...].enumerated().map { i, p in
            Point(month: p.month, amount: max(0, f.intercept + f.slope * Double(i)), finished: true)
        }
    }
}
