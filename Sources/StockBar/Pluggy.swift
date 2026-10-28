import Foundation
import Observation
import Security

// MARK: - API models (fields Pluggy may omit are optional)

struct PluggyItem: Decodable, Identifiable {
    struct Connector: Decodable { var id: Int?; var name: String?; var imageUrl: String? }
    struct ItemError: Decodable { var code: String?; var message: String? }
    var id: String
    var status: String?
    var executionStatus: String?
    var updatedAt: String?
    var lastUpdatedAt: String?
    var connector: Connector?
    var error: ItemError?
}

struct PluggyAccount: Codable, Identifiable {
    var id: String
    var itemId: String?
    var type: String?
    var subtype: String?
    var name: String?
    var marketingName: String?
    var number: String?
    var balance: Double?
    var currencyCode: String?
}

/// A bank, card or PIX transaction. Bank accounts: DEBIT leaves the account, CREDIT comes in.
/// Credit cards: DEBIT is a purchase; payments of the bill and refunds come as CREDIT.
struct PluggyTransaction: Codable, Identifiable, Hashable {
    var id: String
    var accountId: String?
    var description: String?
    var descriptionRaw: String?
    var amount: Double?
    var currencyCode: String?
    /// For purchases in another currency, the amount the bank converted it to; nil when it doesn't say.
    var amountInAccountCurrency: Double?
    var date: String?
    var type: String?
    var category: String?
    var status: String?
    var merchant: Merchant?
    var creditCardMetadata: CardMetadata?
    var paymentData: PaymentData?

    struct Merchant: Codable, Hashable {
        var name: String?
        var businessName: String?
        var cnpj: String?
        var category: String?
    }

    struct CardMetadata: Codable, Hashable {
        var installmentNumber: Int?
        var totalInstallments: Int?
        var totalAmount: Double?
        var purchaseDate: String?
        var billId: String?
    }

    /// PIX and transfers: who paid or got paid.
    struct PaymentData: Codable, Hashable {
        struct Party: Codable, Hashable { var name: String? }
        var payer: Party?
        var receiver: Party?
        var paymentMethod: String?
    }

    var isCredit: Bool { (type ?? "").uppercased() == "CREDIT" }
    /// yyyymmdd, from the purchase date for card installments' first charge or the transaction date.
    var day: Int { Int((date ?? "").prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0 }
}

struct PluggyInvestment: Decodable, Identifiable {
    var id: String
    var itemId: String?
    var name: String?
    var code: String?
    var isin: String?
    var number: String?
    var type: String?
    var subtype: String?
    var status: String?
    var balance: Double?
    var amount: Double?
    var amountOriginal: Double?
    var amountProfit: Double?
    var quantity: Double?
    var value: Double?
    var taxes: Double?
    var taxes2: Double?
    var issuer: String?
    var issuerCNPJ: String?
    var issueDate: String?
    var purchaseDate: String?
    var dueDate: String?
    var date: String?
    var rate: Double?
    var rateType: String?
    var fixedAnnualRate: Double?
    var lastMonthRate: Double?
    var lastTwelveMonthsRate: Double?
    var currencyCode: String?

    /// Average price paid per unit, when Open Finance reports the amount invested or the profit.
    var averagePrice: Double? {
        guard let quantity, quantity > 0 else { return nil }
        if let original = amountOriginal, original > 0 { return original / quantity }
        if let gross = amount ?? balance, let profit = amountProfit, gross - profit > 0 { return (gross - profit) / quantity }
        return nil
    }
}

/// A closed credit card bill (Open Finance): what's due and when, and the payments made against it.
struct PluggyBill: Codable, Identifiable, Hashable {
    var id: String
    var accountId: String?
    var dueDate: String?
    var billClosingDate: String?
    var totalAmount: Double?
    var totalAmountCurrencyCode: String?
    var minimumPaymentAmount: Double?
    var payments: [Payment]?

    struct Payment: Codable, Hashable {
        var paymentDate: String?
        var amount: Double?
    }
}

/// A loan or financing contract (Open Finance). There's no "next due date": it follows from the first
/// installment's due date, the periodicity and how many installments are paid.
struct PluggyLoan: Codable, Identifiable, Hashable {
    var id: String
    var itemId: String?
    var productName: String?
    var type: String?
    var contractAmount: Double?
    var currencyCode: String?
    var contractDate: String?
    /// When the last installment falls due.
    var dueDate: String?
    var firstInstallmentDueDate: String?
    /// "MENSAL", "SEMANAL", "SEM_PERIODICIDADE_REGULAR"…
    var installmentPeriodicity: String?
    var installments: Installments?
    var payments: Payments?

    struct Installments: Codable, Hashable {
        var totalNumberOfInstallments: Double?
        var contractRemainingNumber: Double?
        var paidInstallments: Double?
        var dueInstallments: Double?
        var pastDueInstallments: Double?
    }

    struct Payments: Codable, Hashable {
        var contractOutstandingBalance: Double?
        var releases: [Release]?

        struct Release: Codable, Hashable {
            var paidDate: String?
            var paidAmount: Double?
        }
    }
}

private struct PluggyFailure: Decodable { var message: String? }

private struct Page<T: Decodable>: Decodable {
    var results: [T]
    var page: Int?
    var totalPages: Int?
}

enum PluggyError: LocalizedError {
    case missingCredentials, http(Int, String)
    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Add your Pluggy client ID and secret in Settings."
        case let .http(code, message): "Pluggy returned \(code): \(message)"
        }
    }
}

// MARK: - Client

/// Pluggy's REST API (api.pluggy.ai): client credentials buy a 2-hour API key, sent as X-API-KEY.
actor PluggyClient {
    private let clientId: String
    private let clientSecret: String
    private var apiKey: (key: String, expires: Date)?
    private static let base = URL(string: "https://api.pluggy.ai")!

    init(clientId: String, clientSecret: String) {
        self.clientId = clientId
        self.clientSecret = clientSecret
    }

    private func key() async throws -> String {
        if let apiKey, apiKey.expires > .now { return apiKey.key }
        var request = URLRequest(url: Self.base.appendingPathComponent("auth"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["clientId": clientId, "clientSecret": clientSecret])
        struct Auth: Decodable { var apiKey: String }
        let auth: Auth = try await send(request)
        apiKey = (auth.apiKey, Date.now.addingTimeInterval(110 * 60))
        return auth.apiKey
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.setValue(try await key(), forHTTPHeaderField: "X-API-KEY")
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONDecoder().decode(PluggyFailure.self, from: data))?.message ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw PluggyError.http(code, message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Checks the credentials (Meu Pluggy accounts can't list items, so this only authenticates).
    func authenticate() async throws { _ = try await key() }

    func item(_ id: String) async throws -> PluggyItem { try await get("items/\(id)") }

    /// A 30-minute token for the Connect widget; with `itemId`, the widget reconnects that item instead of adding one.
    func connectToken(updating itemId: String?) async throws -> String {
        var request = URLRequest(url: Self.base.appendingPathComponent("connect_token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(try await key(), forHTTPHeaderField: "X-API-KEY")
        // No avoidDuplicates: MeuPluggy items carry no credentials, so Pluggy would treat every new one as a
        // duplicate, yet each one shares a different institution. StockBar dedupes by accounts after syncing.
        var body: [String: Any] = [:]
        if let itemId { body["itemId"] = itemId }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        struct Token: Decodable { var accessToken: String }
        let token: Token = try await send(request)
        return token.accessToken
    }

    /// The MeuPluggy connector's id: personal applications connect through it, reusing the consent given in Meu Pluggy.
    func meuPluggyConnectorId() async -> Int? {
        struct Connector: Decodable { var id: Int; var name: String }
        guard let page: Page<Connector> = try? await get("connectors", ["name": "MeuPluggy"]) else { return nil }
        let fold = { (s: String) in s.lowercased().filter(\.isLetter) }
        return page.results.first { fold($0.name) == "meupluggy" }?.id
    }

    func accounts(item: String) async throws -> [PluggyAccount] { try await all("accounts", item: item) }

    func investments(item: String) async throws -> [PluggyInvestment] { try await all("investments", item: item) }

    /// Transactions dated `from`...`to` (yyyymmdd, inclusive), following the cursor the API hands back.
    func transactions(account: String, from: Int, to: Int) async throws -> [PluggyTransaction] {
        struct CursorPage: Decodable { var results: [PluggyTransaction]; var next: String? }
        func iso(_ d: Int) -> String { String(format: "%04d-%02d-%02d", d / 10_000, d / 100 % 100, d % 100) }
        let query = ["accountId": account, "dateFrom": iso(from), "dateTo": iso(to)]
        var results: [PluggyTransaction] = []
        var page: CursorPage = try await get("v2/transactions", query)
        results += page.results
        while let next = page.next, !next.isEmpty,
              let after = URLComponents(string: next.hasPrefix("?") ? next : "?" + next)?.queryItems?.first(where: { $0.name == "after" })?.value {
            page = try await get("v2/transactions", query.merging(["after": after]) { $1 })
            results += page.results
        }
        return results.map { var t = $0; t.accountId = t.accountId ?? account; return t }
    }

    func loans(item: String) async throws -> [PluggyLoan] { try await all("loans", item: item) }

    /// A card's closed bills.
    func bills(account: String) async throws -> [PluggyBill] {
        try await all("bills", ["accountId": account]).map { var b: PluggyBill = $0; b.accountId = b.accountId ?? account; return b }
    }

    private func all<T: Decodable>(_ path: String, item: String) async throws -> [T] { try await all(path, ["itemId": item]) }

    private func all<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> [T] {
        var results: [T] = [], page = 1
        while true {
            let p: Page<T> = try await get(path, query.merging(["page": String(page), "pageSize": "500"]) { $1 })
            results += p.results
            guard let total = p.totalPages, page < total else { return results }
            page += 1
        }
    }
}

// MARK: - Keychain

/// The client secret lives in the login keychain, never in files or defaults.
enum Keychain {
    private static let service = "StockBar Pluggy"

    static func secret(for account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setSecret(_ secret: String, for account: String) -> Bool {
        deleteSecret(for: account)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account, kSecValueData as String: Data(secret.utf8)]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func deleteSecret(for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Store

/// Open Finance data pulled through Pluggy for the items (bank connections) the user registered.
@MainActor
@Observable
final class PluggyStore {
    var clientId: String { didSet { UserDefaults.standard.set(clientId, forKey: "pluggyClientId") } }
    private(set) var itemIDs: [String] { didSet { UserDefaults.standard.set(itemIDs, forKey: "pluggyItems") } }
    private(set) var hasSecret = false

    private(set) var items: [PluggyItem] = []
    private(set) var accounts: [PluggyAccount] = []
    private(set) var investments: [PluggyInvestment] = []
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var error: String?
    /// What the last sync changed to match Open Finance; nil when it didn't get to match.
    private(set) var syncChanges: [OpenFinanceChange]?
    /// Applies a sync's investments to what StockBar tracks (see `OpenFinanceMatcher.reconcile`).
    var reconcile: (@MainActor ([PluggyInvestment]) -> [OpenFinanceChange])?

    init() {
        clientId = UserDefaults.standard.string(forKey: "pluggyClientId") ?? ""
        itemIDs = UserDefaults.standard.stringArray(forKey: "pluggyItems") ?? []
        hasSecret = !clientId.isEmpty && Keychain.secret(for: clientId) != nil
    }

    var isConfigured: Bool { !clientId.isEmpty && hasSecret }

    func saveSecret(_ secret: String) {
        guard !clientId.isEmpty, !secret.isEmpty else { return }
        hasSecret = Keychain.setSecret(secret, for: clientId)
    }

    func forgetCredentials() {
        if !clientId.isEmpty { Keychain.deleteSecret(for: clientId) }
        hasSecret = false
        items = []; accounts = []; investments = []
    }

    /// What the Connect widget needs: a fresh token, and the MeuPluggy connector to offer when it can be found.
    func connectSession(updating itemId: String?) async throws -> (token: String, connectorId: Int?) {
        guard isConfigured, let secret = Keychain.secret(for: clientId) else { throw PluggyError.missingCredentials }
        let client = PluggyClient(clientId: clientId, clientSecret: secret)
        async let token = client.connectToken(updating: itemId)
        async let connector = client.meuPluggyConnectorId()
        return (try await token, await connector)
    }

    /// After the widget succeeds: keep the item (a reconnect can hand back a new id) and sync it. If an older
    /// connection turns out to share the same accounts (the same institution connected twice), it's dropped from
    /// StockBar so nothing is counted twice; it stays in Pluggy. Returns the names of those dropped.
    @discardableResult
    func connected(itemId: String, replacing old: String?) async -> [String] {
        let id = itemId.lowercased()
        if let old, old != id { removeItem(old) }
        addItem(id)
        await sync()
        func signature(_ item: String) -> Set<String> {
            Set(accounts.filter { $0.itemId == item }.map { "\($0.type ?? "")|\($0.number ?? "")|\($0.marketingName ?? $0.name ?? "")" })
        }
        let fresh = signature(id)
        guard !fresh.isEmpty else { return [] }
        var dropped: [String] = []
        for other in itemIDs where other != id {
            let theirs = signature(other)
            if !theirs.isEmpty, theirs.isSubset(of: fresh) {
                dropped.append(items.first { $0.id == other }?.connector?.name ?? other)
                removeItem(other)
            }
        }
        if !dropped.isEmpty { await sync() }
        return dropped
    }

    /// The institutions behind a connection, from its accounts (a MeuPluggy item is named after the connector only).
    func institutions(of item: String) -> String? {
        let names = accounts.filter { $0.itemId == item && $0.type == "BANK" }.compactMap { $0.marketingName ?? $0.name }
        let all = names.isEmpty ? accounts.filter { $0.itemId == item }.compactMap { $0.marketingName ?? $0.name } : names
        return all.isEmpty ? nil : Array(NSOrderedSet(array: all)).compactMap { $0 as? String }.joined(separator: ", ")
    }

    /// Items that need the user again: consent expired after a year, or a login error.
    func needsReconnect(_ id: String) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        return item.error != nil || ["LOGIN_ERROR", "OUTDATED", "WAITING_USER_INPUT"].contains(item.status ?? "")
    }

    func addItem(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard UUID(uuidString: trimmed) != nil, !itemIDs.contains(trimmed) else { return }
        itemIDs.append(trimmed)
    }

    func removeItem(_ id: String) {
        itemIDs.removeAll { $0 == id }
        items.removeAll { $0.id == id }
        accounts.removeAll { $0.itemId == id }
        investments.removeAll { $0.itemId == id }
    }

    /// One month's (yyyymm) transactions of every bank account and credit card, side by side.
    func fetchTransactions(month: Int) async throws -> [PluggyTransaction] {
        guard isConfigured, let secret = Keychain.secret(for: clientId) else { throw PluggyError.missingCredentials }
        let client = PluggyClient(clientId: clientId, clientSecret: secret)
        let from = month * 100 + 1, to = month * 100 + DayKey.daysInMonth(month * 100 + 1)
        let ids = accounts.filter { $0.type == "BANK" || $0.type == "CREDIT" }.map(\.id)
        return try await withThrowingTaskGroup(of: [PluggyTransaction].self) { group in
            for id in ids { group.addTask { try await client.transactions(account: id, from: from, to: to) } }
            return try await group.reduce(into: []) { $0 += $1 }
        }
    }

    /// Every card's closed bills and every connection's loans. Each one is asked on its own, so a bank that
    /// doesn't share one of them only adds a line to `failures`.
    func fetchBillsAndLoans() async throws -> (bills: [PluggyBill], loans: [PluggyLoan], cards: Int, failures: [String]) {
        guard isConfigured, let secret = Keychain.secret(for: clientId) else { throw PluggyError.missingCredentials }
        if accounts.isEmpty { await sync() }
        let client = PluggyClient(clientId: clientId, clientSecret: secret)
        let cards = accounts.filter { $0.type == "CREDIT" }
        var bills: [PluggyBill] = [], loans: [PluggyLoan] = [], failures: [String] = []
        for card in cards {
            do { bills += try await client.bills(account: card.id) }
            catch { failures.append(String(localized: "Bills of \(card.marketingName ?? card.name ?? "a card"): \(error.localizedDescription)")) }
        }
        for id in itemIDs {
            do { loans += try await client.loans(item: id).map { var l = $0; l.itemId = l.itemId ?? id; return l } }
            catch { failures.append(String(localized: "Loans of \(institutions(of: id) ?? String(id.prefix(8))): \(error.localizedDescription)")) }
        }
        return (bills, loans, cards.count, failures)
    }

    /// Authenticates, then fetches each item with its accounts and investments.
    func sync() async {
        guard !isSyncing else { return }
        guard isConfigured, let secret = Keychain.secret(for: clientId) else { error = PluggyError.missingCredentials.errorDescription; return }
        isSyncing = true
        error = nil
        defer { isSyncing = false }
        let client = PluggyClient(clientId: clientId, clientSecret: secret)
        do {
            try await client.authenticate()
            var newItems: [PluggyItem] = [], newAccounts: [PluggyAccount] = [], newInvestments: [PluggyInvestment] = []
            var failures: [String] = []
            for id in itemIDs {
                do {
                    newItems.append(try await client.item(id))
                    newAccounts += try await client.accounts(item: id).map { var a = $0; a.itemId = a.itemId ?? id; return a }
                    newInvestments += try await client.investments(item: id).map { var i = $0; i.itemId = i.itemId ?? id; return i }
                } catch {
                    failures.append("\(id.prefix(8))…: \(error.localizedDescription)")
                }
            }
            items = newItems
            accounts = newAccounts
            investments = newInvestments
            lastSync = .now
            if failures.isEmpty {
                syncChanges = reconcile?(newInvestments)
            } else {
                // A missing institution would look like positions sold; match again once they all respond.
                syncChanges = nil
                error = (failures + [String(localized: "Positions weren't updated: sync again once every connection responds.")]).joined(separator: "\n")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
