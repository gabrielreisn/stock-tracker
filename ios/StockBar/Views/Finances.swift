import SwiftUI
import Charts

struct MonthControl: View {
    @Binding var month: Int
    var body: some View {
        HStack {
            Button { month = DayKey.addMonths(month * 100 + 1, -1) / 100 } label: { Label("Previous month", systemImage: "chevron.left").labelStyle(.iconOnly) }
            Spacer()
            Text(DayKey.date(month * 100 + 1), format: .dateTime.month(.wide).year()).font(.headline)
            Spacer()
            Button { month = DayKey.addMonths(month * 100 + 1, 1) / 100 } label: { Label("Next month", systemImage: "chevron.right").labelStyle(.iconOnly) }
                .disabled(month >= DayKey.from(.now) / 100)
        }.buttonStyle(.borderless).tint(CymbaTheme.text)
    }
}

struct ExpensesScreen: View {
    @Environment(ExpenseStore.self) private var expenses
    @State private var month = DayKey.from(.now) / 100
    @State private var query = ""
    @State private var filter = "Spending"
    @State private var sort = "Date"
    @State private var adding = false
    @State private var selected: Expense?
    @FocusState private var searchFocused: Bool
    private var spent: Double { expenses.spending(month: month).values.reduce(0,+) }
    private var income: Double { (expenses.byMonth[month] ?? []).filter { $0.kind == .income }.reduce(0) { $0 + $1.amount } }
    private var review: Int { (expenses.byMonth[month] ?? []).filter { $0.kind == .spending && $0.categoryID == nil }.count }
    private var rows: [Expense] {
        (expenses.byMonth[month] ?? []).filter { e in
            let matchesQuery = query.isEmpty || "\(e.store) \(e.detail)".localizedCaseInsensitiveContains(query)
            let matchesFilter = filter == "Spending" ? e.kind == .spending : filter == "To review" ? e.kind == .spending && e.categoryID == nil : filter == "Income" ? e.kind == .income : e.kind == .outside
            return matchesQuery && matchesFilter
        }.sorted { a,b in
            switch sort {
            case "Store": return a.store < b.store
            case "Amount": return a.amount > b.amount
            case "Category": return category(a) < category(b)
            default: return a.day > b.day
            }
        }
    }
    private func category(_ e: Expense) -> String { expenses.category(e.categoryID)?.name ?? String(localized: e.kind == .income ? "Income" : e.kind == .outside ? "Not spending" : "No category") }
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 12) {
                Text("Personal account").font(.system(size: 14)).foregroundStyle(CymbaTheme.link)
                CymbaCaption(text: "Your transactions and changes are saved on this device.")
                MonthControl(month: $month)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    summary("Spent", spent.reais); summary("Income", income.reais)
                    summary("Balance", (income-spent).reais); summary("To review", String(review))
                }
                if let limit = expenses.settings.totalLimit { Text("\(String(localized: "Monthly limit")): \(limit.reais)").font(.system(size: 14)).foregroundStyle(CymbaTheme.secondary) }
                CymbaChoices(values: ["Spending", "To review", "Income", "Not spending"], selected: $filter)
                TextField("Search store or item", text: $query).textFieldStyle(CymbaInputStyle()).focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                CymbaChoices(values: ["Date", "Store", "Amount", "Category"], selected: $sort)
                HStack {
                    Text("\(rows.count) \(String(localized: "items"))").font(.system(size: 14)).foregroundStyle(CymbaTheme.secondary)
                    Spacer()
                    Button("Add purchase") { adding = true }.buttonStyle(CymbaActionStyle(primary: true)).fixedSize(horizontal: true, vertical: false).accessibilityIdentifier("add-expense")
                }
                if expenses.isLoading { ProgressView("Loading transactions…") }
                if let error = expenses.error { Text(error).font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
            }.listRowInsets(EdgeInsets()).listRowBackground(CymbaTheme.background).listRowSeparator(.hidden)
            ForEach(rows) { e in
                Button { selected = e } label: {
                    CymbaCard(spacing: 6) {
                        HStack {
                            Text(e.store).font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(e.amount.reais).font(.system(size: 15, weight: .medium)).foregroundStyle(e.kind == .income ? CymbaTheme.success : CymbaTheme.text)
                        }
                        Text(DayKey.date(e.day), format: .dateTime.day().month(.abbreviated)).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary)
                        Text(e.detail).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary).lineLimit(2)
                        Text(category(e) + " ›").font(.system(size: 14)).foregroundStyle(CymbaTheme.link)
                    }
                }.buttonStyle(.plain).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(CymbaTheme.background)
            }
            if rows.isEmpty { CymbaCaption(text: "Nothing here this month").padding(.vertical, 24).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(CymbaTheme.background) }
        }
        .listStyle(.plain).listRowSpacing(12).contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollContentBackground(.hidden).background(CymbaTheme.background).scrollDismissesKeyboard(.immediately)
        .cymbaNavigationTitle("Expenses")
        .sheet(isPresented: $adding) { ManualExpenseScreen() }
        .sheet(item: $selected) { row in NavigationStack { ExpenseDetailScreen(expense: row) } }
        .task(id: month) { await expenses.loadMonth(month); await expenses.loadInstallmentHistory(before: month) }
        .refreshable { await expenses.sync(month: month) }
    }
    private func summary(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 14)).foregroundStyle(CymbaTheme.secondary); Text(value).font(.system(size: 22, weight: .semibold)).minimumScaleFactor(0.6).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ExpenseDetailScreen: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var always = false
    @State private var confirm = false
    private var row: Expense { expenses.expenses.first { $0.id == expense.id } ?? expense }
    var body: some View {
        Form {
            Section {
                Text(row.store).font(.headline)
                Text(row.detail).font(.caption)
                Text(row.amount.reais).font(.title)
                Text(DayKey.date(row.day), style: .date)
                Text(row.accountName ?? "").privacySensitive()
                if let foreign = row.foreign { Text("\(foreign.amount.quantity) \(foreign.currency)") }
            }
            Section("Category") {
                Toggle("Always use for this store", isOn: $always)
                Picker("Category", selection: Binding<UUID?>(get: { row.categoryID }, set: { expenses.setCategory($0, for: row, forStore: always) })) {
                    Text("To review").tag(UUID?.none)
                    ForEach(expenses.settings.categories) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("Not spending", isOn: Binding(get: { row.kind == .outside }, set: { expenses.setOutside($0, for: row) }))
            }
            Section("Bills") {
                Toggle("Track this store as a recurring bill", isOn: Binding(get: { expenses.billChoice(BillStore.key(for: row)).tracked == true }, set: { value in
                    let key = BillStore.key(for: row)
                    var choice = expenses.billChoice(key); choice.tracked = value
                    expenses.setBillChoice(choice, for: key)
                }))
            }
            Section { Button("Delete", role: .destructive) { confirm = true } }
        }.cymbaList().cymbaNavigationTitle("Transaction")
        .confirmationDialog("Delete this transaction?", isPresented: $confirm) { Button("Delete", role: .destructive) { expenses.delete(row); dismiss() } }
    }
}

struct ManualExpenseScreen: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Date.now
    @State private var category: UUID?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Store", text: $name)
                TextField("Amount", text: $amount).keyboardType(.decimalPad)
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                Picker("Category", selection: $category) {
                    Text("To review").tag(UUID?.none)
                    ForEach(expenses.settings.categories) { Text($0.name).tag(Optional($0.id)) }
                }
            }.cymbaList().cymbaNavigationTitle("Add expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = parseNumber(amount), value > 0 {
                            expenses.addManual(ManualExpense(day: DayKey.from(date), store: name.trimmingCharacters(in: .whitespaces), amount: value, categoryID: category)); dismiss()
                        }
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (parseNumber(amount) ?? 0) <= 0)
                }
            }
        }
    }
}

struct CategoriesScreen: View {
    @Environment(ExpenseStore.self) private var expenses
    @State private var edit: ExpenseCategory?
    @State private var total = ""
    @State private var large = ""
    private var spending: [UUID?: Double] { expenses.spending(month: DayKey.from(.now) / 100) }
    var body: some View {
        List {
            VStack(alignment: .leading, spacing: 16) {
                CymbaCaption(text: "Personal account · saved on this device.")
                Text(Date.now, format: .dateTime.month(.wide).year()).font(.system(size: 22, weight: .semibold))
            }.listRowBackground(CymbaTheme.background).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Spent this month").font(.system(size: 16, weight: .medium))
                    CategorySpending(spent: spending.values.reduce(0,+), limit: expenses.settings.totalLimit, alertAt: expenses.settings.alertAt)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Monthly total limit (R$)").font(.system(size: 16, weight: .medium))
                    TextField("No limit", text: $total).textFieldStyle(CymbaInputStyle(inset: true)).keyboardType(.decimalPad).accessibilityLabel("Total monthly limit")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Warn at").font(.system(size: 16, weight: .medium))
                    HStack {
                        Button("−") { expenses.setAlertAt(max(0.5, expenses.settings.alertAt - 0.05)) }.buttonStyle(CymbaActionStyle()).fixedSize(horizontal: true, vertical: false).disabled(expenses.settings.alertAt <= 0.5).accessibilityLabel("Decrease warning threshold")
                        Spacer()
                        Text("\(Int((expenses.settings.alertAt * 100).rounded()))% of the limit").font(.system(size: 16, weight: .medium))
                        Spacer()
                        Button("+") { expenses.setAlertAt(min(1, expenses.settings.alertAt + 0.05)) }.buttonStyle(CymbaActionStyle()).fixedSize(horizontal: true, vertical: false).disabled(expenses.settings.alertAt >= 1).accessibilityLabel("Increase warning threshold")
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Warn about purchases over (R$)").font(.system(size: 16, weight: .medium))
                    TextField("Off", text: $large).textFieldStyle(CymbaInputStyle(inset: true)).keyboardType(.decimalPad).accessibilityLabel("Large purchase alert")
                    if total != (expenses.settings.totalLimit?.editableQuantity ?? "") || large != (expenses.settings.largePurchase?.editableQuantity ?? "") {
                        Button("Save") { saveLimits() }.buttonStyle(CymbaActionStyle(primary: true))
                            .disabled((!total.isEmpty && (parseNumber(total) ?? 0) <= 0) || (!large.isEmpty && (parseNumber(large) ?? 0) <= 0))
                    }
                }
                Button("Suggest limits from history") { Task { await expenses.suggestLimits(); total = expenses.settings.totalLimit?.editableQuantity ?? "" } }.buttonStyle(CymbaActionStyle())
                if let note = expenses.suggestionNote { Text(note).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary) }
            } header: { CymbaHeading(title: "Whole month").textCase(nil) } footer: {
                CymbaCaption(text: "Limits are per month. Warnings appear here when spending reaches the chosen share or exceeds a limit.")
            }.listRowBackground(CymbaTheme.surface).listRowSeparatorTint(CymbaTheme.selected)
            Section {
                ForEach(expenses.settings.categories) { c in
                    Button { edit = c } label: {
                        HStack(spacing: 12) {
                            Image(systemName: c.symbol).font(.system(size: 22)).frame(width: 44, height: 44)
                                .background(CymbaTheme.selected, in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 6) {
                                Text(c.name).font(.system(size: 16, weight: .medium))
                                CategorySpending(spent: spending[c.id] ?? 0, limit: c.limit, alertAt: expenses.settings.alertAt)
                                if c.limit == nil { CymbaCaption(text: "No limit") }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.foregroundStyle(CymbaTheme.text).padding(.vertical, 8).frame(minHeight: 72)
                    }.buttonStyle(.plain).accessibilityLabel(Text(c.name)).accessibilityIdentifier("category-\(c.id.uuidString)")
                        .swipeActions { Button("Delete", role: .destructive) { expenses.deleteCategory(c) } }
                }.onMove { expenses.moveCategories(from: $0, to: $1) }
                Button("Add category") { edit = ExpenseCategory(name: "", symbol: "tag") }.buttonStyle(CymbaActionStyle())
            } header: { CymbaHeading(title: "Categories").textCase(nil) } footer: {
                CymbaCaption(text: "Drag the handle to reorder categories. Tap a category to edit it.")
            }.listRowBackground(CymbaTheme.surface).listRowSeparatorTint(CymbaTheme.selected)
        }
        .cymbaList().environment(\.editMode, .constant(.active))
        .cymbaNavigationTitle("Categories & limits")
        .sheet(item: $edit) { CategoryEditor(category: $0) }
        .onAppear { total = expenses.settings.totalLimit?.editableQuantity ?? ""; large = expenses.settings.largePurchase?.editableQuantity ?? "" }
    }
    private func saveLimits() {
        expenses.setTotalLimit(parseNumber(total).flatMap { $0 > 0 ? $0 : nil })
        expenses.setLargePurchase(parseNumber(large).flatMap { $0 > 0 ? $0 : nil })
        Task { _ = await AlertNotifier.shared.authorize() }
    }
}

struct CategorySpending: View {
    let spent: Double
    let limit: Double?
    let alertAt: Double
    private var color: Color { guard let limit, limit > 0 else { return CymbaTheme.secondary }; return spent > limit ? CymbaTheme.danger : spent >= limit * alertAt ? CymbaTheme.warning : CymbaTheme.secondary }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(limit.map { "\(spent.reais) \(String(localized: "of")) \($0.reais)" } ?? spent.reais).font(.system(size: 13)).foregroundStyle(color)
            if let limit, limit > 0 { ProgressView(value: min(1, spent / limit)).tint(color).background(CymbaTheme.selected) }
        }
    }
}

struct CategoryEditor: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(\.dismiss) private var dismiss
    @State var category: ExpenseCategory
    @State private var limit = ""
    @State private var confirmingDelete = false
    private let icons = ["cart", "house", "fork.knife", "car", "cross.case", "sparkles", "laptopcomputer", "arrow.triangle.2.circlepath", "book", "pawprint", "tshirt", "gamecontroller", "bolt", "arrow.left.arrow.right", "bag", "tag", "gift", "airplane", "fuelpump", "figure.run", "heart", "graduationcap", "wrench.and.screwdriver", "film", "music.note", "cup.and.saucer", "wineglass", "stroller", "building.columns", "creditcard", "banknote", "ellipsis.circle"]
    private var isNew: Bool { !expenses.settings.categories.contains { $0.id == category.id } }
    private var canSave: Bool { !category.name.trimmingCharacters(in: .whitespaces).isEmpty && (limit.isEmpty || (parseNumber(limit) ?? 0) > 0) }
    var body: some View {
        NavigationStack {
            CymbaPage {
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(CymbaActionStyle())
                    Spacer()
                    Button("Save") { category.limit = parseNumber(limit).flatMap { $0 > 0 ? $0 : nil }; expenses.saveCategory(category); dismiss() }.buttonStyle(CymbaActionStyle(primary: true)).disabled(!canSave)
                }
                CymbaHeading(title: isNew ? "Add category" : "Edit category", size: 22).accessibilityIdentifier("category-editor-title")
                Text("Name").font(.system(size: 16, weight: .medium))
                TextField("Name", text: $category.name).textFieldStyle(CymbaInputStyle())
                Text("Monthly limit (R$)").font(.system(size: 16, weight: .medium))
                TextField("No limit", text: $limit).textFieldStyle(CymbaInputStyle()).keyboardType(.decimalPad).accessibilityLabel("Monthly limit")
                Text("Icon").font(.system(size: 16, weight: .medium))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 10) {
                    ForEach(icons, id: \.self) { icon in
                        Button { category.symbol = icon } label: {
                            Image(systemName: icon).font(.system(size: 22)).frame(width: 48, height: 48)
                                .foregroundStyle(category.symbol == icon ? CymbaTheme.link : CymbaTheme.text)
                                .background(category.symbol == icon ? CymbaTheme.selected : CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                        }.accessibilityLabel(icon).accessibilityAddTraits(category.symbol == icon ? .isSelected : [])
                    }
                }
                if !isNew { Button("Delete category", role: .destructive) { confirmingDelete = true }.buttonStyle(CymbaActionStyle()) }
            }
            .navigationTitle("Category").toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Delete this category?", isPresented: $confirmingDelete) { Button("Delete", role: .destructive) { expenses.deleteCategory(category); dismiss() } }
            .onAppear { limit = category.limit?.editableQuantity ?? "" }
        }
    }
}

struct InsightsScreen: View {
    @Environment(ExpenseStore.self) private var expenses
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selected: UUID?
    private var months: [Int] { (1...12).map { year * 100 + $0 }.filter { $0 <= DayKey.from(.now) / 100 } }
    private func amount(_ month: Int, _ category: UUID? = nil) -> Double {
        let spending = expenses.spending(month: month)
        return category.map { spending[$0] ?? 0 } ?? spending.values.reduce(0,+)
    }
    private var total: Double { months.reduce(0) { $0 + amount($1) } }
    private var income: Double { expenses.expenses.filter { $0.kind == .income && $0.day / 10000 == year }.reduce(0) { $0 + $1.amount } }
    var body: some View {
        CymbaPage {
            HStack {
                Text("Personal account").font(.system(size: 13, weight: .semibold)).foregroundStyle(CymbaTheme.accent)
                Spacer()
                Button { year -= 1 } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous year")
                Text(String(year)).font(.system(size: 20, weight: .semibold))
                Button { year += 1 } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next year").disabled(year >= Calendar.current.component(.year, from: .now))
            }
            CymbaCaption(text: "Your connected accounts")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("Spent in the year", total.reais); tile("Average per month", (total / Double(max(months.count,1))).reais)
                tile("Income", income.reais); tile("Balance", (income-total).reais)
            }
            CymbaCard {
                CymbaHeading(title: "Spending by month", size: 19)
                Picker("Category", selection: $selected) {
                    Text("All categories").tag(UUID?.none)
                    ForEach(expenses.settings.categories) { Text($0.name).tag(Optional($0.id)) }
                }.tint(CymbaTheme.text).padding(8).frame(maxWidth: .infinity).background(CymbaTheme.selected, in: RoundedRectangle(cornerRadius: 10))
                Chart {
                    ForEach(months, id: \.self) { month in BarMark(x: .value("Month", DayKey.date(month * 100 + 1), unit: .month), y: .value("Spending", amount(month, selected))).foregroundStyle(CymbaTheme.accent) }
                    if let limit = selected.flatMap({ expenses.category($0)?.limit }) ?? expenses.settings.totalLimit { RuleMark(y: .value("Limit", limit)).foregroundStyle(CymbaTheme.warning).lineStyle(.init(dash: [5,3])) }
                }.frame(height: 220)
            }
            CymbaHeading(title: "Categories", size: 19)
            ForEach(expenses.settings.categories) { c in
                CymbaCard {
                    HStack {
                        Text(c.name).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Chart(months, id: \.self) { m in LineMark(x: .value("Month", m), y: .value("Spending", amount(m, c.id))).foregroundStyle(CymbaTheme.text) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 90, height: 30)
                    }
                    HStack {
                        CymbaMetric(label: "Average", value: (months.reduce(0) { $0 + amount($1, c.id) } / Double(max(months.count,1))).reais)
                        CymbaMetric(label: "Last month", value: months.dropLast().last.map { amount($0, c.id).reais } ?? "—")
                    }
                    MoneyRow(title: String(localized: "Year"), value: months.reduce(0) { $0 + amount($1,c.id) }.reais)
                }
            }
            CymbaCard {
                CymbaHeading(title: "Month by month", size: 19)
                ScrollView(.horizontal) {
                    Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow { Text("Category").frame(width: 120, alignment: .leading); ForEach(months, id: \.self) { m in Text(DayKey.date(m * 100 + 1), format: .dateTime.month(.abbreviated)).frame(width: 84) } }.font(.caption.bold())
                        ForEach(expenses.settings.categories) { c in
                            GridRow { Text(c.name).frame(width: 120, alignment: .leading); ForEach(months, id: \.self) { m in Text(amount(m, c.id).reais).frame(width: 84) } }.font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            if let error = expenses.error { Text(error).font(.caption).foregroundStyle(CymbaTheme.warning) }
        }.cymbaNavigationTitle("Insights").task(id: year) { for month in months { if Task.isCancelled { break }; await expenses.loadMonth(month) } }
    }
    private func tile(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(label).font(.system(size: 12)).foregroundStyle(CymbaTheme.secondary); Text(value).font(.system(size: 23, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BillsScreen: View {
    @Environment(BillStore.self) private var bills
    @Environment(ExpenseStore.self) private var expenses
    var body: some View {
        CymbaPage(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) { Text("Personal account").font(.system(size: 14, weight: .semibold)).foregroundStyle(CymbaTheme.link); CymbaCaption(text: "Your transactions and changes are saved on this device.") }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                summary("Due in the next 30 days", bills.upcoming().reduce(0) { $0 + ($1.amount ?? 0) }.reais)
                summary("Late", String(bills.recurring().filter { $0.status == .late }.count))
                summary("Paid this month", bills.recurring().reduce(0) { $0 + $1.paidThisMonth.reduce(0) { $0 + $1.amount } }.reais)
                summary("Recurring bills", String(bills.recurring().count))
            }
            if bills.isLoading { ProgressView("Loading bills…") }
            if let error = bills.error { Text(error).font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
            ForEach(bills.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(CymbaTheme.warning) }
            VStack(alignment: .leading, spacing: 8) {
                CymbaHeading(title: "Upcoming"); CymbaCaption(text: "Late bills first, then the next 30 days")
                CymbaCard {
                    ForEach(bills.upcoming()) { bill in
                        HStack(spacing: 12) {
                            VStack(spacing: 2) { Text(DayKey.date(bill.day), format: .dateTime.month(.abbreviated)).font(.system(size: 10, weight: .semibold)); Text(String(bill.day % 100)).font(.system(size: 22, weight: .semibold)) }.frame(width: 48, height: 52).background(CymbaTheme.selected, in: RoundedRectangle(cornerRadius: 8))
                            MoneyRow(title: bill.name, value: bill.amount?.reais ?? "—")
                        }
                    }
                    if bills.upcoming().isEmpty { CymbaCaption(text: "Nothing due in the next 30 days.") }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                CymbaHeading(title: "Recurring bills")
                CymbaCaption(text: "Boletos, automatic debits and financing paid in at least 2 of the last 3 months")
                CymbaCard {
                    ForEach(bills.recurring()) { bill in NavigationLink { BillEditor(bill: bill) } label: { MoneyRow(title: bill.name, detail: "\(DayKey.date(bill.nextDue).formatted(date: .abbreviated, time: .omitted)) · \(status(bill.status))", value: bill.usual.reais) }.buttonStyle(.plain) }
                    if bills.recurring().isEmpty { CymbaCaption(text: "No recurring bills found yet.") }
                }
            }
            CymbaHeading(title: "Credit card bills")
            CymbaCard {
                ForEach(bills.cards()) { card in MoneyRow(title: card.card, detail: DayKey.date(card.due).formatted(date: .abbreviated, time: .omitted), value: card.total.reais) }
                if bills.cards().isEmpty { CymbaCaption(text: "No closed card bills are available from your banks.") }
            }
            CymbaHeading(title: "Loans & financing")
            CymbaCard {
                ForEach(bills.loanSummaries()) { loan in MoneyRow(title: loan.name, value: loan.balance?.reais ?? "—") }
                if bills.loanSummaries().isEmpty { CymbaCaption(text: "No loan contracts are available from your banks.") }
            }
            if !bills.hidden.isEmpty {
                CymbaHeading(title: "Hidden bills")
                ForEach(bills.hidden, id: \.key) { item in Button(item.name) { var choice = expenses.billChoice(item.key); choice.tracked = true; expenses.setBillChoice(choice, for: item.key) }.buttonStyle(CymbaActionStyle()) }
            }
            CymbaCaption(text: "Due days are estimated from past payments. Tap a recurring bill to set its due day. Payments have a 3-day grace period before appearing late.")
        }.cymbaNavigationTitle("Bills").task { await bills.load() }.refreshable { await bills.refresh() }
    }
    private func summary(_ title: LocalizedStringKey, _ value: String) -> some View { CymbaCard { CymbaMetric(label: title, value: value) } }
    private func status(_ value: BillStatus) -> String { switch value { case .paid: String(localized: "Paid"); case .upcoming: String(localized: "Upcoming"); case .late: String(localized: "Late") } }
}

struct BillEditor: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(\.dismiss) private var dismiss
    let bill: RecurringBill
    @State private var due = 1
    @State private var paid = false
    @State private var tracked = true
    var body: some View {
        Form {
            Text(bill.name).font(.headline)
            Text(bill.usual.reais)
            Stepper("Due day: \(due)", value: $due, in: 1...31)
            Toggle("Paid this month", isOn: $paid)
            Toggle("Track this bill", isOn: $tracked)
            Button("Save") {
                var choice = expenses.billChoice(bill.key)
                choice.dueDay = due; choice.tracked = tracked
                var months = choice.paidByHand ?? []
                if paid { months.insert(DayKey.from(.now) / 100) } else { months.remove(DayKey.from(.now) / 100) }
                choice.paidByHand = months
                expenses.setBillChoice(choice, for: bill.key); dismiss()
            }
        }.cymbaList().cymbaNavigationTitle("Bill")
        .onAppear { due = bill.dueDay; paid = bill.paidByHand; tracked = expenses.billChoice(bill.key).tracked != false }
    }
}
