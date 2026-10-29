import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// What the on-device model is told before every conversation: the rules in Resources/AI/rules.md (edit them
/// there, like an AGENTS.md), then today's date, which it can't know otherwise.
enum AIRules {
    static var instructions: String {
        let rules = Bundle.main.url(forResource: "rules", withExtension: "md", subdirectory: "AI")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            ?? "You are StockBar's assistant. Use the tools for the user's own data and never invent numbers."
        let today = Date.now.formatted(.iso8601.year().month().day())
        let weekday = Date.now.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "en_US")))
        return rules + "\n\nToday is \(weekday), \(today). Amounts are in reais (R$) unless a tool says otherwise."
    }
}

/// The periods the tools accept. The model picks one by name; a specific month comes as YYYY-MM, a year as YYYY.
enum AIPeriod: String, CaseIterable {
    case thisMonth = "this month", lastMonth = "last month", last30Days = "last 30 days"
    case last3Months = "last 3 months", thisYear = "this year", lastYear = "last year"

    /// First and last day (yyyymmdd) and how to name it in a tool's answer.
    static func resolve(_ name: String, month: String?) -> (from: Int, to: Int, label: String) {
        let today = DayKey.from(.now)
        let firstOfMonth = today / 100 * 100 + 1
        func lastDay(_ first: Int) -> Int { first / 100 * 100 + DayKey.daysInMonth(first) }
        // Some models put "2026-09" in period instead of month; take it from either.
        let parts = (month ?? (AIPeriod(rawValue: name.lowercased()) == nil ? name : "")).split(separator: "-").compactMap { Int($0) }
        if parts.count == 2, (2000...2100).contains(parts[0]), (1...12).contains(parts[1]) {
            let (y, m) = (parts[0], parts[1])
            let first = y * 10_000 + m * 100 + 1
            return (first, min(lastDay(first), today), String(format: "%04d-%02d", y, m))
        }
        if parts.count == 1, (2000...2100).contains(parts[0]) {
            return (parts[0] * 10_000 + 101, min(parts[0] * 10_000 + 1231, today), String(parts[0]))
        }
        switch AIPeriod(rawValue: name.lowercased()) ?? .thisMonth {
        case .thisMonth: return (firstOfMonth, today, "this month")
        case .lastMonth:
            let first = DayKey.addMonths(firstOfMonth, -1)
            return (first, lastDay(first), "last month")
        case .last30Days: return (DayKey.from(.now.addingTimeInterval(-29 * 86_400)), today, "the last 30 days")
        case .last3Months: return (DayKey.addMonths(firstOfMonth, -2), today, "the last 3 months")
        case .thisYear: return (today / 10_000 * 10_000 + 101, today, "this year")
        case .lastYear:
            let year = today / 10_000 - 1
            return (year * 10_000 + 101, year * 10_000 + 1231, "last year")
        }
    }

    /// A period as the lookup line under an answer shows it, in the app's language.
    static func label(_ name: String) -> String {
        AIPeriod(rawValue: name.lowercased()).map { String(localized: String.LocalizationValue($0.rawValue)) } ?? name
    }

    /// The months (yyyymm) a range touches.
    static func months(from: Int, to: Int) -> [Int] {
        var months: [Int] = [], first = from / 100 * 100 + 1
        while first / 100 <= to / 100 {
            months.append(first / 100)
            first = DayKey.addMonths(first, 1)
        }
        return months
    }
}

/// A transaction question, as the model filled it in. Everything but the period is optional.
struct TransactionQuery {
    var period: String
    var month: String?
    var text: String?
    var category: String?
    var method: String?
    var account: String?
    /// "out", "in" or "both" (also nil).
    var direction: String?
    var minimumAmount: Double?
    var maximumAmount: Double?
    /// merchant, category, method, account, day, week or month.
    var groupBy: String?
    var largestFirst: Bool?
}

/// The app's data, as short plain text for the model. Its context holds about 4.000 tokens in all (rules, tools,
/// the conversation and these answers), so every answer is a summary with capped lists, never a dump.
/// Amounts go through the usual formatters, so "Hide values" hides them from the model too.
@MainActor
struct AIData {
    let portfolio: PortfolioStore
    let funds: FundStore
    let expenses: ExpenseStore
    let pluggy: PluggyStore

    private static let maxRows = 8

    private func day(_ key: Int) -> String { String(format: "%02d/%02d/%04d", key % 100, key / 100 % 100, key / 10_000) }
    private func fold(_ s: String) -> String { OpenFinanceMatcher.fold(s) }

    /// Only when there's nothing to go by: transactions already downloaded still answer after a bank is disconnected.
    private var noData: String? {
        pluggy.isConfigured && !pluggy.itemIDs.isEmpty || !expenses.expenses.isEmpty ? nil
            : "Open Finance isn't connected in StockBar, so there are no transactions. The user can connect a bank on the Open Finance page."
    }

    // MARK: Expenses

    /// Filters, counts and totals transactions (see `AITools.Query`). Every answer carries the largest
    /// transaction and, over several months, the total per month, so the model rarely needs to ask for them.
    func queryTransactions(_ q: TransactionQuery) async -> String {
        let range = AIPeriod.resolve(q.period, month: q.month)
        let months = AIPeriod.months(from: range.from, to: range.to)
        for m in months { await expenses.loadMonth(m) }
        // Card installments of earlier purchases sit in the months before.
        if let first = months.first { await expenses.loadInstallmentHistory(before: first) }
        if let noData { return noData }

        let needle = fold(q.text ?? "")
        let accountWords = words(q.account, ignoring: ["card", "cartao", "conta", "account", "credit", "credito", "debit", "debito"])
        let categoryIDs = categoryMatches(q.category)
        let method = Self.methods.first { $0.0 == q.method }?.1
        let rows = expenses.expenses.filter { e in
            e.kind != .outside && (range.from...range.to).contains(e.day)
                && (q.direction == "in" ? e.kind == .income : q.direction == "out" ? e.kind == .spending : true)
                && (needle.isEmpty || fold("\(e.store) \(e.detail)").contains(needle))
                && (categoryIDs == nil || categoryIDs!.contains(e.categoryID))
                && (method == nil || e.source == method)
                && (accountWords.isEmpty || accountWords.allSatisfy(fold(e.accountName ?? "").contains))
                && e.amount >= (q.minimumAmount ?? 0) && e.amount <= (q.maximumAmount ?? .infinity)
        }

        var lines = ["Period: \(range.label), \(day(range.from)) to \(day(range.to))."]
        let filters = [q.text.map { "text \"\($0)\"" }, q.category.map { "category \"\($0)\"" }, q.method.map { "method \($0)" },
                       q.account.map { "account \"\($0)\"" }, q.direction.map { "money \($0)" },
                       q.minimumAmount.map { "at least \($0.reais)" }, q.maximumAmount.map { "at most \($0.reais)" }].compactMap { $0 }
        if !filters.isEmpty { lines.append("Filters: " + filters.joined(separator: ", ") + ".") }
        if q.category != nil, categoryIDs?.isEmpty == true {
            lines.append("No category is named like \"\(q.category!)\". Categories: \(expenses.settings.categories.map(\.name).joined(separator: ", ")).")
        }
        guard !rows.isEmpty else {
            lines.append("No transactions found.")
            return lines.joined(separator: "\n")
        }

        let out = rows.filter { $0.kind == .spending }, into = rows.filter { $0.kind == .income }
        for (title, group) in [("Money out", out), ("Money in", into)] where !group.isEmpty {
            let largest = group.max { $0.amount < $1.amount }!
            lines.append("\(title): \(group.count) transactions, total \(total(group).reais). Largest: \(row(largest)).")
        }
        // Totals go over the money that left, unless the question is about money in.
        let measured = q.direction == "in" || out.isEmpty ? into : out
        if let groupBy = q.groupBy {
            lines.append("Per \(groupBy):")
            lines += groups(measured, by: groupBy).prefix(12).map { "- \($0.name): \($0.total.reais) in \($0.count)×" }
        } else {
            if months.count > 1 {
                lines.append("Per month: " + groups(measured, by: "month").map { "\($0.name) \($0.total.reais) (\($0.count)×)" }.joined(separator: "; ") + ".")
            }
            let listed = q.largestFirst == true ? rows.sorted { $0.amount > $1.amount } : rows.sorted { $0.day > $1.day }
            lines.append(rows.count > Self.maxRows ? (q.largestFirst == true ? "Largest \(Self.maxRows):" : "Latest \(Self.maxRows):") : "All of them:")
            lines += listed.prefix(Self.maxRows).map { "- " + row($0) }
        }
        return lines.joined(separator: "\n")
    }

    /// What the model can ask for, as it says it, and how StockBar tells them apart.
    nonisolated static let methods: [(String, Expense.Source)] = [("pix", .pix), ("credit card", .creditCard), ("debit card", .debitCard),
                                                       ("boleto", .boleto), ("transfer", .transfer), ("automatic debit", .autoDebit)]

    private func total(_ rows: [Expense]) -> Double { rows.reduce(0) { $0 + $1.amount } }

    private func row(_ e: Expense) -> String {
        var detail = [expenses.category(e.categoryID)?.name, e.source.label, e.accountName, e.installment.map { "installment \($0)" }].compactMap { $0 }
        if e.kind == .income { detail.insert("money in", at: 0) }
        return "\(day(e.day)) \(e.store) \(e.amount.reais) (\(detail.joined(separator: ", ")))"
    }

    /// Totals per group: by size for names, in date order for days, weeks and months.
    private func groups(_ rows: [Expense], by key: String) -> [(name: String, total: Double, count: Int)] {
        let calendar = Calendar(identifier: .iso8601)
        func name(_ e: Expense) -> String {
            switch key {
            case "category": expenses.category(e.categoryID)?.name ?? "Uncategorized"
            case "method": e.source.label
            case "account": e.accountName ?? "Unknown account"
            case "day": day(e.day)
            case "week": "week of " + day(DayKey.from(calendar.dateInterval(of: .weekOfYear, for: DayKey.date(e.day))?.start ?? DayKey.date(e.day)))
            case "month": String(format: "%04d-%02d", e.day / 10_000, e.day / 100 % 100)
            default: e.store
            }
        }
        func sortKey(_ e: Expense) -> Int { key == "week" ? DayKey.from(calendar.dateInterval(of: .weekOfYear, for: DayKey.date(e.day))?.start ?? .now) : e.day }
        let grouped = Dictionary(grouping: rows, by: name)
        let result = grouped.map { (name: $0.key, total: total($0.value), count: $0.value.count, first: $0.value.map(sortKey).min() ?? 0) }
        let sorted = ["day", "week", "month"].contains(key) ? result.sorted { $0.first < $1.first } : result.sorted { $0.total > $1.total }
        return sorted.map { ($0.name, $0.total, $0.count) }
    }

    /// "BANCO BMG S.A" → "BANCO BMG": fewer tokens for the model to read, same meaning.
    private func shortIssuer(_ name: String) -> String {
        name.replacingOccurrences(of: #"[\s-]*(S[./]?A\.?|S/A|LTDA\.?|BANCO MULTIPLO.*|BANCO MÚLTIPLO.*)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespaces)
    }

    /// Folded words of a name, without the generic ones ("Nubank card" → ["nubank"]).
    private func words(_ text: String?, ignoring generic: Set<String>) -> [String] {
        (text ?? "").split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { fold(String($0)) }.filter { !$0.isEmpty && !generic.contains($0) }
    }

    func spendingSummary(period: String, month: String?) async -> String {
        let range = AIPeriod.resolve(period, month: month)
        let months = AIPeriod.months(from: range.from, to: range.to)
        for m in months { await expenses.loadMonth(m) }
        // Card installments of earlier purchases sit in the months before.
        if let first = months.first { await expenses.loadInstallmentHistory(before: first) }
        if let noData { return noData }
        let rows = expenses.expenses.filter { (range.from...range.to).contains($0.day) }
        let spending = rows.filter { $0.kind == .spending }
        let income = rows.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }

        var lines = ["Spending \(day(range.from)) to \(day(range.to)) (\(range.label)): \(spending.reduce(0) { $0 + $1.amount }.reais) in \(spending.count) transactions. Money in: \(income.reais)."]
        let byCategory = Dictionary(grouping: spending) { $0.categoryID }
            .map { (name: expenses.category($0.key)?.name ?? "Uncategorized", limit: expenses.category($0.key)?.limit, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        if !byCategory.isEmpty {
            lines.append("By category:")
            for c in byCategory.prefix(10) {
                let limit = c.limit.map { " (monthly limit \($0.reais))" } ?? ""
                lines.append("- \(c.name): \(c.total.reais)\(limit)")
            }
        }
        let byStore = Dictionary(grouping: spending) { $0.merchantKey }
            .map { (name: $0.value[0].store, count: $0.value.count, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        if !byStore.isEmpty {
            lines.append("Top places:")
            for s in byStore.prefix(5) { lines.append("- \(s.name): \(s.total.reais) in \(s.count)×") }
        }
        return lines.joined(separator: "\n")
    }

    /// Categories whose name contains `name`; nil when there's no filter.
    private func categoryMatches(_ name: String?) -> Set<UUID?>? {
        guard let name, !fold(name).isEmpty else { return nil }
        return Set(expenses.settings.categories.filter { fold($0.name).contains(fold(name)) || fold(name).contains(fold($0.name)) }.map { Optional($0.id) })
    }

    // MARK: Portfolio

    func portfolioOverview() -> String {
        let pricer = portfolio.bondPricer
        let bonds = portfolio.bonds.reduce(0) { $0 + pricer.value($1).gross }
        let fundsValue = funds.holdings.reduce(0) { $0 + (funds.value($1)?.gross ?? 0) }
        let total = portfolio.totalValue + bonds + fundsValue
        var lines = ["Portfolio: \(total.reais). Stocks, FIIs and ETFs \(portfolio.totalValue.reais) (\(portfolio.holdings.count) tickers), fixed income \(bonds.reais) (\(portfolio.bonds.count) bonds), funds \(fundsValue.reais) (\(funds.holdings.count))."]
        if let change = portfolio.dayChange { lines.append("Stocks today: \(change.signedPercent).") }
        let top = portfolio.holdings.prefix(5).map { "\($0.ticker) \($0.weight.percent)" }
        if !top.isEmpty { lines.append("Largest stock positions (share of stocks): \(top.joined(separator: ", ")).") }

        let today = DayKey.from(.now)
        let paid = portfolio.dividends.filter { ($0.paymentDay ?? $0.recordDay) / 10_000 == today / 10_000 && ($0.paymentDay ?? $0.recordDay) <= today }
        lines.append("Dividends and JCP this year so far: \(paid.reduce(0) { $0 + $1.amount }.reais).")
        let upcoming = portfolio.dividends.filter { ($0.paymentDay ?? 0) > today }.sorted { $0.paymentDay! < $1.paymentDay! }
        if !upcoming.isEmpty {
            lines.append("Upcoming payments: " + upcoming.prefix(5).map { "\($0.ticker) \($0.amount.reais) on \(day($0.paymentDay!))" }.joined(separator: "; ") + ".")
        }
        return lines.joined(separator: "\n")
    }

    func holdings(kind: String, indexer: String? = nil) -> String {
        switch kind {
        case "bonds":
            let pricer = portfolio.bondPricer
            let today = DayKey.from(.now)
            // Earned this month: today's gross over the last day of last month's (or the amount invested, if newer).
            let monthStart = DayKey.from(DayKey.date(today / 100 * 100 + 1).addingTimeInterval(-86_400))
            func earnedThisMonth(_ b: Bond) -> Double {
                let now = pricer.value(b).gross
                return now - (b.issueDay > monthStart ? b.invested : pricer.value(b, on: monthStart).gross)
            }
            func family(_ b: Bond) -> String {
                switch b.indexer {
                case .fixed: "fixed"
                case .cdi, .cdiPlus: "cdi"
                case .ipca: "ipca"
                }
            }
            let names = ["fixed": "Fixed rate (prefixado)", "cdi": "CDI (pós-fixado)", "ipca": "IPCA+"]
            let bonds = portfolio.bonds.filter { indexer == nil || family($0) == indexer }
            guard !bonds.isEmpty else { return indexer == nil ? "No fixed income in StockBar." : "No \(names[indexer!] ?? indexer!) bonds in StockBar." }
            var lines = ["Fixed income, gross values (before income tax). \"This month\" is what each bond earned since \(day(monthStart))."]
            for (key, group) in Dictionary(grouping: bonds, by: family).sorted(by: { $0.key < $1.key }) {
                let value = group.reduce(0) { $0 + pricer.value($1).gross }
                let month = group.reduce(0) { $0 + earnedThisMonth($1) }
                let gain = group.reduce(0) { $0 + pricer.value($1).gain }
                lines.append("\(names[key]!) total: \(group.count) bonds, \(value.reais), this month +\(month.reais), since purchase +\(gain.reais).")
            }
            let rows = bonds.map { ($0, pricer.value($0)) }.sorted { $0.1.gross > $1.1.gross }
            lines += rows.prefix(12).map { b, v in
                "- \(b.kind.rawValue) \(shortIssuer(b.issuer)), \(b.indexer.describe(b.rate)), matures \(day(b.maturityDay)): \(v.gross.reais), this month +\(earnedThisMonth(b).reais)"
            }
            return lines.joined(separator: "\n")
        case "funds":
            guard !funds.holdings.isEmpty else { return "No funds in StockBar." }
            return (["Funds (\(funds.holdings.count)):"] + funds.holdings.prefix(12).map { f in
                let v = funds.value(f)
                let ytd = v?.ytd.map { ", \($0.signedPercent) this year" } ?? ""
                return "- \(f.name): \(v?.gross.reais ?? "no price yet")\(ytd)"
            }).joined(separator: "\n")
        default:
            guard !portfolio.holdings.isEmpty else { return "No stocks in StockBar." }
            return (["Stocks, FIIs and ETFs (\(portfolio.holdings.count)), largest first:"] + portfolio.holdings.prefix(15).map { h in
                var parts = ["\(h.quantity.quantity) shares", "value \((h.weight * portfolio.totalValue).reais)"]
                if let live = portfolio.livePrice(h.ticker) {
                    parts.append("price \(live.price(for: h.ticker))")
                    if let average = h.averagePrice, average > 0 {
                        parts.append("average price \(average.price(for: h.ticker))")
                        parts.append("gain \((live / average - 1).signedPercent)")
                    }
                }
                return "- \(h.ticker): " + parts.joined(separator: ", ")
            }).joined(separator: "\n")
        }
    }
}

#if canImport(FoundationModels)
/// The model's read-only window into the app. None of them change anything: text inside the data (a PIX
/// description, a merchant name) can try to steer the model, and read-only tools keep that harmless.
@available(macOS 26, *)
protocol StockBarTool: Tool where Output == String {
    var data: AIData { get }
    var note: @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void { get }
}

@available(macOS 26, *)
extension StockBarTool {
    /// Runs the call through `AIToolbox`, the same code the cloud models use, and reports it to the chat.
    @MainActor
    func answer(_ name: String, _ arguments: [String: Any]) async throws -> String {
        let start = Date.now
        let (label, output) = await AIToolbox.run(name, arguments: arguments, data: data)
        note(label, output, Date.now.timeIntervalSince(start))
        return output
    }
}

@available(macOS 26, *)
enum AITools {
    static func all(_ data: AIData, note: @escaping @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void) -> [any Tool] {
        [Query(data: data, note: note), Spending(data: data, note: note), Overview(data: data, note: note), Holdings(data: data, note: note)]
    }

    /// The query tool: its arguments are the schema of a transaction, as far as the model needs to know it.
    struct Query: StockBarTool {
        let data: AIData
        let note: @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void
        let name = "queryTransactions"
        let description = AIToolbox.queryDescription

        @Generable
        struct Arguments {
            @Guide(description: "The period", .anyOf(AIPeriod.allCases.map(\.rawValue)))
            var period: String
            @Guide(description: "A month the user names, as YYYY-MM, or a year as YYYY. It replaces period.")
            var month: String?
            @Guide(description: "Merchant or person the money went to or came from, like 'uber', 'ifood' or 'João'.")
            var text: String?
            @Guide(description: "Expense category name, like 'Transport'.")
            var category: String?
            @Guide(description: "How the money moved: pix; credit card ('cartão de crédito', 'no crédito'); debit card ('débito', 'no débito'); boleto; transfer ('TED', 'transferência'); automatic debit ('débito automático')", .anyOf(AIData.methods.map(\.0)))
            var method: String?
            @Guide(description: "Account or card name, like 'Nubank' or 'XP'.")
            var account: String?
            @Guide(description: "Money out (spending), in (income) or both", .anyOf(["out", "in", "both"]))
            var direction: String?
            @Guide(description: "Only transactions of this many reais or more: 'over', 'above', 'more than', 'acima de'.")
            var amountAbove: Double?
            @Guide(description: "Only transactions of this many reais or less: 'under', 'below', 'up to', 'abaixo de'.")
            var amountBelow: Double?
            @Guide(description: "Only when the user asks for totals per something ('per week', 'by category', 'por mês')", .anyOf(["merchant", "category", "method", "account", "day", "week", "month"]))
            var groupBy: String?
            @Guide(description: "List the largest first instead of the newest")
            var largestFirst: Bool?
        }

        func call(arguments a: Arguments) async throws -> String {
            var dict: [String: Any] = ["period": a.period]
            dict["month"] = a.month; dict["text"] = a.text; dict["category"] = a.category; dict["method"] = a.method
            dict["account"] = a.account; dict["direction"] = a.direction; dict["amountAbove"] = a.amountAbove
            dict["amountBelow"] = a.amountBelow; dict["groupBy"] = a.groupBy; dict["largestFirst"] = a.largestFirst
            return try await answer(name, dict)
        }
    }

    struct Spending: StockBarTool {
        let data: AIData
        let note: @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void
        let name = "spendingSummary"
        let description = AIToolbox.spendingDescription

        @Generable
        struct Arguments {
            @Guide(description: "The period", .anyOf(AIPeriod.allCases.map(\.rawValue)))
            var period: String
            @Guide(description: "A month the user names, as YYYY-MM, or a year as YYYY. It replaces period.")
            var month: String?
        }

        func call(arguments: Arguments) async throws -> String {
            var dict: [String: Any] = ["period": arguments.period]
            dict["month"] = arguments.month
            return try await answer(name, dict)
        }
    }

    struct Overview: StockBarTool {
        let data: AIData
        let note: @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void
        let name = "portfolioOverview"
        let description = AIToolbox.overviewDescription

        @Generable
        struct Arguments {}

        func call(arguments: Arguments) async throws -> String { try await answer(name, [:]) }
    }

    struct Holdings: StockBarTool {
        let data: AIData
        let note: @MainActor @Sendable (_ label: String, _ output: String, _ seconds: Double) -> Void
        let name = "listHoldings"
        let description = AIToolbox.holdingsDescription

        @Generable
        struct Arguments {
            @Guide(description: "Which positions", .anyOf(["stocks", "bonds", "funds"]))
            var kind: String
            @Guide(description: "Bonds only. fixed: prefixado, pré-fixado, taxa fixa. cdi: pós-fixado, % do CDI. ipca: IPCA+, inflação.", .anyOf(["fixed", "cdi", "ipca"]))
            var indexer: String?
        }

        func call(arguments: Arguments) async throws -> String {
            var dict: [String: Any] = ["kind": arguments.kind]
            dict["indexer"] = arguments.indexer
            return try await answer(name, dict)
        }
    }
}
#endif
