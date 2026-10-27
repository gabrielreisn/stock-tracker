import SwiftUI

/// Spending categories and their optional monthly limits, plus the month-wide limit and alerts.
struct CategoriesPage: View {
    @Environment(ExpenseStore.self) private var expenses
    /// A new category opens with its name ready to type.
    @State private var editingName: UUID?

    private var month: Int { DayKey.from(.now) / 100 }

    var body: some View {
        let spent = expenses.spending(month: month)
        Form {
            Section {
                AmountField(title: "Monthly total limit", placeholder: "no limit", value: expenses.settings.totalLimit) { expenses.setTotalLimit($0) }
                LabeledContent("Warn at") {
                    HStack {
                        Slider(value: Binding(get: { expenses.settings.alertAt }, set: { expenses.setAlertAt($0) }), in: 0.5...1, step: 0.05)
                            .frame(width: 220)
                        Text("\(Int((expenses.settings.alertAt * 100).rounded()))% of the limit").monospacedDigit().frame(width: 110, alignment: .leading)
                    }
                }
                AmountField(title: "Warn about purchases over", placeholder: "off", value: expenses.settings.largePurchase) { expenses.setLargePurchase($0) }
                HStack {
                    Button("Suggest limits from history") { Task { await expenses.suggestLimits() } }
                        .disabled(expenses.isLoading)
                    if let note = expenses.suggestionNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Whole month")
            } footer: {
                Text("Limits are per month. You get a notification when a category passes the chosen share and another when it goes over its limit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(expenses.settings.categories) { c in
                    CategoryRow(category: c, spent: spent[c.id] ?? 0, startEditing: editingName == c.id)
                }
                .onMove { expenses.moveCategories(from: $0, to: $1) }
                if let uncategorized = spent[nil], uncategorized > 0 {
                    LabeledContent {
                        Text("this month: \(uncategorized.reais)").font(.caption).foregroundStyle(.orange)
                    } label: {
                        Label("No category", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                    }
                }
                Button {
                    let new = ExpenseCategory(name: String(localized: "New category"), symbol: "tag")
                    expenses.saveCategory(new)
                    editingName = new.id
                } label: { Label("Add category", systemImage: "plus") }
                .buttonStyle(.borderless)
            } header: {
                Text("Categories")
            } footer: {
                Text("Click an icon to change it and a name to rename it. Deleting a category sends its purchases back to “To review”.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .task {
            await expenses.loadMonth(month)
            await expenses.loadInstallmentHistory(before: month)
        }
    }
}

private struct CategoryRow: View {
    @Environment(ExpenseStore.self) private var expenses
    let category: ExpenseCategory
    let spent: Double
    var startEditing = false
    @State private var name = ""
    @State private var editing = false
    @State private var choosingIcon = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?

    static let symbols = ["cart", "house", "fork.knife", "car", "cross.case", "sparkles", "laptopcomputer", "arrow.triangle.2.circlepath",
                          "book", "pawprint", "tshirt", "gamecontroller", "bolt", "arrow.left.arrow.right", "bag", "tag", "gift",
                          "airplane", "fuelpump", "figure.run", "heart", "graduationcap", "wrench.and.screwdriver", "film", "music.note",
                          "cup.and.saucer", "wineglass", "stroller", "building.columns", "creditcard", "banknote", "ellipsis.circle"]

    var body: some View {
        HStack(spacing: 10) {
            // The icon grid lives in a popover, built only when opened.
            Button { choosingIcon = true } label: {
                Image(systemName: category.symbol).frame(width: 26, height: 26)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Change icon")
            .popover(isPresented: $choosingIcon, arrowEdge: .bottom) { iconGrid }

            Group {
                if editing {
                    // Plain field in the label's exact spot; the outline sits outside the text so nothing moves.
                    TextField("Name", text: $name)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit(commitName)
                        .onExitCommand { name = category.name; editing = false }
                        .onChange(of: nameFocused) { if !nameFocused { commitName() } }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.background, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 1.5))
                        .padding(.horizontal, -5).padding(.vertical, -2)
                        .frame(maxWidth: 280, alignment: .leading)
                        .background(GeometryReader { geo in
                            Color.clear
                                .onAppear { fieldFrame = geo.frame(in: .global) }
                                .onChange(of: geo.frame(in: .global)) { fieldFrame = $1 }
                        })
                        .onAppear(perform: watchClicksOutside)
                        .onDisappear(perform: stopWatching)
                } else {
                    Text(category.name)
                        .contentShape(Rectangle())
                        .onTapGesture { beginEditing() }
                        .help("Click to rename")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let limit = category.limit
            Text("this month: \(spent.reais)").font(.caption)
                .foregroundStyle(limit.map { spent > $0 ? Color.red : spent >= $0 * expenses.settings.alertAt ? .orange : .secondary } ?? .secondary)
            AmountField(title: "Limit", placeholder: "no limit", value: limit) { var c = category; c.limit = $0; expenses.saveCategory(c) }
                .frame(width: 190)
            Button { confirmDelete = true } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Delete category")
                .confirmationDialog("Delete “\(category.name)”?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) { expenses.deleteCategory(category) }
                } message: {
                    Text("Its purchases go back to “To review”.")
                }
        }
        .onAppear { if startEditing { beginEditing() } }
    }

    private var iconGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8), spacing: 6) {
            ForEach(Self.symbols, id: \.self) { s in
                Button {
                    var c = category; c.symbol = s; expenses.saveCategory(c)
                    choosingIcon = false
                } label: {
                    Image(systemName: s).frame(width: 28, height: 28)
                        .background(s == category.symbol ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    /// Clicking an empty spot doesn't take focus away on macOS, so any click outside the field ends the edit.
    private func watchClicksOutside() {
        stopWatching()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in
            if let window = event.window, let height = window.contentView?.bounds.height {
                let p = event.locationInWindow
                // SwiftUI's global frame is top-down; AppKit's window points are bottom-up.
                if !fieldFrame.insetBy(dx: -6, dy: -4).contains(CGPoint(x: p.x, y: height - p.y)) {
                    DispatchQueue.main.async { commitName() }
                }
            }
            return event
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func beginEditing() {
        name = category.name
        editing = true
        nameFocused = true
    }

    private func commitName() {
        guard editing else { return }
        editing = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != category.name else { return }
        var c = category
        c.name = trimmed
        expenses.saveCategory(c)
    }
}

/// An optional amount in reais, typed Brazilian style ("1.234,50"); empty means none.
private struct AmountField: View {
    let title: LocalizedStringKey
    let placeholder: LocalizedStringKey
    let value: Double?
    let onCommit: (Double?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            TextField(title, text: $text, prompt: Text(placeholder))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
        }
        .onAppear { text = Self.format(value) }
        .onChange(of: value) { if !focused { text = Self.format(value) } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parsed = trimmed.isEmpty ? nil : parseNumber(trimmed).flatMap { $0 > 0 ? $0 : nil }
        if parsed != value { onCommit(parsed) }
        text = Self.format(parsed)
    }

    private static func format(_ v: Double?) -> String {
        v.map { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR"))) } ?? ""
    }
}
