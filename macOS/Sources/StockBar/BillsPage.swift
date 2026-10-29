import SwiftUI

/// What's due and when: recurring bills found in the bank accounts, card bills and loans from Open Finance.
struct BillsPage: View {
    @Environment(ExpenseStore.self) private var expenses
    @Environment(BillStore.self) private var bills
    @State private var showHidden = false

    private var today: Int { DayKey.from(.now) }

    var body: some View {
        let recurring = bills.recurring(today: today)
        let upcoming = bills.upcoming(today: today)
        let cards = bills.cards(today: today)
        let loans = bills.loanSummaries(today: today)
        ScrollView {
            VStack(alignment: .leading, spacing: PageLayout.spacing) {
                header
                tiles(recurring: recurring, upcoming: upcoming, cards: cards)
                upcomingList(upcoming)
                recurringTable(recurring)
                if !cards.isEmpty { cardList(cards) }
                if !loans.isEmpty { loanList(loans) }
                shared(loans: loans)
            }
            .padding(PageLayout.padding)
        }
        // This month and the three before it: what the recurring bills are found in.
        .task {
            let month = today / 100
            await expenses.loadMonth(month)
            for back in 1...3 { await expenses.loadMonth(DayKey.addMonths(month * 100 + 1, -back) / 100) }
        }
        .task { await bills.load() }
    }

    // MARK: - Header and tiles

    private var header: some View {
        HStack(spacing: 12) {
            Text("Bills").font(.title2.weight(.semibold))
            Spacer()
            if let error = bills.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).lineLimit(2)
            } else if let last = bills.fetchedAt {
                Text("card bills and loans updated \(last.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
            if bills.isLoading || expenses.isLoading { ProgressView().controlSize(.small) }
            Button { Task { await bills.refresh(); await expenses.sync(month: today / 100) } } label: {
                Label("Sync", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(bills.isLoading)
        }
        .frame(height: 28)
    }

    private func tiles(recurring: [RecurringBill], upcoming: [UpcomingBill], cards: [CardBillSummary]) -> some View {
        let due = upcoming.filter { !$0.late }
        let late = upcoming.filter(\.late)
        let paid = recurring.flatMap(\.paidThisMonth).reduce(0) { $0 + $1.amount }
            + cards.filter { $0.status == .paid && $0.due / 100 == today / 100 }.reduce(0) { $0 + $1.total }
        return TileRow {
            SummaryTile(title: "Due in the next 30 days", value: due.reduce(0) { $0 + ($1.amount ?? 0) }.reais,
                        detail: "\(due.count) bills")
            SummaryTile(title: "Late", value: "\(late.count)",
                        detail: late.isEmpty ? "nothing late" : "\(late.reduce(0) { $0 + ($1.amount ?? 0) }.reais)",
                        tint: late.isEmpty ? nil : .red)
            SummaryTile(title: "Paid this month", value: paid.reais)
            SummaryTile(title: "Recurring bills", value: "\(recurring.count)",
                        detail: "\(recurring.filter { $0.status == .paid }.count) paid this month")
        }
    }

    // MARK: - Upcoming

    private func upcomingList(_ list: [UpcomingBill]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Upcoming", detail: "Late bills first, then the next 30 days")
            if list.isEmpty {
                Text(expenses.isLoading ? "Loading transactions…" : "Nothing due in the next 30 days.")
                    .foregroundStyle(.secondary).padding(14)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Divider().padding(.horizontal, 14) }
                HStack(spacing: 12) {
                    DateBadge(day: item.day, late: item.late)
                    Image(systemName: item.symbol).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1)
                        Text(relative(item.day, late: item.late)).font(.caption).foregroundStyle(item.late ? .red : .secondary)
                    }
                    Spacer()
                    Text(item.exact ? "From the bank" : "Estimated")
                        .font(.caption2).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .help(item.exact ? "Due date reported by the bank" : "Due day estimated from when it was paid in the last months")
                    Text(item.amount.map { (item.exact && item.origin == .card ? "" : "≈ ") + $0.reais } ?? String(localized: "when it closes"))
                        .foregroundStyle(item.amount == nil ? .secondary : .primary)
                        .monospacedDigit()
                        .frame(width: 120, alignment: .trailing)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .card()
    }

    private func relative(_ day: Int, late: Bool) -> String {
        let n = BillStore.days(from: today, to: day)
        if late { return String(localized: "not seen yet, expected \(DayKey.date(day).formatted(.dateTime.day().month(.wide)))") }
        switch n {
        case ..<0: return String(localized: "\(-n) days ago")
        case 0: return String(localized: "today")
        case 1: return String(localized: "tomorrow")
        default: return String(localized: "in \(n) days")
        }
    }

    // MARK: - Recurring bills

    private enum Width { static let source: CGFloat = 130, due: CGFloat = 110, amount: CGFloat = 110, last: CGFloat = 150, status: CGFloat = 150, menu: CGFloat = 28 }

    private func recurringTable(_ list: [RecurringBill]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Recurring bills", detail: "Boletos, automatic debits and financing paid in at least 2 of the last 3 months")
            HStack(spacing: 10) {
                Text("Bill").frame(maxWidth: .infinity, alignment: .leading)
                Text("Source").frame(width: Width.source, alignment: .leading)
                Text("Due").frame(width: Width.due, alignment: .leading)
                Text("Usually").frame(width: Width.amount, alignment: .trailing)
                Text("Last paid").frame(width: Width.last, alignment: .leading)
                Text("This month").frame(width: Width.status, alignment: .leading)
                Text("").frame(width: Width.menu)
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            if list.isEmpty {
                Text(expenses.isLoading ? "Loading transactions…" : "No recurring bills found yet.")
                    .foregroundStyle(.secondary).padding(14)
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, bill in
                if i > 0 { Divider().padding(.horizontal, 14) }
                recurringRow(bill)
            }
            let hidden = bills.hidden
            if !hidden.isEmpty {
                Divider()
                DisclosureGroup(isExpanded: $showHidden) {
                    ForEach(hidden, id: \.key) { h in
                        HStack {
                            Text(h.name).foregroundStyle(.secondary)
                            Spacer()
                            Button("Track again") { update(h.key) { $0.tracked = nil } }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    Text("Not tracked (\(hidden.count))").font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .card()
    }

    private func recurringRow(_ bill: RecurringBill) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(bill.name).lineLimit(1)
                if let i = bill.installment {
                    Text("\(i.number)/\(i.total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                        .help("Last installment paid")
                }
                if bill.trackedByHand {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary).help("Tracked by you")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Label(bill.source.label, systemImage: bill.source.symbol).lineLimit(1).foregroundStyle(.secondary)
                .frame(width: Width.source, alignment: .leading)
            dueMenu(bill).frame(width: Width.due, alignment: .leading)
            Text("≈ " + bill.usual.reais).frame(width: Width.amount, alignment: .trailing)
            Text(bill.lastPayment.map { "\(DayKey.date($0.day).formatted(.dateTime.day().month(.abbreviated))) · \($0.amount.reais)" } ?? "—")
                .lineLimit(1).foregroundStyle(.secondary)
                .frame(width: Width.last, alignment: .leading)
            StatusChip(bill: bill, today: today).frame(width: Width.status, alignment: .leading)
            Menu {
                let month = today / 100
                if bill.paidThisMonth.isEmpty {
                    if bill.paidByHand {
                        Button("Not paid this month") { update(bill.key) { $0.paidByHand?.remove(month) } }
                    } else {
                        Button("Mark as paid this month") { update(bill.key) { $0.paidByHand = ($0.paidByHand ?? []).union([month]) } }
                    }
                }
                Divider()
                Button("Stop tracking") { update(bill.key) { $0.tracked = false; $0.paidByHand = nil } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .frame(width: Width.menu)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    private func dueMenu(_ bill: RecurringBill) -> some View {
        Menu {
            Button("Estimate from payments") { update(bill.key) { $0.dueDay = nil } }.disabled(!bill.dueDaySet)
            Divider()
            Picker("Due day", selection: Binding(get: { bill.dueDaySet ? bill.dueDay : 0 }, set: { d in update(bill.key) { $0.dueDay = d } })) {
                ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(bill.dueDaySet ? "Day \(bill.dueDay)" : "≈ day \(bill.dueDay)")
                .foregroundStyle(bill.dueDaySet ? .primary : .secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(bill.dueDaySet ? "Due day set by you" : "Estimated from the last payments; pick the real day if you know it")
    }

    private func update(_ key: String, _ change: (inout BillChoice) -> Void) {
        var choice = expenses.billChoice(key)
        change(&choice)
        if choice.paidByHand?.isEmpty == true { choice.paidByHand = nil }
        expenses.setBillChoice(choice, for: key)
    }

    // MARK: - Cards and loans

    private func cardList(_ cards: [CardBillSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Credit card bills", detail: "The latest closed bill of each card")
            ForEach(Array(cards.enumerated()), id: \.element.id) { i, c in
                if i > 0 { Divider().padding(.horizontal, 14) }
                HStack(spacing: 12) {
                    Image(systemName: "creditcard").foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.card).lineLimit(1)
                        Text(c.closing.map { "closed \(DayKey.date($0).formatted(.dateTime.day().month(.abbreviated)))" } ?? "")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("due \(DayKey.date(c.due).formatted(.dateTime.day().month(.abbreviated).year()))")
                        if let minimum = c.minimum, c.status != .paid {
                            Text("minimum \(minimum.reais)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(c.total.reais).monospacedDigit().frame(width: 120, alignment: .trailing)
                    chip(c.status == .paid ? String(localized: "Paid") : c.status == .late ? String(localized: "Overdue") : String(localized: "Open"),
                         c.status)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .card()
    }

    private func loanList(_ loans: [LoanSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Loans & financing", detail: "Contracts your banks share through Open Finance")
            ForEach(Array(loans.enumerated()), id: \.element.id) { i, l in
                if i > 0 { Divider().padding(.horizontal, 14) }
                HStack(spacing: 12) {
                    Image(systemName: "house").foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l.name).lineLimit(1)
                        if let paid = l.paid, let total = l.total, total > 0 {
                            ProgressView(value: Double(paid), total: Double(total)).frame(width: 220)
                            Text("\(paid) of \(total) installments paid").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let next = l.nextDue {
                            Text("next \(DayKey.date(next).formatted(.dateTime.day().month(.abbreviated).year()))")
                        }
                        if let last = l.lastDue {
                            Text("ends \(DayKey.date(last).formatted(.dateTime.month(.abbreviated).year()))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(l.balance?.reais ?? "—").monospacedDigit()
                        Text("outstanding").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 140, alignment: .trailing)
                }
                .font(.callout)
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .card()
    }

    /// What the banks share, so a missing section has a reason.
    private func shared(loans: [LoanSummary]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if bills.fetchedAt != nil {
                Text("Card bills: \(bills.cardsWithBills) of \(bills.cardsAsked) cards. Loans: \(loans.count).")
            }
            ForEach(bills.failures, id: \.self) { Text($0) }
            Text("Boletos and automatic debits only carry the day they were paid, so their due day is estimated from the last payments; set the real one in the Due column. To track another payment, right-click it in Expenses.")
        }
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Pieces

    private func sectionTitle(_ title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    private func chip(_ text: String, _ status: BillStatus) -> some View {
        let color: Color = switch status { case .paid: .green; case .late: .red; case .upcoming: .secondary }
        return Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// A calendar-leaf date: the day large, the month small.
private struct DateBadge: View {
    let day: Int
    let late: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(DayKey.date(day).formatted(.dateTime.month(.abbreviated)).uppercased())
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(late ? .red : .secondary)
            Text("\(day % 100)").font(.title3.weight(.semibold).monospacedDigit())
        }
        .frame(width: 40, height: 40)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// This month's state of a recurring bill.
private struct StatusChip: View {
    let bill: RecurringBill
    let today: Int

    var body: some View {
        let (text, color, help): (String, Color, String) = switch bill.status {
        case .paid where bill.paidThisMonth.isEmpty:
            (String(localized: "Marked paid"), .green, String(localized: "Marked as paid by you"))
        case .paid:
            (String(localized: "Paid \(DayKey.date(bill.paidThisMonth.last!.day).formatted(.dateTime.day().month(.abbreviated)))"), .green,
             bill.paidThisMonth.map { $0.amount.reais }.joined(separator: " + "))
        case .late:
            (String(localized: "Not seen yet"), .red,
             String(localized: "Usually paid around day \(bill.dueDay). If you paid it from an account that isn't connected, mark it as paid in the menu."))
        case .upcoming:
            (String(localized: "Due \(DayKey.date(bill.nextDue).formatted(.dateTime.day().month(.abbreviated)))"), .secondary, "")
        }
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .help(help)
    }
}
