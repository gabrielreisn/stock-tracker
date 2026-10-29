import SwiftUI

/// A month of card, account and PIX transactions: spending by category, income, what still needs a category,
/// and what isn't spending at all (bill payments, own transfers, investments).
enum ExpenseSort: String {
    case date, store, detail, source, category, value
}

struct ExpensesPage: View {
    @Environment(ExpenseStore.self) private var expenses
    @State private var month = DayKey.from(.now) / 100
    @State private var tab: Tab = .spending
    @State private var search = ""
    @AppStorage("expenseSort") private var sort: ExpenseSort = .date
    @AppStorage("expenseSortAscending") private var ascending = false
    @State private var adding = false
    @State private var pendingDelete: Expense?

    enum Tab: String, CaseIterable, Identifiable {
        case spending, income, review, outside
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .spending: "Spending"
            case .income: "Income"
            case .review: "To review"
            case .outside: "Not spending"
            }
        }
    }

    private static let brazil = Locale(identifier: "pt_BR")

    var body: some View {
        let all = expenses.byMonth[month] ?? []
        let rows = sorted(filtered(all))
        let spent = all.filter { $0.kind == .spending }.reduce(0) { $0 + $1.amount }
        let income = all.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let toReview = all.filter { $0.kind == .spending && $0.categoryID == nil }.count

        // Sized to exactly the space the column gives it: a page with a scroll view inside is otherwise
        // measured as tall as all its rows, which pushes the window's content (sidebar included) out of view.
        GeometryReader { geo in
        VStack(alignment: .leading, spacing: 14) {
            header
            TileRow {
                SummaryTile(title: "Spent", value: spent.reais,
                            detail: expenses.settings.totalLimit.map { "\(Int((spent / max($0, 1) * 100).rounded()))% of \($0.reais)" },
                            tint: expenses.settings.totalLimit.map { spent > $0 ? .red : spent >= $0 * expenses.settings.alertAt ? .orange : nil } ?? nil)
                SummaryTile(title: "Income", value: income.reais)
                SummaryTile(title: "Balance", value: (income - spent).reais, tint: (income - spent).gainColor)
                SummaryTile(title: "To review", value: "\(toReview)", detail: toReview > 0 ? "without a category" : nil,
                            tint: toReview > 0 ? .orange : nil)
            }
            HStack(spacing: 12) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.label).tag(t) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                TextField("Search store or item", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 416)
                Spacer()
                Text("\(rows.count) items").font(.callout).foregroundStyle(.secondary)
                Button { adding = true } label: { Label("Add purchase", systemImage: "plus") }
            }
            table(rows)
                .frame(maxHeight: .infinity)
            Text("Tip: pick a category on a row, or right-click to use it for every purchase at that store, or to move it out of spending. “Not spending” holds card bill payments, transfers between your own accounts and investments.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(PageLayout.padding)
        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .confirmationDialog("Delete this transaction?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { e in
            Button("Delete", role: .destructive) { expenses.delete(e) }
        } message: { e in
            Text(e.isManual ? "\(e.store) · \(e.amount.reais)" : "\(e.store) · \(e.amount.reais). It stays hidden when the month syncs again.")
        }
        .sheet(isPresented: $adding) { ManualExpenseForm(day: defaultDay).environment(expenses) }
        // The month on screen first, then the ones before it for installments billed in this month.
        .task(id: month) {
            await expenses.loadMonth(month)
            await expenses.loadInstallmentHistory(before: month)
        }
    }

    private var defaultDay: Int {
        DayKey.from(.now) / 100 == month ? DayKey.from(.now) : month * 100 + 1
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { month = DayKey.addMonths(month * 100 + 1, -1) / 100 } label: { Image(systemName: "chevron.left") }
                .help("Previous month")
            Text(DayKey.date(month * 100 + 1).formatted(.dateTime.month(.wide).year()).localizedCapitalized)
                .font(.title2.weight(.semibold))
                .frame(minWidth: 200)
            Button { month = DayKey.addMonths(month * 100 + 1, 1) / 100 } label: { Image(systemName: "chevron.right") }
                .disabled(month >= DayKey.from(.now) / 100)
                .help("Next month")
            Spacer()
            if let error = expenses.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else if let last = expenses.lastSync {
                Text("synced \(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if expenses.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await expenses.sync(month: month) } } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                .disabled(expenses.isLoading)
        }
    }

    private func filtered(_ rows: [Expense]) -> [Expense] {
        let tabRows: [Expense] = switch tab {
        case .spending: rows.filter { $0.kind == .spending }
        case .income: rows.filter { $0.kind == .income }
        case .review: rows.filter { $0.kind == .spending && $0.categoryID == nil }
        case .outside: rows.filter { $0.kind == .outside }
        }
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return tabRows }
        return tabRows.filter { $0.store.localizedStandardContains(query) || $0.detail.localizedStandardContains(query) }
    }

    // MARK: - Table

    private enum Width { static let date: CGFloat = 70, source: CGFloat = 116, category: CGFloat = 214, value: CGFloat = 110, icon: CGFloat = 24 }

    private func sorted(_ rows: [Expense]) -> [Expense] {
        switch sort {
        case .date: rows.sorted(by: { Double($0.day) }, ascending: ascending)
        case .store: rows.sorted(byText: { $0.store }, ascending: ascending)
        case .detail: rows.sorted(byText: { $0.detail }, ascending: ascending)
        case .category: rows.sorted(byText: { expenses.category($0.categoryID)?.name ?? "" }, ascending: ascending)
        case .source: rows.sorted(byText: { $0.source.label }, ascending: ascending)
        case .value: rows.sorted(by: { $0.amount }, ascending: ascending)
        }
    }

    private func column(_ title: LocalizedStringKey, _ key: ExpenseSort, ascendingFirst: Bool = false) -> some View {
        SortHeader(title: title, key: key, sort: $sort, ascending: $ascending, ascendingFirst: ascendingFirst)
    }

    /// A List, not a lazy stack: it's an NSTableView that reuses its row views. A LazyVStack kept re-estimating
    /// the height of rows it hadn't built and sometimes stalled scrolling for seconds.
    private func table(_ rows: [Expense]) -> some View {
        // The headers are the list's pinned section header, so they sit in the same row layout as the cells
        // and stay over their columns whatever the table's insets or scroll bar do.
        List {
            Section {
                ForEach(rows) { e in
                    row(e)
                        .overlay(alignment: .bottom) { Divider().padding(.horizontal, 14) }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack(spacing: 10) {
                    column("Date", .date).frame(width: Width.date, alignment: .leading)
                    column("Store", .store, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                    column("Description", .detail, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                    column("Source", .source, ascendingFirst: true).frame(width: Width.source, alignment: .leading)
                    column("Category", .category, ascendingFirst: true).frame(width: Width.category, alignment: .leading)
                    column("Value", .value).frame(width: Width.value, alignment: .trailing)
                    Text("").frame(width: Width.icon)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if rows.isEmpty {
                Text(expenses.isLoading ? "Loading transactions…" : search.isEmpty ? "Nothing here this month" : "No transactions match “\(search)”")
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func foreignHelp(_ f: Expense.Foreign) -> String {
        switch f.conversion {
        case .bank: String(localized: "Paid in \(f.currency), converted by the bank")
        case .rate(let rate): String(localized: "Paid in \(f.currency), converted at \(rate.formatted(.number.precision(.significantDigits(4)).locale(Self.brazil))) reais, the day's rate on Yahoo Finance; the card bill may differ a little")
        case .missing: String(localized: "Paid in \(f.currency); the exchange rate couldn't be loaded yet")
        }
    }

    private func row(_ e: Expense) -> some View {
        HStack(spacing: 10) {
            Text(e.billedLater ? "–" : DayKey.date(e.day).formatted(.dateTime.day().month(.abbreviated)))
                .foregroundStyle(e.billedLater ? .secondary : .primary)
                .frame(width: Width.date, alignment: .leading)
                .help(e.billedLater ? "A later installment, counted from the start of the month" : "")
            HStack(spacing: 6) {
                Text(e.store).lineLimit(1)
                if let foreign = e.foreign {
                    Text(Privacy.isOn ? "\(foreign.currency) •••" : foreign.amount.formatted(.currency(code: foreign.currency).locale(Self.brazil)))
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .help(foreignHelp(foreign))
                }
                if let installment = e.installment {
                    Text(installment).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .help("Installment")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.detail).lineLimit(1).foregroundStyle(.secondary).help(e.detail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Label(e.source.label, systemImage: e.source.symbol)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .help(e.accountName ?? (e.isManual ? String(localized: "Added by hand") : ""))
                .frame(width: Width.source, alignment: .leading)
            HoverSwap { categoryCell(e) } still: { categoryLabel(e) }
                .frame(width: Width.category, alignment: .leading)
            Text(e.foreign?.conversion == .missing ? "—" : (e.foreign.map { if case .rate = $0.conversion { "≈ " } else { "" } } ?? "") + e.amount.reais)
                .foregroundStyle(e.kind == .income ? .green : e.amount >= (expenses.settings.largePurchase ?? .infinity) ? .orange : .primary)
                .frame(width: Width.value, alignment: .trailing)
            Button { pendingDelete = e } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete")
                .frame(width: Width.icon)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: 38)
        .contentShape(Rectangle())
        .contextMenu { contextMenu([e]) }
    }

    /// What the selector looks like at rest. Each live picker creates a native pop-up menu with every category,
    /// which made scrolling drop to ~9 fps; drawing this instead and swapping in the picker under the pointer
    /// keeps it at ~5 ms a frame.
    /// The selector at rest: the same view the live menu uses as its label, so nothing moves when it swaps in.
    @ViewBuilder
    private func categoryLabel(_ e: Expense) -> some View {
        if e.kind == .spending {
            CategoryChip(category: expenses.category(e.categoryID), width: Width.category)
        } else {
            Text(e.kind == .income ? "Income" : "Not spending").foregroundStyle(.secondary)
        }
    }

    /// The live selector: a menu whose label is the chip itself (a native pop-up button can't take a fixed
    /// width), with the categories as a checked list inside.
    @ViewBuilder
    private func categoryCell(_ e: Expense) -> some View {
        if e.kind == .spending {
            Menu {
                Picker("Category", selection: Binding(get: { e.categoryID }, set: { expenses.setCategory($0, for: e) })) {
                    Text("No category").tag(UUID?.none)
                    ForEach(expenses.settings.categories) { c in
                        Label(c.name, systemImage: c.symbol).tag(UUID?.some(c.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                CategoryChip(category: expenses.category(e.categoryID), width: Width.category)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        } else {
            categoryLabel(e)
        }
    }

    @ViewBuilder
    private func contextMenu(_ picked: [Expense]) -> some View {
        if let first = picked.first {
            if picked.count == 1, first.kind == .spending {
                Menu("Always use for “\(first.store)”") {
                    ForEach(expenses.settings.categories) { c in
                        Button { expenses.setCategory(c.id, for: first, forStore: true) } label: { Label(c.name, systemImage: c.symbol) }
                    }
                }
            }
            if picked.allSatisfy({ $0.kind == .outside }) {
                Button("Count as spending or income") { picked.forEach { expenses.setOutside(false, for: $0) } }
            } else {
                Button("Move to Not spending") { picked.forEach { expenses.setOutside(true, for: $0) } }
            }
            if picked.count == 1, !first.isCard {
                let key = BillStore.key(for: first)
                let choice = expenses.billChoice(key)
                Button(choice.tracked == true ? "Stop tracking as a bill" : "Track as a bill") {
                    var changed = choice
                    changed.tracked = choice.tracked == true ? nil : true
                    expenses.setBillChoice(changed, for: key)
                }
            }
            Divider()
            Button("Delete", role: .destructive) { pendingDelete = first }
        }
    }
}

/// A category as a fixed-width selector: icon in its own slot (so names line up down the column), name, and arrows.
private struct CategoryChip: View {
    let category: ExpenseCategory?
    let width: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: category?.symbol ?? "tag")
                .frame(width: 16)
                .opacity(category == nil ? 0 : 1)
            Text(category?.name ?? String(localized: "No category"))
                .lineLimit(1).truncationMode(.tail)
                .foregroundStyle(category == nil ? .secondary : .primary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
        }
        .font(.system(size: 13))
        .padding(.leading, 10).padding(.trailing, 10)
        .frame(width: width, height: 24)
        .background(scheme == .dark ? Color.white.opacity(0.09) : Color.white, in: RoundedRectangle(cornerRadius: 6))
        .shadow(color: .black.opacity(scheme == .dark ? 0 : 0.18), radius: 0.5, y: 0.5)
        .contentShape(Rectangle())
    }
}

/// Shows `still` until the pointer is over it, then the live control, so only one heavy control exists at a time.
private struct HoverSwap<Live: View, Still: View>: View {
    @ViewBuilder let live: Live
    @ViewBuilder let still: Still
    @State private var hovering = false

    var body: some View {
        Group { if hovering { live } else { still } }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// A purchase that didn't come through Open Finance.
struct ManualExpenseForm: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var store = ""
    @State private var amount = ""
    @State private var categoryID: UUID?

    init(day: Int) { _date = State(initialValue: DayKey.date(day)) }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Store", text: $store, prompt: Text("Padaria"))
                TextField("Value", text: $amount, prompt: Text("25,90"))
                Picker("Category", selection: $categoryID) {
                    Text("No category").tag(UUID?.none)
                    ForEach(expenses.settings.categories) { c in Label(c.name, systemImage: c.symbol).tag(UUID?.some(c.id)) }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let value = parseNumber(amount), value > 0 else { return }
                    expenses.addManual(ManualExpense(day: DayKey.from(date), store: store.trimmingCharacters(in: .whitespaces), amount: value, categoryID: categoryID))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(store.trimmingCharacters(in: .whitespaces).isEmpty || (parseNumber(amount) ?? 0) <= 0)
            }
            .padding(16)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
