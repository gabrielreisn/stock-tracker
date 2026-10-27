import Foundation
import Observation

/// Where a bill is this month.
enum BillStatus: Hashable { case paid, upcoming, late }

/// A bill that comes back every month: boletos, automatic debits and financing installments paid from a bank
/// account, or any store the user chose to track. Open Finance only says when each one was paid, so the due
/// day is estimated from the last payments unless the user sets it.
struct RecurringBill: Identifiable {
    var id: String { key }
    let key: String
    let name: String
    let source: Expense.Source
    let dueDay: Int
    let dueDaySet: Bool
    /// The average month over the last months it was paid.
    let usual: Double
    let lastPayment: Expense?
    let paidThisMonth: [Expense]
    let paidByHand: Bool
    /// From "Parcela 012 de 360": the latest installment paid and how many there are.
    let installment: (number: Int, total: Int)?
    let trackedByHand: Bool
    /// This month's due date while unpaid, next month's once paid.
    let nextDue: Int
    let status: BillStatus
}

/// A card's latest closed bill.
struct CardBillSummary: Identifiable {
    let id: String
    let card: String
    let closing: Int?
    let due: Int
    let total: Double
    let minimum: Double?
    let paid: Double
    let status: BillStatus
    /// A month after this one's due date, once it's paid; the bank only shares a bill after it closes.
    let nextDue: Int?
}

/// A loan or financing contract, with its next installment worked out.
struct LoanSummary: Identifiable {
    let id: String
    let name: String
    let paid: Int?
    let total: Int?
    let balance: Double?
    let nextDue: Int?
    let lastDue: Int?
    let lastPayment: (day: Int, amount: Double)?
    let pastDue: Int
}

/// One line of the "Upcoming" list.
struct UpcomingBill: Identifiable {
    enum Origin { case recurring, card, loan }
    let id: String
    let name: String
    let symbol: String
    let day: Int
    let amount: Double?
    /// The date comes from the bank (a card bill or a loan), not from past payments.
    let exact: Bool
    let late: Bool
    let origin: Origin
}

/// Card bills and loans from Open Finance, and the recurring bills found in the transactions.
@MainActor
@Observable
final class BillStore {
    private(set) var cardBills: [PluggyBill] = []
    private(set) var loans: [PluggyLoan] = []
    private(set) var cardsAsked = 0
    /// What a bank wouldn't share (the product isn't in its consent, or it failed).
    private(set) var failures: [String] = []
    private(set) var fetchedAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    private var cardNames: [String: String] = [:]
    private var loadedCache = false

    private let pluggy: PluggyStore
    private let expenses: ExpenseStore

    private struct Cache: Codable {
        var bills: [PluggyBill]
        var loans: [PluggyLoan]
        var cardsAsked: Int
        var failures: [String]
        var cardNames: [String: String]
        var fetchedAt: Date
    }
    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("StockBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("bills-and-loans.json")
    }()

    init(pluggy: PluggyStore, expenses: ExpenseStore) {
        self.pluggy = pluggy
        self.expenses = expenses
    }

    /// The cached copy, then Open Finance again when that's over six hours old.
    func load() async {
        if !loadedCache {
            loadedCache = true
            let url = Self.cacheURL
            let cached = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
            }.value
            if let cached {
                cardBills = cached.bills; loans = cached.loans; cardsAsked = cached.cardsAsked
                failures = cached.failures; cardNames = cached.cardNames; fetchedAt = cached.fetchedAt
            }
        }
        if fetchedAt.map({ Date.now.timeIntervalSince($0) > 6 * 3600 }) ?? true { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        guard pluggy.isConfigured, !pluggy.itemIDs.isEmpty else {
            error = String(localized: "Connect a bank in Settings → Open Finance first.")
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await pluggy.fetchBillsAndLoans()
            cardBills = result.bills
            loans = result.loans
            cardsAsked = result.cards
            failures = result.failures
            for a in pluggy.accounts where a.type == "CREDIT" { cardNames[a.id] = a.marketingName ?? a.name }
            fetchedAt = .now
            let cache = Cache(bills: cardBills, loans: loans, cardsAsked: cardsAsked, failures: failures, cardNames: cardNames, fetchedAt: .now)
            let url = Self.cacheURL
            Task.detached(priority: .utility) { try? JSONEncoder().encode(cache).write(to: url, options: .atomic) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Cards that returned at least one bill.
    var cardsWithBills: Int { Set(cardBills.compactMap(\.accountId)).count }

    // MARK: - Recurring bills

    /// Payments are seen this many days after the due day before a bill counts as late.
    private static let grace = 3

    /// Bills that showed up in at least 2 of the 3 months before this one, or that the user tracks.
    func recurring(today: Int = DayKey.from(.now)) -> [RecurringBill] {
        let month = today / 100
        let previous = (1...3).map { DayKey.addMonths(month * 100 + 1, -$0) / 100 }
        let choices = expenses.settings.bills ?? [:]
        let tracked = Set(choices.filter { $0.value.tracked == true }.keys)
        let rows = expenses.expenses.filter {
            !$0.isCard && $0.kind != .income && $0.amount > 0 && $0.day / 100 <= month
                && ($0.day / 100 >= previous.last! || tracked.contains(Self.key(for: $0)))
        }
        var bills: [RecurringBill] = []
        for (key, payments) in Dictionary(grouping: rows, by: Self.key(for:)) {
            let choice = choices[key] ?? BillChoice()
            guard choice.tracked != false else { continue }
            let looksLikeBill = payments.contains { $0.kind != .outside && ($0.source == .boleto || $0.source == .autoDebit || Self.financing($0.detail) != nil) }
            let months = Set(payments.map { $0.day / 100 }).intersection(previous)
            guard choice.tracked == true || (looksLikeBill && months.count >= 2) else { continue }

            let sorted = payments.sorted { $0.day < $1.day }
            let past = sorted.filter { $0.day / 100 < month }
            let days = (past.isEmpty ? sorted : Array(past.suffix(3))).map { $0.day % 100 }.sorted()
            let dueDay = choice.dueDay ?? days[days.count / 2]
            let perMonth = Dictionary(grouping: past.suffix(6), by: { $0.day / 100 }).mapValues { $0.reduce(0) { $0 + $1.amount } }
            let usual = perMonth.isEmpty ? sorted.last!.amount : perMonth.values.reduce(0, +) / Double(perMonth.count)
            let thisMonth = sorted.filter { $0.day / 100 == month }
            let byHand = choice.paidByHand?.contains(month) == true
            let dueNow = Self.day(dueDay, inMonth: month)
            let paid = !thisMonth.isEmpty || byHand
            let status: BillStatus = paid ? .paid : Self.days(from: dueNow, to: today) > Self.grace ? .late : .upcoming
            bills.append(RecurringBill(
                key: key, name: sorted.last!.store, source: sorted.last!.source, dueDay: dueDay, dueDaySet: choice.dueDay != nil,
                usual: usual, lastPayment: sorted.last, paidThisMonth: thisMonth, paidByHand: byHand,
                installment: sorted.reversed().lazy.compactMap { Self.financing($0.detail) }.first, trackedByHand: choice.tracked == true,
                nextDue: paid ? Self.day(dueDay, inMonth: DayKey.addMonths(month * 100 + 1, 1) / 100) : dueNow, status: status))
        }
        return bills.sorted { ($0.dueDay, $0.name) < ($1.dueDay, $1.name) }
    }

    /// What ties a bill's payments together: the store, except for automatic debits, whose description
    /// ("Débito automático DA ENERGIA CIA") stays put when the bank renames the company behind it.
    static func key(for e: Expense) -> String {
        guard e.source == .autoDebit else { return e.merchantKey }
        return "debit:" + ExpenseStore.merchantKey(e.detail.filter { !$0.isNumber })
    }

    /// Stores the user stopped tracking, to bring them back.
    var hidden: [(key: String, name: String)] {
        let keys = (expenses.settings.bills ?? [:]).filter { $0.value.tracked == false }.keys
        let names = Dictionary(expenses.expenses.map { (Self.key(for: $0), $0.store) }, uniquingKeysWith: { a, _ in a })
        return keys.map { ($0, names[$0] ?? $0) }.sorted { $0.name < $1.name }
    }

    /// "Parcela 012 de 360 Crédito Imobiliário" → (12, 360).
    static func financing(_ text: String) -> (number: Int, total: Int)? {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard let match = folded.firstMatch(of: #/(?i)parcela\s+(\d{1,3})\s*(?:de|/)\s*(\d{1,3})/#),
              let n = Int(match.1), let total = Int(match.2), total > 1, n <= total else { return nil }
        return (n, total)
    }

    // MARK: - Cards and loans

    /// Each card's latest bill, leaving out cards whose last bill is over 45 days old (cards no longer in use).
    func cards(today: Int = DayKey.from(.now)) -> [CardBillSummary] {
        let byCard = Dictionary(grouping: cardBills.filter { $0.dueDate != nil }, by: { $0.accountId ?? "" })
        return byCard.compactMap { card, bills -> CardBillSummary? in
            guard let latest = bills.max(by: { ($0.dueDate ?? "") < ($1.dueDate ?? "") }), let due = Self.dayKey(latest.dueDate),
                  Self.days(from: due, to: today) <= 45 else { return nil }
            let total = latest.totalAmount ?? 0
            let closing = Self.dayKey(latest.billClosingDate)
            // The bill's own payments, or else the payments the card received since it closed.
            let reported = (latest.payments ?? []).reduce(0) { $0 + abs($1.amount ?? 0) }
            let received = expenses.transactions.filter {
                $0.accountId == card && $0.isCredit && $0.day >= (closing ?? due - 100) && $0.day <= today && Self.isCardPayment($0)
            }.reduce(0) { $0 + abs($1.amount ?? 0) }
            let paid = max(reported, received)
            let status: BillStatus = total <= 0.5 || paid >= total - 1 ? .paid : due < today ? .late : .upcoming
            return CardBillSummary(id: latest.id, card: cardNames[card] ?? String(localized: "Credit card"), closing: closing, due: due,
                                   total: total, minimum: latest.minimumPaymentAmount, paid: paid, status: status,
                                   nextDue: status == .paid ? Self.day(due % 100, inMonth: DayKey.addMonths(due, 1) / 100) : nil)
        }
        .sorted { $0.due < $1.due }
    }

    private static func isCardPayment(_ t: PluggyTransaction) -> Bool {
        let text = ((t.description ?? "") + " " + (t.descriptionRaw ?? "") + " " + (t.category ?? "")).uppercased()
        return ["PAGAMENTO", "PAGTO", "PGTO", "CREDIT CARD PAYMENT"].contains(where: text.contains)
    }

    func loanSummaries(today: Int = DayKey.from(.now)) -> [LoanSummary] {
        loans.map { loan in
            let total = loan.installments?.totalNumberOfInstallments.map { Int($0) }
            let paid = loan.installments?.paidInstallments.map { Int($0) }
                ?? total.flatMap { t in loan.installments?.contractRemainingNumber.map { t - Int($0) } }
            let pastDue = Int(loan.installments?.pastDueInstallments ?? 0)
            var next: Int?
            if let first = Self.dayKey(loan.firstInstallmentDueDate), let paid, let step = Self.months(loan.installmentPeriodicity) {
                var due = Self.day(first % 100, inMonth: DayKey.addMonths(first, paid * step) / 100)
                // A count that lags behind the payments would put the next installment in the past.
                while pastDue == 0, due < today, Self.days(from: due, to: today) > Self.grace {
                    due = Self.day(first % 100, inMonth: DayKey.addMonths(due, step) / 100)
                }
                next = due
            }
            let last = (loan.payments?.releases ?? []).compactMap { r in Self.dayKey(r.paidDate).map { ($0, abs(r.paidAmount ?? 0)) } }.max { $0.0 < $1.0 }
            return LoanSummary(id: loan.id, name: loan.productName?.capitalizedIfShouting ?? loan.type ?? String(localized: "Loan"),
                               paid: paid, total: total, balance: loan.payments?.contractOutstandingBalance, nextDue: next,
                               lastDue: Self.dayKey(loan.dueDate), lastPayment: last.map { (day: $0.0, amount: $0.1) }, pastDue: pastDue)
        }
    }

    /// Months between installments; nil when there's no regular schedule.
    private static func months(_ periodicity: String?) -> Int? {
        switch (periodicity ?? "MENSAL").uppercased() {
        case "MENSAL": 1
        case "BIMESTRAL": 2
        case "TRIMESTRAL": 3
        case "SEMESTRAL": 6
        case "ANUAL": 12
        default: nil
        }
    }

    // MARK: - Upcoming

    /// What falls due in the next `horizon` days, plus anything late, in date order. A financing installment
    /// that matches a loan from the bank takes the loan's due date.
    func upcoming(today: Int = DayKey.from(.now), horizon: Int = 30) -> [UpcomingBill] {
        let loans = loanSummaries(today: today)
        var matched: Set<String> = []
        var list: [UpcomingBill] = []
        for bill in recurring(today: today) {
            var day = bill.nextDue, exact = false
            if let installment = bill.installment, let loan = loans.first(where: { $0.total == installment.total }), let next = loan.nextDue {
                matched.insert(loan.id)
                if bill.status != .paid || next > today { day = next; exact = true }
            }
            list.append(UpcomingBill(id: "r" + bill.key, name: bill.name, symbol: bill.source.symbol, day: day, amount: bill.usual,
                                     exact: exact, late: bill.status == .late, origin: .recurring))
        }
        for card in cards(today: today) {
            if let next = card.nextDue {
                list.append(UpcomingBill(id: "c" + card.id, name: card.card, symbol: "creditcard", day: next, amount: nil,
                                         exact: false, late: false, origin: .card))
            } else {
                list.append(UpcomingBill(id: "c" + card.id, name: card.card, symbol: "creditcard", day: card.due, amount: card.total - card.paid,
                                         exact: true, late: card.status == .late, origin: .card))
            }
        }
        for loan in loans where !matched.contains(loan.id) {
            guard let next = loan.nextDue else { continue }
            list.append(UpcomingBill(id: "l" + loan.id, name: loan.name, symbol: "house", day: next, amount: loan.lastPayment?.amount,
                                     exact: true, late: loan.pastDue > 0, origin: .loan))
        }
        return list.filter { $0.late || Self.days(from: today, to: $0.day) <= horizon }.sorted { ($0.day, $0.name) < ($1.day, $1.name) }
    }

    // MARK: - Dates

    /// "2026-11-06T00:00:00.000Z" → 20261106.
    static func dayKey(_ iso: String?) -> Int? {
        guard let iso, iso.count >= 10 else { return nil }
        return Int(iso.prefix(10).replacingOccurrences(of: "-", with: ""))
    }

    /// The `day` of `month` (yyyymm), or its last day when the month is shorter.
    static func day(_ day: Int, inMonth month: Int) -> Int { month * 100 + min(day, DayKey.daysInMonth(month * 100 + 1)) }

    static func days(from a: Int, to b: Int) -> Int {
        Calendar.current.dateComponents([.day], from: DayKey.date(a), to: DayKey.date(b)).day ?? 0
    }
}
