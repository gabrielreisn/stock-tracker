import SwiftUI

/// Shared pieces for the main window's pages, so they line up with each other.
enum PageLayout {
    static let padding: CGFloat = 24
    static let spacing: CGFloat = 20
    static let rowHeight: CGFloat = 48
}

/// Page title with an optional trailing control; the same height whether or not there is one.
struct PageHeader<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            accessory
        }
        .frame(height: 28)
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// A summary figure. Every tile keeps a detail line (blank when there's none), so a row of them is even.
struct SummaryTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(tint ?? .primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail ?? " ").font(.caption.monospacedDigit()).foregroundStyle(tint ?? .secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A row of summary tiles sized to the tallest one.
struct TileRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A column title that sorts its table: click to sort by it, click again to flip the order.
struct SortHeader<Key: Equatable>: View {
    let title: String
    let key: Key
    @Binding var sort: Key
    @Binding var ascending: Bool
    /// The first click sorts ascending (names, dates) instead of descending (amounts).
    var ascendingFirst = false

    var body: some View {
        Button {
            if sort == key { ascending.toggle() } else { sort = key; ascending = ascendingFirst }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sort == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 7, weight: .bold))
                }
            }
            .fontWeight(sort == key ? .semibold : .regular)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }
}

extension Array {
    /// Sorted by a number, with missing values last whichever the direction.
    func sorted(by value: (Element) -> Double?, ascending: Bool) -> [Element] {
        sorted { a, b in
            switch (value(a), value(b)) {
            case let (x?, y?): ascending ? x < y : x > y
            case (_?, nil): true
            default: false
            }
        }
    }

    /// Sorted by text, the way Finder does (case- and accent-insensitive, numbers in order).
    func sorted(byText text: (Element) -> String, ascending: Bool) -> [Element] {
        sorted { a, b in
            let order = text(a).localizedStandardCompare(text(b))
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

/// What a page shows before anything is added: what it's for, and ways to fill it.
struct EmptyPageState: View {
    let symbol: String
    let title: String
    let message: String
    let addTitle: String
    let onAdd: () -> Void
    @AppStorage("mainSection") private var section: MainSection = .overview

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button(addTitle, action: onAdd).buttonStyle(.borderedProminent)
                Button("Import from Open Finance") { section = .openFinance }
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
