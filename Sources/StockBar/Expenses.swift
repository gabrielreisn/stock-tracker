import Foundation
import Observation
import UserNotifications

/// A spending category, with an optional monthly limit. `pluggyKeywords` match Pluggy's own category names
/// (in English, e.g. "Groceries", "Pharmacy") so transactions land in it without a rule.
struct ExpenseCategory: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol: String
    var limit: Double?
    var pluggyKeywords: [String] = []

    func isLike(_ other: ExpenseCategory) -> Bool {
        name.localizedCaseInsensitiveCompare(other.name) == .orderedSame
            || (!pluggyKeywords.isEmpty && pluggyKeywords == other.pluggyKeywords)
    }
}

/// A purchase typed by hand (cash, another card…), counted like an Open Finance one.
struct ManualExpense: Codable, Identifiable, Hashable {
    var id = UUID()
    var day: Int
    var store: String
    var amount: Double
    var categoryID: UUID?
}

/// How one transaction is treated, set by the user.
enum ExpenseOverride: Codable, Hashable {
    case category(UUID)
    /// Not spending: a bill payment, a transfer between own accounts, an investment.
    case outside
    /// Deleted by the user: hidden, and kept hidden when the month syncs again.
    case deleted
}

/// Everything the user decides, saved together.
struct ExpenseSettings: Codable {
    var categories: [ExpenseCategory] = []
    /// Merchant key → category: "always use this category for this store".
    var rules: [String: UUID] = [:]
    var overrides: [String: ExpenseOverride] = [:]
    var manual: [ManualExpense] = []
    var totalLimit: Double?
    /// Warn at this share of a limit (0.5–1).
    var alertAt: Double = 0.8
    var largePurchase: Double?
    /// "<yyyymm>|<category id or total>|<warn|over>" and "big|<transaction id>": notifications already sent.
    var notified: Set<String> = []
    /// Merchant key → how the Bills page treats that store. Optional so settings saved before it still load.
    var bills: [String: BillChoice]?
}

/// The user's say over one recurring bill.
struct BillChoice: Codable, Hashable {
    /// true: tracked even when it doesn't look like a bill; false: never shown as one.
    var tracked: Bool?
    /// The day of the month it's due, when the user set it; otherwise it's estimated from the payments.
    var dueDay: Int?
    /// Months (yyyymm) marked as paid by hand, for bills paid from an account that isn't connected.
    var paidByHand: Set<Int>?
}

/// One row of the expenses table: an Open Finance transaction or a manual entry, already classified.
struct Expense: Identifiable, Hashable {
    enum Kind: Hashable { case spending, income, outside }

    /// How the money moved.
    enum Source: String, Hashable {
        case pix, creditCard, debitCard, autoDebit, transfer, boleto, account, manual

        var label: String {
            switch self {
            case .pix: "PIX"
            case .creditCard: String(localized: "Credit card")
            case .debitCard: String(localized: "Debit card")
            case .autoDebit: String(localized: "Automatic debit")
            case .transfer: String(localized: "Transfer")
            case .boleto: "Boleto"
            case .account: String(localized: "Account")
            case .manual: String(localized: "Manual")
            }
        }

        var symbol: String {
            switch self {
            case .pix: "bolt.horizontal"
            case .creditCard: "creditcard"
            case .debitCard: "creditcard.and.123"
            case .autoDebit: "arrow.clockwise.circle"
            case .transfer: "arrow.left.arrow.right"
            case .boleto: "barcode"
            case .account: "building.columns"
            case .manual: "hand.point.up.left"
            }
        }
    }

    var id: String
    var day: Int
    var store: String
    var detail: String
    var amount: Double
    var kind: Kind
    var categoryID: UUID?
    var accountName: String?
    var isCard: Bool
    var isManual: Bool
    var installment: String?
    var merchantKey: String
    var source: Source
    /// A later installment of a card purchase: counted from the 1st of its own month, with no real date.
    var billedLater = false
    /// A purchase in another currency; `amount` is its value in reais.
    var foreign: Foreign?

    struct Foreign: Hashable {
        var amount: Double
        var currency: String
        /// How the reais were found: the bank's own conversion, Yahoo's rate for the day, or not yet.
        var conversion: Conversion
        enum Conversion: Hashable { case bank, rate(Double), missing }
    }
}

@MainActor
@Observable
final class ExpenseStore {
    private(set) var settings = ExpenseSettings()
    /// True until the settings are first saved: the categories are still the built-in starting set.
    private(set) var usingDefaultCategories = false
    /// Transactions by month (yyyymm), fetched only for the months that are opened.
    private(set) var monthsLoaded: [Int: [PluggyTransaction]] = [:]
    private var fetchedAt: [Int: Date] = [:]
    private var loading: Set<Int> = []
    var transactions: [PluggyTransaction] { monthsLoaded.values.flatMap { $0 } }
    /// Classified rows, recomputed only when the data or the user's choices change (`reclassify`).
    private(set) var expenses: [Expense] = []
    private(set) var byMonth: [Int: [Expense]] = [:]
    private var loadedCache = false
    /// Accounts as of the last sync, so cached rows know which are cards before Open Finance syncs again.
    private var cachedAccounts: [PluggyAccount] = []

    private struct Cache: Codable {
        var months: [Int: [PluggyTransaction]]
        var fetchedAt: [Int: Date]
        var accounts: [PluggyAccount]
        /// Months fetched since the bank's converted amounts were read; older copies of months with foreign purchases are fetched again.
        var currencyRead: Set<Int>?
    }
    private var currencyRead: Set<Int> = []
    /// Daily closes of each foreign currency in reais (Yahoo's ARSBRL=X and so on), for purchases the bank didn't convert.
    private var rates: [String: PriceHistory] = [:]
    private var ratesRequested: Set<String> = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var lastSync: Date?
    var suggestionNote: String?

    private let pluggy: PluggyStore
    private static let settingsURL = PortfolioStore.directory.appendingPathComponent("expenses.json")
    /// Banking data is re-downloadable, so it lives in Caches, not next to the portfolio.
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StockBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transactions-by-month.json")
    }()

    init(pluggy: PluggyStore) {
        self.pluggy = pluggy
        if let data = try? Data(contentsOf: Self.settingsURL), let saved = try? JSONDecoder().decode(ExpenseSettings.self, from: data) {
            settings = saved
        } else {
            settings.categories = Self.defaultCategories
            usingDefaultCategories = true
        }
    }

    /// Reads the cached months off the main thread the first time a finance page opens, so launch stays fast.
    private func loadCacheIfNeeded() async {
        guard !loadedCache else { return }
        loadedCache = true
        let url = Self.cacheURL
        let cached = await Task.detached(priority: .userInitiated) {
            (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        }.value
        if let cached {
            monthsLoaded.merge(cached.months) { mine, _ in mine }
            fetchedAt.merge(cached.fetchedAt) { mine, _ in mine }
            cachedAccounts = cached.accounts
            currencyRead.formUnion(cached.currencyRead ?? [])
        }
        reclassify()
    }

    private func writeCache() {
        let url = Self.cacheURL
        let cache = Cache(months: monthsLoaded, fetchedAt: fetchedAt, accounts: pluggy.accounts.isEmpty ? cachedAccounts : pluggy.accounts,
                          currencyRead: currencyRead)
        Task.detached(priority: .utility) { try? JSONEncoder().encode(cache).write(to: url, options: .atomic) }
    }

    private func save() {
        usingDefaultCategories = false
        reclassify()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(settings).write(to: Self.settingsURL, options: .atomic)
    }

    // MARK: - Loading months

    /// Makes a month available: from the cache when it's there, else from Open Finance. A past month is
    /// fetched once; the current month again when its copy is over an hour old.
    func loadMonth(_ month: Int) async {
        await loadCacheIfNeeded()
        let current = DayKey.from(.now) / 100
        let stale = month == current && (fetchedAt[month].map { Date.now.timeIntervalSince($0) > 3600 } ?? true)
        // Copies from before the bank's conversions were read count every foreign amount as reais.
        let unconverted = !currencyRead.contains(month) && (monthsLoaded[month] ?? []).contains { Self.isForeign($0) && $0.amountInAccountCurrency == nil }
        guard monthsLoaded[month] == nil || stale || unconverted else { return }
        await fetch(month)
    }

    /// Card installments arrive with the purchase, so a month's later installments sit in the months before it.
    /// Loads the 11 months before `month`, two at a time; ones already cached cost nothing.
    func loadInstallmentHistory(before month: Int) async {
        let months = (1...11).map { DayKey.addMonths(month * 100 + 1, -$0) / 100 }
        for chunk in stride(from: 0, to: months.count, by: 2) {
            await withTaskGroup(of: Void.self) { group in
                for m in months[chunk..<min(chunk + 2, months.count)] { group.addTask { await self.loadMonth(m) } }
            }
        }
    }

    /// Months of `year` loaded so far by `loadYear`, for its progress bar.
    private(set) var yearProgress: (done: Int, total: Int)?

    /// Every month of a year up to this one, two at a time; months already cached cost nothing.
    func loadYear(_ year: Int) async {
        let current = DayKey.from(.now) / 100
        let months = (1...12).map { year * 100 + $0 }.filter { $0 <= current }
        guard !months.isEmpty else { return }
        yearProgress = (0, months.count)
        defer { yearProgress = nil }
        for chunk in stride(from: 0, to: months.count, by: 2) {
            await withTaskGroup(of: Void.self) { group in
                for m in months[chunk..<min(chunk + 2, months.count)] { group.addTask { await self.loadMonth(m) } }
            }
            yearProgress = (min(chunk + 2, months.count), months.count)
        }
        await loadInstallmentHistory(before: months[0])
    }

    /// Fetches a month again from Open Finance (the Sync button).
    func sync(month: Int) async {
        await loadCacheIfNeeded()
        await fetch(month)
    }

    private func fetch(_ month: Int) async {
        guard !loading.contains(month) else { return }
        guard pluggy.isConfigured, !pluggy.itemIDs.isEmpty else {
            error = String(localized: "Connect a bank in Settings → Open Finance first.")
            return
        }
        loading.insert(month)
        isLoading = true
        error = nil
        defer { loading.remove(month); isLoading = !loading.isEmpty }
        if pluggy.accounts.isEmpty { await pluggy.sync() }
        do {
            monthsLoaded[month] = try await pluggy.fetchTransactions(month: month)
            fetchedAt[month] = .now
            currencyRead.insert(month)
            lastSync = .now
            reclassify()
            writeCache()
            if month == DayKey.from(.now) / 100 { checkAlerts() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Classification

    /// Stores are matched by name, so "IFD*BURGER PLACE" and later charges at the same place share a rule.
    static func merchantKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .uppercased().filter { $0.isLetter || $0.isNumber }
    }


    /// Cards are credit; on a bank account, Pluggy's payment method, then the description ("Pix enviado",
    /// "Compra débito"), tell PIX, debit card, transfers and boletos apart.
    private static func source(of t: PluggyTransaction, isCard: Bool) -> Expense.Source {
        if isCard { return .creditCard }
        let method = (t.paymentData?.paymentMethod ?? "").uppercased()
        let text = ((t.description ?? "") + " " + (t.descriptionRaw ?? "")).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).uppercased()
        let category = (t.category ?? "").lowercased()
        if method == "PIX" || text.contains("PIX") { return .pix }
        if text.contains("COMPRA DEBITO") || text.contains("DEBITO VISA") || text.contains("DEBITO MASTER") || text.contains("CARTAO DEBITO")
            || text.contains("COMPRA CARTAO") || category.contains("debit card") { return .debitCard }
        if text.contains("DEBITO AUTOMATICO") || text.contains("DEB AUTOMATICO") || text.contains("DEB.AUT") { return .autoDebit }
        if method == "BOLETO" || text.contains("BOLETO") || text.contains("PAGAMENTO DE TITULO") { return .boleto }
        if ["TED", "DOC", "TEF"].contains(method) || text.contains("TED ") || text.contains("DOC ") || text.contains("TRANSF") { return .transfer }
        return .account
    }

    /// Bill payments, transfers between one's own accounts, investments and card payments aren't spending.
    private static func looksOutside(_ t: PluggyTransaction, isCard: Bool) -> Bool {
        let category = (t.category ?? "").lowercased()
        let text = ((t.descriptionRaw ?? "") + " " + (t.description ?? "")).uppercased()
        if isCard && t.isCredit { return true }
        if ["credit card payment", "same ownership", "same person", "investment", "proceeds", "savings"].contains(where: category.contains) { return true }
        return ["PAGAMENTO FATURA", "PAG FATURA", "PGTO FATURA", "FATURA CARTAO", "APLICACAO", "RESGATE", "CDB", "TESOURO",
                "TED MESMA TITULARIDADE", "TRANSF ENTRE CONTAS"].contains(where: text.contains)
    }

    private func categoryFor(_ t: PluggyTransaction, merchantKey: String) -> UUID? {
        if let rule = settings.rules[merchantKey], settings.categories.contains(where: { $0.id == rule }) { return rule }
        let pluggyCategory = (t.category ?? t.merchant?.category ?? "").lowercased()
        guard !pluggyCategory.isEmpty else { return nil }
        return settings.categories.first { c in c.pluggyKeywords.contains { pluggyCategory.contains($0.lowercased()) } }?.id
    }

    /// Classifies every transaction and manual entry once and indexes them by month.
    private func reclassify() {
        let accounts = Dictionary((pluggy.accounts.isEmpty ? cachedAccounts : pluggy.accounts).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func accountName(_ id: String?) -> (name: String?, isCard: Bool) {
            let account = id.flatMap { accounts[$0] }
            return (account?.marketingName ?? account?.name, account?.type == "CREDIT")
        }
        var rows: [Expense] = transactions.compactMap { t -> Expense? in
            if case .deleted? = settings.overrides[t.id] { return nil }
            let (account, isCard) = accountName(t.accountId)
            let party = t.isCredit ? t.paymentData?.payer?.name : t.paymentData?.receiver?.name
            let store = [t.merchant?.businessName, t.merchant?.name, party, t.description]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "—"
            let key = Self.merchantKey(store)
            var kind: Expense.Kind = Self.looksOutside(t, isCard: isCard) ? .outside : (t.isCredit ? .income : .spending)
            var category = kind == .spending ? categoryFor(t, merchantKey: key) : nil
            switch settings.overrides[t.id] {
            case .category(let id)?: category = id; if kind == .outside { kind = t.isCredit && !isCard ? .income : .spending }
            case .outside?: kind = .outside; category = nil
            case .deleted?, nil: break
            }
            var installment: String?, day = t.day, billedLater = false
            if let m = t.creditCardMetadata, let n = m.installmentNumber, let total = m.totalInstallments, total > 1 {
                installment = "\(n)/\(total)"
                // Cards send every installment on the purchase day; each one is really billed a month after the last.
                if n > 1 {
                    let purchase = m.purchaseDate.flatMap { Int($0.prefix(10).replacingOccurrences(of: "-", with: "")) } ?? t.day
                    day = DayKey.addMonths(purchase / 100 * 100 + 1, n - 1)
                    billedLater = true
                }
            }
            let (amount, foreign) = reais(t)
            return Expense(id: t.id, day: day, store: store.capitalizedIfShouting, detail: t.descriptionRaw ?? t.description ?? "",
                           amount: amount, kind: kind, categoryID: category, accountName: account, isCard: isCard,
                           isManual: false, installment: installment, merchantKey: key, source: Self.source(of: t, isCard: isCard),
                           billedLater: billedLater, foreign: foreign)
        }
        rows += settings.manual.map { m in
            var kind = Expense.Kind.spending, category = m.categoryID
            if case .outside? = settings.overrides[m.id.uuidString] { kind = .outside; category = nil }
            if case .category(let id)? = settings.overrides[m.id.uuidString] { category = id }
            return Expense(id: m.id.uuidString, day: m.day, store: m.store, detail: String(localized: "Added by hand"), amount: m.amount,
                           kind: kind, categoryID: category, accountName: nil, isCard: false, isManual: true, installment: nil,
                           merchantKey: Self.merchantKey(m.store), source: .manual)
        }
        expenses = rows
        byMonth = Dictionary(grouping: rows) { $0.day / 100 }
        Task { await loadMissingRates() }
    }

    // MARK: - Other currencies

    private static func isForeign(_ t: PluggyTransaction) -> Bool {
        guard let code = t.currencyCode?.uppercased(), !code.isEmpty else { return false }
        return code != "BRL"
    }

    /// The bank's conversion when it gives one, else the currency's close in reais on the purchase day.
    private func reais(_ t: PluggyTransaction) -> (Double, Expense.Foreign?) {
        let original = abs(t.amount ?? 0)
        guard Self.isForeign(t), let code = t.currencyCode?.uppercased() else { return (original, nil) }
        if let converted = t.amountInAccountCurrency {
            return (abs(converted), Expense.Foreign(amount: original, currency: code, conversion: .bank))
        }
        if let rate = rates[code]?.price(onOrBefore: t.day) {
            return (original * rate, Expense.Foreign(amount: original, currency: code, conversion: .rate(rate)))
        }
        return (0, Expense.Foreign(amount: original, currency: code, conversion: .missing))
    }

    /// Fetches each currency's history once per launch, from a week before its oldest unconverted purchase.
    private func loadMissingRates() async {
        var oldest: [String: Int] = [:]
        for t in transactions where Self.isForeign(t) && t.amountInAccountCurrency == nil {
            let code = t.currencyCode!.uppercased()
            if rates[code]?.days.first.map({ $0 <= t.day }) != true { oldest[code] = min(oldest[code] ?? .max, t.day) }
        }
        var fetched = false
        for (code, day) in oldest where !ratesRequested.contains("\(code)\(day)") {
            ratesRequested.insert("\(code)\(day)")
            if let history = try? await MarketData.history(for: "\(code)BRL=X", from: DayKey.date(day).addingTimeInterval(-7 * 86_400)) {
                rates[code] = history
                fetched = true
            }
        }
        if fetched { reclassify() }
    }

    /// Spending per category in a month (yyyymm); uncategorized spending sits under nil.
    func spending(month: Int) -> [UUID?: Double] {
        (byMonth[month] ?? []).filter { $0.kind == .spending && $0.day / 100 == month }
            .reduce(into: [:]) { $0[$1.categoryID, default: 0] += $1.amount }
    }

    func category(_ id: UUID?) -> ExpenseCategory? { settings.categories.first { $0.id == id } }

    // MARK: - Editing

    /// Sets a transaction's category; with `forStore`, every transaction from the same store follows (now and later).
    func setCategory(_ id: UUID?, for expense: Expense, forStore: Bool = false) {
        if let id {
            settings.overrides[expense.id] = .category(id)
            if forStore {
                settings.rules[expense.merchantKey] = id
                // Rows the user hadn't set by hand follow the new rule.
                for row in expenses where row.merchantKey == expense.merchantKey && row.id != expense.id {
                    if case .category? = settings.overrides[row.id] { settings.overrides[row.id] = nil }
                }
            }
        } else {
            settings.overrides[expense.id] = nil
        }
        save()
        checkAlerts()
    }

    func setOutside(_ outside: Bool, for expense: Expense) {
        settings.overrides[expense.id] = outside ? .outside : nil
        save()
    }

    func addManual(_ entry: ManualExpense) {
        settings.manual.append(entry)
        save()
        checkAlerts()
    }

    /// Manual entries are removed; Open Finance ones are hidden for good, so the next sync doesn't bring them back.
    func delete(_ expense: Expense) {
        if expense.isManual {
            settings.manual.removeAll { $0.id.uuidString == expense.id }
            settings.overrides[expense.id] = nil
        } else {
            settings.overrides[expense.id] = .deleted
        }
        save()
    }

    func saveCategory(_ category: ExpenseCategory) {
        if let i = settings.categories.firstIndex(where: { $0.id == category.id }) { settings.categories[i] = category }
        else { settings.categories.append(category) }
        save()
        checkAlerts()
    }

    /// Its transactions go back to "to review"; rules pointing at it are dropped.
    func deleteCategory(_ category: ExpenseCategory) {
        settings.categories.removeAll { $0.id == category.id }
        settings.rules = settings.rules.filter { $0.value != category.id }
        settings.overrides = settings.overrides.filter { if case .category(let id) = $0.value { id != category.id } else { true } }
        settings.manual = settings.manual.map { var m = $0; if m.categoryID == category.id { m.categoryID = nil }; return m }
        save()
    }

    /// Whether there's already a category like this one: same name, or the same Pluggy mapping (a default created
    /// in another language).
    func hasCategory(like other: ExpenseCategory) -> Bool {
        settings.categories.contains { $0.isLike(other) }
    }

    /// The setup guide's answer. While the categories are still the starting set they become the picks (in the
    /// guide's order); afterwards picks are only added, so nothing the user set up is lost.
    func adoptCategories(_ picks: [ExpenseCategory], replacingDefaults: Bool) {
        if replacingDefaults {
            settings.categories = picks.map { pick in settings.categories.first { $0.isLike(pick) } ?? pick }
            let ids = Set(settings.categories.map(\.id))
            settings.rules = settings.rules.filter { ids.contains($0.value) }
            settings.overrides = settings.overrides.filter { if case .category(let id) = $0.value { ids.contains(id) } else { true } }
        } else {
            settings.categories += picks.filter { !hasCategory(like: $0) }
        }
        save()
    }

    func moveCategories(from source: IndexSet, to destination: Int) {
        settings.categories.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func billChoice(_ key: String) -> BillChoice { settings.bills?[key] ?? BillChoice() }

    func setBillChoice(_ choice: BillChoice, for key: String) {
        var bills = settings.bills ?? [:]
        bills[key] = choice == BillChoice() ? nil : choice
        settings.bills = bills
        save()
    }

    func setTotalLimit(_ value: Double?) { settings.totalLimit = value; save() }
    func setAlertAt(_ value: Double) { settings.alertAt = value; save() }
    func setLargePurchase(_ value: Double?) { settings.largePurchase = value; save() }

    /// Average monthly spending of each category over the three months before this one (fetched if needed),
    /// plus 10%, rounded up to R$ 10.
    func suggestLimits() async {
        let current = DayKey.from(.now) / 100
        let history = (1...3).map { DayKey.addMonths(current * 100 + 1, -$0) / 100 }
        for m in history { await loadMonth(m) }
        let rows = expenses
        let months = Set(rows.filter { $0.kind == .spending && history.contains($0.day / 100) }.map { $0.day / 100 })
        guard !months.isEmpty else {
            suggestionNote = String(localized: "Not enough history yet: sync at least one full month first.")
            return
        }
        var count = 0
        for i in settings.categories.indices {
            let id = settings.categories[i].id
            let total = rows.filter { $0.kind == .spending && $0.categoryID == id && months.contains($0.day / 100) }.reduce(0) { $0 + $1.amount }
            guard total > 0 else { continue }
            settings.categories[i].limit = (total / Double(months.count) * 1.1 / 10).rounded(.up) * 10
            count += 1
        }
        settings.totalLimit = settings.categories.compactMap(\.limit).reduce(0, +)
        suggestionNote = String(localized: "Suggested \(count) limits from the average of the previous \(months.count) months + 10%. Adjust as you like.")
        save()
    }

    // MARK: - Alerts

    /// Notifies once per month per category when spending crosses the warning share and again over the limit,
    /// the same for the total, and once per large purchase this month.
    func checkAlerts() {
        let month = DayKey.from(.now) / 100
        let rows = expenses
        let spent = spending(month: month)
        var messages: [(key: String, title: String, body: String)] = []
        func check(_ key: String, name: String, spent: Double, limit: Double?) {
            guard let limit, limit > 0 else { return }
            if spent > limit {
                messages.append(("\(month)|\(key)|over", String(localized: "\(name): limit exceeded"),
                                 String(localized: "\(spent.reais) spent this month, over the \(limit.reais) limit.")))
            } else if spent >= limit * settings.alertAt {
                messages.append(("\(month)|\(key)|warn", String(localized: "\(name): \(Int((spent / limit * 100).rounded()))% of the limit"),
                                 String(localized: "\(spent.reais) of \(limit.reais) spent this month.")))
            }
        }
        for c in settings.categories { check(c.id.uuidString, name: c.name, spent: spent[c.id] ?? 0, limit: c.limit) }
        check("total", name: String(localized: "Monthly total"), spent: spent.values.reduce(0, +), limit: settings.totalLimit)
        if let large = settings.largePurchase, large > 0 {
            for e in byMonth[month] ?? [] where e.kind == .spending && !e.billedLater && e.amount >= large {
                messages.append(("big|\(e.id)", String(localized: "Large purchase: \(e.amount.reais)"), "\(e.store) · \(e.detail)"))
            }
        }
        let fresh = messages.filter { !settings.notified.contains($0.key) }
        guard !fresh.isEmpty else { return }
        for m in fresh { settings.notified.insert(m.key) }
        save()
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for m in fresh.prefix(5) {
                let content = UNMutableNotificationContent()
                content.title = m.title
                content.body = m.body
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: m.key, content: content, trigger: nil))
            }
        }
    }

    // MARK: - Defaults

    /// What the setup guide offers, in the order they're kept: most of the starting set, plus two that only
    /// make sense when someone says they have them.
    static var onboardingCategories: [ExpenseCategory] {
        let defaults = defaultCategories
        func starting(_ symbol: String) -> ExpenseCategory { defaults.first { $0.symbol == symbol }! }
        return [
            ExpenseCategory(name: String(localized: "Fixed expenses"), symbol: "pin", pluggyKeywords: ["insurance", "loan", "financing"]),
            starting("bolt"),                          // Housing & Bills
            starting("arrow.triangle.2.circlepath"),   // Subscriptions & Apps
            starting("pawprint"),                      // Pets
            // Ahead of Transport & Travel, so fuel and parking land here when both are picked.
            ExpenseCategory(name: String(localized: "Car"), symbol: "car.side", pluggyKeywords: ["gas station", "parking", "toll", "vehicle", "automotive"]),
            starting("cart"),                          // Groceries & Cleaning
            starting("fork.knife"),                    // Delivery & Restaurants
            starting("cross.case"),                    // Health & Pharmacy
            starting("car"),                           // Transport & Travel
            starting("gamecontroller"),                // Leisure & Games
            starting("bag"),                           // Shopping
            starting("book"),                          // Books & Education
        ]
    }

    /// A starting set, named in the app's language, mapped to Pluggy's categories.
    static var defaultCategories: [ExpenseCategory] {
        [
            ExpenseCategory(name: String(localized: "Groceries & Cleaning"), symbol: "cart", pluggyKeywords: ["groceries", "supermarket"]),
            ExpenseCategory(name: String(localized: "Home & Furniture"), symbol: "house", pluggyKeywords: ["home", "furniture", "houseware", "housing improvement"]),
            ExpenseCategory(name: String(localized: "Delivery & Restaurants"), symbol: "fork.knife", pluggyKeywords: ["eating out", "restaurant", "food delivery", "delivery", "food and drinks"]),
            ExpenseCategory(name: String(localized: "Transport & Travel"), symbol: "car", pluggyKeywords: ["transport", "taxi", "ride", "gas station", "parking", "travel", "airline", "accommodation", "toll"]),
            ExpenseCategory(name: String(localized: "Health & Pharmacy"), symbol: "cross.case", pluggyKeywords: ["health", "pharmacy", "hospital", "dentist", "medical"]),
            ExpenseCategory(name: String(localized: "Beauty & Self-care"), symbol: "sparkles", pluggyKeywords: ["beauty", "wellness", "gym", "fitness"]),
            ExpenseCategory(name: String(localized: "Electronics & Tech"), symbol: "laptopcomputer", pluggyKeywords: ["electronics", "technology"]),
            ExpenseCategory(name: String(localized: "Subscriptions & Apps"), symbol: "arrow.triangle.2.circlepath", pluggyKeywords: ["subscription", "streaming", "digital services", "software"]),
            ExpenseCategory(name: String(localized: "Books & Education"), symbol: "book", pluggyKeywords: ["education", "books", "school", "university"]),
            ExpenseCategory(name: String(localized: "Pets"), symbol: "pawprint", pluggyKeywords: ["pet"]),
            ExpenseCategory(name: String(localized: "Clothing & Accessories"), symbol: "tshirt", pluggyKeywords: ["clothing", "apparel", "fashion"]),
            ExpenseCategory(name: String(localized: "Leisure & Games"), symbol: "gamecontroller", pluggyKeywords: ["leisure", "entertainment", "games", "gaming", "cinema", "tickets"]),
            ExpenseCategory(name: String(localized: "Housing & Bills"), symbol: "bolt", pluggyKeywords: ["bills", "utilities", "electricity", "water", "rent", "telecommunications", "internet", "mobile", "taxes", "housing"]),
            ExpenseCategory(name: String(localized: "PIX & Transfers"), symbol: "arrow.left.arrow.right", pluggyKeywords: ["transfer", "pix"]),
            ExpenseCategory(name: String(localized: "Shopping"), symbol: "bag", pluggyKeywords: ["shopping", "online shopping", "department store"]),
        ]
    }
}

extension String {
    /// Banks send "IFOOD.COM AGENCIA DE R"; show "Ifood.com Agencia de R" unless the name already has lower case.
    var capitalizedIfShouting: String {
        guard self == uppercased(), contains(where: \.isLetter) else { return self }
        return localizedCapitalized
    }
}
