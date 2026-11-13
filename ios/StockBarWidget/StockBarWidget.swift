import SwiftUI
import WidgetKit

private let suite = "group.app.cymba.native.shared"

struct PortfolioEntry: TimelineEntry {
    let date: Date
    let value: Double
    let change: Double?
    let updated: Date?
    let hidden: Bool
    let holdings: [String]
}

struct PortfolioProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortfolioEntry { PortfolioEntry(date: .now, value: 0, change: nil, updated: nil, hidden: true, holdings: []) }
    func getSnapshot(in context: Context, completion: @escaping (PortfolioEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PortfolioEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(.now.addingTimeInterval(21600))))
    }
    private func entry() -> PortfolioEntry {
        let defaults = UserDefaults(suiteName: suite)
        return PortfolioEntry(date: .now, value: defaults?.double(forKey: "total") ?? 0,
            change: defaults?.object(forKey: "change") as? Double, updated: defaults?.object(forKey: "updated") as? Date,
            hidden: defaults?.object(forKey: "hidden") as? Bool ?? true, holdings: defaults?.stringArray(forKey: "holdings") ?? [])
    }
}

struct PortfolioWidgetView: View {
    let entry: PortfolioEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cymba Native", systemImage: "chart.line.uptrend.xyaxis").font(.caption.bold()).foregroundStyle(.primary)
            Text(entry.hidden ? "R$ •••••" : entry.value.formatted(.currency(code: "BRL").locale(Locale(identifier: "pt_BR"))))
                .font(.title2.bold()).minimumScaleFactor(0.6).lineLimit(1).privacySensitive()
            if let change = entry.change { Text(change.formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always()))).font(.caption).foregroundStyle(change >= 0 ? .green : .red) }
            if family == .systemMedium && !entry.hidden { Text(entry.holdings.joined(separator: " · ")).font(.caption).lineLimit(2).privacySensitive() }
            Spacer(minLength: 0)
            if let updated = entry.updated { Text(updated, style: .relative).font(.caption2).foregroundStyle(.secondary) }
            else { Text("Open Cymba to refresh").font(.caption2).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "cymba-native://overview"))
    }
}

@main
struct StockBarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StockBarPortfolio", provider: PortfolioProvider()) { PortfolioWidgetView(entry: $0) }
            .configurationDisplayName("Portfolio")
            .description("Portfolio value, daily return and your largest stock holdings.")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
