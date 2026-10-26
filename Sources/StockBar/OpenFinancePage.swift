import SwiftUI

enum OpenFinanceSort: String {
    case name, quantity, value, status
}

/// A position picked for import, with what the user still fills in on its row.
private struct StagedImport {
    enum Item {
        case stock(ticker: String, quantity: Double)
        /// A stock StockBar already holds, getting the average price typed on its row.
        case stockAverage(ticker: String)
        case bond(Bond)
        case fund(FundHolding)
    }
    var item: Item
    /// Average price for a stock (optional), CNPJ for a fund (required).
    var input: String
    /// Why the last import attempt left it behind.
    var failure: String?

    var isValid: Bool {
        switch item {
        case .stock: input.trimmingCharacters(in: .whitespaces).isEmpty || (parseNumber(input) ?? 0) > 0
        case .stockAverage: (parseNumber(input) ?? 0) > 0
        case .bond: true
        case .fund: input.filter(\.isNumber).count == 14
        }
    }
}

/// What Open Finance (via Pluggy) reports, side by side with what StockBar tracks. Positions StockBar doesn't
/// have can be picked (they turn blue) and imported together from the bar at the bottom.
struct OpenFinancePage: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @AppStorage("mainSection") private var section: MainSection = .stocks
    @State private var showClosed = false
    @State private var editor: Editor?
    /// Picked for import, by investment id.
    @State private var staged: [String: StagedImport] = [:]
    @State private var importing = false
    @State private var importResult: String?
    @AppStorage("openFinanceSort") private var sort: OpenFinanceSort = .value
    @AppStorage("openFinanceSortAscending") private var ascending = false

    /// Positions already sold come back with zero quantity and balance; they're hidden unless asked for.
    private func isClosed(_ inv: PluggyInvestment) -> Bool { (inv.balance ?? 0) == 0 && (inv.quantity ?? 0) == 0 }
    private var openInvestments: [PluggyInvestment] { pluggy.investments.filter { !isClosed($0) } }

    /// The same account can come back more than once (same type, number and name); keep the one with a balance.
    private var accounts: [PluggyAccount] {
        var seen: [String: PluggyAccount] = [:], order: [String] = []
        for a in pluggy.accounts {
            let key = [a.type, a.subtype, a.number, a.marketingName ?? a.name].map { $0 ?? "" }.joined(separator: "|")
            if let kept = seen[key] {
                if abs(a.balance ?? 0) > abs(kept.balance ?? 0) { seen[key] = a }
            } else {
                seen[key] = a
                order.append(key)
            }
        }
        return order.compactMap { seen[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Open Finance").font(.title2.weight(.semibold))
                    if let last = pluggy.lastSync {
                        Text("synced \(last.formatted(date: .omitted, time: .shortened))").foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pluggy.isSyncing { ProgressView().controlSize(.small) }
                    Button { Task { await pluggy.sync() } } label: { Label("Sync", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(!pluggy.isConfigured || pluggy.itemIDs.isEmpty || pluggy.isSyncing)
                }
                if let error = pluggy.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !pluggy.isConfigured || pluggy.itemIDs.isEmpty {
                    setupHint
                } else {
                    connections
                    if !accounts.isEmpty { accountsCard }
                    investmentsCard
                }
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            if !staged.isEmpty || importResult != nil { importBar }
        }
        .sheet(item: $editor) { e in
            switch e {
            case let .stock(ticker, quantity, price): StockForm(ticker: ticker, quantity: quantity, averagePrice: price).environment(store)
            case .bond(let b): BondForm(bond: b).environment(store)
            case .fund(let f): FundHoldingForm(holding: f).environment(funds)
            }
        }
        .task { if pluggy.isConfigured, !pluggy.itemIDs.isEmpty, pluggy.lastSync == nil { await pluggy.sync() } }
    }

    private var setupHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pluggy.isConfigured ? "Add an item ID to sync" : "Connect your Pluggy account").font(.headline)
            Text("1. In Settings → Open Finance, enter the client ID and secret of your Meu Pluggy application.\n2. In the Pluggy dashboard, connect the “Meu Pluggy” connector to that application and copy the item ID it creates (Meu Pluggy can't list items through the API).\n3. Add the item ID in Settings and sync.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Open Settings") { section = .settings }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(pluggy.items) { item in
                HStack(spacing: 10) {
                    Circle().fill(item.status == "UPDATED" ? Color.green : item.status == "UPDATING" ? .yellow : .orange).frame(width: 8, height: 8)
                    Text(pluggy.institutions(of: item.id) ?? item.connector?.name ?? "Item").fontWeight(.semibold)
                    Text(item.status ?? "").font(.caption).foregroundStyle(.secondary)
                    if let message = item.error?.message { Text(message).font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    if let updated = item.lastUpdatedAt ?? item.updatedAt { Text("updated \(isoDay(updated))").font(.caption).foregroundStyle(.secondary) }
                    Text(Privacy.isOn ? "•••" : item.id).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
                }
            }
        }
        .padding(14)
        .card()
    }

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Accounts").font(.headline).padding(14)
            ForEach(accounts) { a in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.marketingName ?? a.name ?? "Account")
                        Text([a.type, a.subtype, a.number.map { Privacy.isOn ? "•••" : $0 }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(a.balance.map(\.reais) ?? "—").monospacedDigit().fontWeight(.medium)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                Divider().padding(.horizontal, 14)
            }
        }
        .card()
    }

    // MARK: - Investments vs StockBar

    private var investmentsCard: some View {
        let shown = showClosed ? pluggy.investments : openInvestments
        let closed = pluggy.investments.count - openInvestments.count
        let groups = Dictionary(grouping: shown) { $0.type ?? "OTHER" }
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Investments").font(.headline)
                Text("\(openInvestments.count) positions · \(openInvestments.reduce(0) { $0 + (gross($1) ?? 0) }.reais) gross")
                    .foregroundStyle(.secondary)
                Spacer()
                if closed > 0 {
                    Toggle("Show \(closed) closed", isOn: $showClosed).toggleStyle(.checkbox).foregroundStyle(.secondary)
                }
            }
            if pluggy.investments.isEmpty {
                Text(pluggy.isSyncing ? "Loading…" : "No investments returned.").foregroundStyle(.secondary)
            }
            ForEach(groups.keys.sorted(), id: \.self) { type in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Text(typeLabel(type)).font(.subheadline.weight(.semibold))
                        if type == "FIXED_INCOME" || type == "MUTUAL_FUND" { selectAll(groups[type]!) }
                    }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                    if isStockGroup(type) {
                        HStack(spacing: 12) {
                            column("Stock", .name, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                            column("Shares", .quantity).frame(width: StockColumn.shares, alignment: .trailing)
                            Text("Avg price").frame(width: StockColumn.average, alignment: .center)
                            Text("Price").frame(width: StockColumn.price, alignment: .trailing)
                            column("Value", .value).frame(width: StockColumn.value, alignment: .trailing)
                            column("StockBar", .status, ascendingFirst: true).frame(width: 230, alignment: .leading)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 4)
                    } else {
                        HStack(alignment: .top, spacing: 12) {
                            column("Name", .name, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                            column("Quantity", .quantity).frame(width: 150, alignment: .trailing)
                            column("Value", .value).frame(width: 150, alignment: .trailing)
                            column("StockBar", .status, ascendingFirst: true).frame(width: 230, alignment: .leading)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.bottom, 4)
                    }
                    Divider()
                    ForEach(sorted(groups[type]!)) { inv in
                        if isStockGroup(type) { stockRow(inv) } else { investmentRow(inv) }
                        Divider().padding(.horizontal, 14)
                    }
                }
                .card()
            }
        }
    }

    private func isStockGroup(_ type: String) -> Bool { type == "EQUITY" || type == "ETF" }

    private enum StockColumn {
        static let shares: CGFloat = 90, average: CGFloat = 120, price: CGFloat = 100, value: CGFloat = 130
    }

    /// Stocks laid out like the Holdings table, with the average price typed right on the row.
    private func stockRow(_ inv: PluggyInvestment) -> some View {
        let closed = isClosed(inv)
        let match = closed ? nil : compare(inv)
        let ticker = normalizedCode(inv).isEmpty ? (inv.name ?? "") : normalizedCode(inv)
        let brazil = Locale(identifier: "pt_BR")
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ticker).fontWeight(.semibold)
                Text(store.holdings.first { $0.ticker == ticker }?.name ?? [inv.subtype, inv.name == ticker ? nil : inv.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(inv.quantity.map(\.shares) ?? "—")
                .frame(width: StockColumn.shares, alignment: .trailing)
            Group {
                if closed { Text("—").foregroundStyle(.tertiary) } else { averageField(inv, match: match) }
            }
            .frame(width: StockColumn.average, alignment: .center)
            Text(inv.value.map { $0.formatted(.currency(code: inv.currencyCode ?? "BRL").locale(brazil)) } ?? "—")
                .frame(width: StockColumn.price, alignment: .trailing)
            Text(gross(inv).map(\.reais) ?? "—").fontWeight(.medium)
                .frame(width: StockColumn.value, alignment: .trailing)
            status(inv, closed: closed, match: match)
                .font(.callout)
                .frame(width: 230, alignment: .leading)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14)
        .frame(height: PageLayout.rowHeight)
        .background(rowTint(inv))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !closed else { return }
            if let target = match?.target { editor = editor(for: target) } else { toggleStaged(inv) }
        }
        .help(closed ? "" : match?.target == nil ? "Click to pick for import" : "Click to edit in StockBar")
    }

    /// Typing an average price picks the row: a new stock is imported with it, a held one gets it as an update.
    /// A held stock's current average shows as the placeholder.
    private func averageField(_ inv: PluggyInvestment, match: Match?) -> some View {
        let held: Holding? = if case .stock(let h)? = match?.target { h } else { nil }
        let binding = Binding(
            get: { staged[inv.id]?.input ?? "" },
            set: { text in
                if staged[inv.id] == nil {
                    if let held {
                        guard !text.isEmpty else { return }
                        staged[inv.id] = StagedImport(item: .stockAverage(ticker: held.ticker), input: "")
                    } else {
                        toggleStaged(inv)
                    }
                }
                if case .stockAverage? = staged[inv.id]?.item, text.isEmpty {
                    staged[inv.id] = nil
                    return
                }
                staged[inv.id]?.input = text
                staged[inv.id]?.failure = nil
            })
        let placeholder = held?.averagePrice.map { $0.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "pt_BR"))) } ?? "-"
        return TextField("Avg price", text: binding, prompt: Text(placeholder))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .controlSize(.small)
            .frame(width: 76)
    }

    /// Picks every untracked row in a group that has all it needs (bonds always, funds when the CNPJ is known);
    /// once they're all picked, it unpicks them.
    @ViewBuilder
    private func selectAll(_ items: [PluggyInvestment]) -> some View {
        let candidates = items.filter { inv in
            guard !isClosed(inv), compare(inv).target == nil, let editor = newEditor(inv) else { return false }
            if case .fund(let f) = editor { return f.cnpj.count == 14 }
            return true
        }
        let picked = candidates.filter { staged[$0.id] != nil }
        if !candidates.isEmpty {
            Button(picked.count == candidates.count ? "Unselect all" : "Select all (\(candidates.count - picked.count))") {
                if picked.count == candidates.count {
                    for inv in candidates { staged[inv.id] = nil }
                } else {
                    for inv in candidates where staged[inv.id] == nil { toggleStaged(inv) }
                }
            }
            .buttonStyle(.borderless)
            .font(.callout.weight(.medium))
            .foregroundStyle(Color.accentColor)
        }
    }

    private func investmentRow(_ inv: PluggyInvestment) -> some View {
        let closed = isClosed(inv)
        let match = closed ? nil : compare(inv)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.name ?? inv.code ?? "Investment").lineLimit(1)
                Text(details(inv)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(inv.quantity.map(\.shares) ?? "—")
                if let v = inv.value { Text("× \(v.formatted(.number.precision(.fractionLength(2...8)).locale(Locale(identifier: "pt_BR"))))").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: 150, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text(gross(inv).map(\.reais) ?? "—").fontWeight(.medium)
                if let taxes = taxes(inv), taxes > 0, let net = inv.balance {
                    Text("net \(net.reais)").font(.caption).foregroundStyle(.secondary)
                        .help("Income tax \(taxes.reais)")
                } else if let profit = inv.amountProfit, profit != 0 {
                    Text("profit \(profit.reais)").font(.caption).foregroundStyle(profit.gainColor)
                }
            }
            .frame(width: 150, alignment: .trailing)
            status(inv, closed: closed, match: match)
                .font(.callout)
                .frame(width: 230, alignment: .leading)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(rowTint(inv))
        .contentShape(Rectangle())
        .onTapGesture {
            guard !closed else { return }
            if let target = match?.target { editor = editor(for: target) } else { toggleStaged(inv) }
        }
        .help(closed ? "" : match?.target == nil ? "Click to pick for import" : "Click to edit in StockBar")
    }

    private func rowTint(_ inv: PluggyInvestment) -> Color {
        guard let s = staged[inv.id] else { return .clear }
        return s.failure != nil ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.16)
    }

    /// Pluggy's `amount` is the gross value and `balance` what's left after taxes; some positions only have one.
    private func gross(_ inv: PluggyInvestment) -> Double? { inv.amount ?? inv.balance }

    private func taxes(_ inv: PluggyInvestment) -> Double? {
        let t = (inv.taxes ?? 0) + (inv.taxes2 ?? 0)
        return t > 0 ? t : nil
    }

    /// StockBar's own value for a matched bond or fund, to set against Open Finance's.
    private func ourValue(_ target: Target) -> Double? {
        switch target {
        case .stock: nil
        case .bond(let b): store.bondPricer.value(b).gross
        case .fund(let f): funds.value(f)?.gross
        }
    }

    /// Matches, a one-click quantity update when they differ, or adding it when StockBar doesn't track it.
    @ViewBuilder
    private func status(_ inv: PluggyInvestment, closed: Bool, match: Match?) -> some View {
        if closed {
            Label("Closed", systemImage: "minus.circle").foregroundStyle(.secondary)
        } else if staged[inv.id] != nil {
            stagedControls(inv)
        } else if let match, let target = match.target {
            if match.matches {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Matches \(match.label)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let ours = ourValue(target), let theirs = gross(inv), theirs > 0 {
                        let diff = ours - theirs
                        Text("StockBar \(ours.reais) (\(diff >= 0 ? "+" : "")\(diff.reais))")
                            .font(.caption)
                            .foregroundStyle(abs(diff / theirs) < 0.005 ? Color.secondary : .orange)
                            .help("StockBar's gross value vs. Open Finance's. Small differences come from different price dates.")
                    }
                }
            } else {
                Button { update(target, from: match) } label: {
                    Label(match.quantityMatches ? "Update avg price" : "Update to \(match.quantity.quantity)", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless).foregroundStyle(.orange)
                .help(match.quantityMatches
                      ? "Average price: StockBar \(match.ourAverage.map { $0.price(for: match.label) } ?? "none"), Open Finance \(match.theirAverage.map { $0.price(for: match.label) } ?? "—")"
                      : "StockBar has \(match.ours.quantity); set \(match.label) to the Open Finance quantity" + (match.theirAverage.map { " and average price \($0.price(for: match.label))" } ?? ""))
            }
        } else if newEditor(inv) != nil {
            Button { toggleStaged(inv) } label: { Label("Add to StockBar", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderless)
        } else {
            Label("Not supported", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    // MARK: Import

    /// Picks a position for import, pre-filled the way the add forms would be, or drops it.
    private func toggleStaged(_ inv: PluggyInvestment) {
        if staged[inv.id] != nil { staged[inv.id] = nil; return }
        guard let editor = newEditor(inv) else { return }
        let brazil = Locale(identifier: "pt_BR")
        switch editor {
        case let .stock(ticker, quantity, price):
            staged[inv.id] = StagedImport(item: .stock(ticker: ticker, quantity: quantity ?? 0),
                                          input: price.map { $0.formatted(.number.precision(.fractionLength(2)).locale(brazil)) } ?? "")
        case .bond(let b):
            staged[inv.id] = StagedImport(item: .bond(b), input: "")
        case .fund(let f):
            staged[inv.id] = StagedImport(item: .fund(f), input: f.cnpj.isEmpty ? "" : CVM.formatCNPJ(f.cnpj))
        }
        importResult = nil
    }

    /// The inline input for a picked row (average price, or a fund's CNPJ) and a way to drop it.
    @ViewBuilder
    private func stagedControls(_ inv: PluggyInvestment) -> some View {
        let binding = Binding(get: { staged[inv.id]?.input ?? "" }, set: { staged[inv.id]?.input = $0; staged[inv.id]?.failure = nil })
        let item = staged[inv.id]!
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                switch item.item {
                case .stock:
                    Label("Ready to import", systemImage: "checkmark.circle").foregroundStyle(Color.accentColor)
                case .stockAverage:
                    Label("Will update avg price", systemImage: "checkmark.circle").foregroundStyle(Color.accentColor)
                case .bond:
                    Label("Ready to import", systemImage: "checkmark.circle").foregroundStyle(Color.accentColor)
                case .fund(let f) where f.cnpj.count == 14:
                    Label("Ready to import", systemImage: "checkmark.circle").foregroundStyle(Color.accentColor)
                case .fund:
                    // Only when Open Finance didn't say: a fund can't be priced without its CNPJ.
                    TextField("CNPJ", text: binding, prompt: Text("Fund CNPJ"))
                        .textFieldStyle(.roundedBorder).frame(width: 170)
                }
                Button { staged[inv.id] = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Don't import")
            }
            if let failure = item.failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            } else if !item.isValid {
                Text(item.input.isEmpty ? "CNPJ needed" : "Check this value").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var importBar: some View {
        let valid = staged.values.allSatisfy(\.isValid)
        return HStack(spacing: 14) {
            Image(systemName: "square.and.arrow.down.on.square").foregroundStyle(Color.accentColor)
            if staged.isEmpty {
                Text(importResult ?? "")
            } else {
                Text("\(staged.count) \(staged.count == 1 ? String(localized: "item") : String(localized: "items")) picked")
                if let importResult { Text(importResult).foregroundStyle(.secondary) }
            }
            Spacer()
            if staged.isEmpty {
                Button("Done") { importResult = nil }
            } else {
                Button("Clear") { staged = [:]; importResult = nil }
                Button {
                    Task { await runImport() }
                } label: {
                    if importing { ProgressView().controlSize(.small) } else { Text("Import \(staged.count) \(staged.count == 1 ? String(localized: "item") : String(localized: "items"))") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(importing || !valid)
                .help(valid ? "" : "Fill in the highlighted rows first")
            }
        }
        .controlSize(.large)
        .padding(.horizontal, PageLayout.padding)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    /// Adds every picked position. Stocks need a market price, checked side by side first; anything that fails
    /// stays picked with the reason on its row.
    private func runImport() async {
        importing = true
        defer { importing = false }
        let tickers = staged.values.compactMap { s -> String? in if case let .stock(t, _) = s.item { t } else { nil } }
        let priced = await withTaskGroup(of: (String, Bool).self) { group in
            for t in Set(tickers) { group.addTask { (t, (try? await MarketData.intraday(for: t)) != nil) } }
            return await group.reduce(into: [String: Bool]()) { $0[$1.0] = $1.1 }
        }
        var imported = 0, failed: [String] = []
        for (id, s) in staged {
            switch s.item {
            case .stockAverage(let ticker):
                if let held = store.holdings.first(where: { $0.ticker == ticker }) {
                    store.setQuantity(ticker, to: held.quantity, averagePrice: parseNumber(s.input))
                }
            case let .stock(ticker, quantity):
                guard priced[ticker] == true else {
                    staged[id]?.failure = "No market price for \(ticker)"
                    failed.append(ticker)
                    continue
                }
                let average = parseNumber(s.input).flatMap { $0 > 0 ? $0 : nil }
                if let held = store.holdings.first(where: { $0.ticker == ticker }) {
                    store.setQuantity(ticker, to: held.quantity + quantity, averagePrice: average ?? held.averagePrice)
                } else {
                    store.add(Trade(ticker: ticker, kind: .buy, date: .now, quantity: quantity, price: average))
                }
            case .bond(let b):
                store.saveBond(b)
            case .fund(var f):
                f.cnpj = s.input.filter(\.isNumber)
                funds.saveHolding(f)
            }
            staged[id] = nil
            imported += 1
        }
        importResult = "Imported \(imported)" + (failed.isEmpty ? "" : " · \(failed.count) left: \(failed.sorted().joined(separator: ", ")) (no market price)")
    }

    private func details(_ inv: PluggyInvestment) -> String {
        var parts: [String] = []
        if let code = inv.code { parts.append(code) }
        if let subtype = inv.subtype { parts.append(subtype) }
        if inv.type == "EQUITY" || inv.type == "ETF", let average = inv.averagePrice, !Privacy.isOn {
            parts.append("avg \(average.formatted(.currency(code: inv.currencyCode ?? "BRL").locale(Locale(identifier: "pt_BR"))))")
        }
        if let issuer = inv.issuer { parts.append(issuer) }
        if let rate = inv.rate { parts.append("\(rate.formatted(.number.precision(.fractionLength(0...2))))% \(inv.rateType ?? "")") }
        if let fixed = inv.fixedAnnualRate, fixed != 0 { parts.append("+\(fixed.formatted(.number.precision(.fractionLength(0...2))))% a.a.") }
        if let due = inv.dueDate { parts.append("due \(isoDay(due))") }
        return parts.joined(separator: " · ")
    }

    private func column(_ title: LocalizedStringKey, _ key: OpenFinanceSort, ascendingFirst: Bool = false) -> some View {
        SortHeader(title: title, key: key, sort: $sort, ascending: $ascending, ascendingFirst: ascendingFirst)
    }

    /// Status order puts what needs attention first: quantity differences, then untracked, then matches, then closed.
    private func sorted(_ items: [PluggyInvestment]) -> [PluggyInvestment] {
        func rank(_ inv: PluggyInvestment) -> Double {
            if isClosed(inv) { return 3 }
            let m = compare(inv)
            return m.target == nil ? 1 : m.matches ? 2 : 0
        }
        return switch sort {
        case .name: items.sorted(byText: { $0.name ?? $0.code ?? "" }, ascending: ascending)
        case .quantity: items.sorted(by: { $0.quantity }, ascending: ascending)
        case .value: items.sorted(by: { gross($0) }, ascending: ascending)
        case .status: items.sorted(by: rank, ascending: ascending)
        }
    }

    // MARK: Matching

    private enum Target { case stock(Holding), bond(Bond), fund(FundHolding) }

    private struct Match {
        var target: Target?
        var label = ""
        var ours = 0.0
        /// Open Finance's quantity, summed over entries with the same code.
        var quantity = 0.0
        /// For stocks: StockBar's average price and Open Finance's.
        var ourAverage: Double?
        var theirAverage: Double?
        var quantityMatches: Bool { abs(ours - quantity) <= max(0.0001, abs(quantity) * 0.0001) }
        /// Open Finance has an average price and StockBar has none, or one more than 0,5% away.
        var averageDiffers: Bool {
            guard let theirs = theirAverage else { return false }
            guard let ours = ourAverage else { return true }
            return abs(ours / theirs - 1) > 0.005
        }
        var matches: Bool { quantityMatches && !averageDiffers }
    }

    private func normalizedCode(_ inv: PluggyInvestment) -> String {
        (inv.code ?? "").uppercased().replacingOccurrences(of: "CDB-", with: "").trimmingCharacters(in: .whitespaces)
    }

    /// Stocks by ticker, bonds by code (or issuer and maturity), funds by CNPJ (or name).
    private func compare(_ inv: PluggyInvestment) -> Match {
        let code = normalizedCode(inv)
        // The same asset can be split across entries (or institutions); compare the open total.
        let siblings = code.isEmpty ? [inv] : openInvestments.filter { $0.type == inv.type && normalizedCode($0) == code }
        var match = Match(quantity: siblings.reduce(0) { $0 + ($1.quantity ?? 0) })

        switch inv.type {
        case "EQUITY", "ETF":
            if let h = store.holdings.first(where: { $0.ticker == code || $0.ticker + "F" == code }) {
                (match.target, match.label, match.ours) = (.stock(h), h.ticker, h.quantity)
                match.ourAverage = h.averagePrice
                // Across split entries, the average weighted by each one's quantity.
                let priced = siblings.compactMap { s in s.averagePrice.map { (price: $0, quantity: s.quantity ?? 0) } }
                let shares = priced.reduce(0) { $0 + $1.quantity }
                if shares > 0 { match.theirAverage = priced.reduce(0) { $0 + $1.price * $1.quantity } / shares }
            }
        case "FIXED_INCOME":
            let due = inv.dueDate.map(isoDayKey)
            if let b = store.bonds.first(where: { !code.isEmpty && ($0.code == code || code.hasSuffix($0.code)) })
                ?? store.bonds.first(where: { $0.maturityDay == due && fold(inv.issuer ?? inv.name ?? "").contains(fold($0.issuer).prefix(10)) }) {
                (match.target, match.label, match.ours) = (.bond(b), b.code, b.quantity)
            }
        case "MUTUAL_FUND":
            let digits = [inv.code, inv.number, inv.issuerCNPJ, inv.name].compactMap { $0?.filter(\.isNumber) }
            if let f = funds.holdings.first(where: { h in digits.contains { $0.contains(h.cnpj) } })
                ?? funds.holdings.first(where: { fold($0.name).prefix(12) == fold(inv.name ?? "").prefix(12) }) {
                (match.target, match.label, match.ours) = (.fund(f), CVM.formatCNPJ(f.cnpj), f.quantity)
            }
        default: break
        }
        return match
    }

    /// Takes Open Finance's quantity, and for stocks its average price when it has one.
    private func update(_ target: Target, from match: Match) {
        let quantity = match.quantity
        switch target {
        case .stock(let h): store.setQuantity(h.ticker, to: quantity, averagePrice: match.theirAverage ?? h.averagePrice)
        case .bond(var b): b.quantity = quantity; store.saveBond(b)
        case .fund(var f): f.quantity = quantity; funds.saveHolding(f)
        }
    }

    // MARK: Editing

    enum Editor: Identifiable {
        case stock(ticker: String, quantity: Double?, price: Double?)
        case bond(Bond)
        case fund(FundHolding)

        var id: String {
            switch self {
            case .stock(let t, _, _): "stock-\(t)"
            case .bond(let b): "bond-\(b.id)"
            case .fund(let f): "fund-\(f.id)"
            }
        }
    }

    private func editor(for target: Target) -> Editor {
        switch target {
        case .stock(let h): .stock(ticker: h.ticker, quantity: h.quantity, price: h.averagePrice)
        case .bond(let b): .bond(b)
        case .fund(let f): .fund(f)
        }
    }

    /// A StockBar entry pre-filled from Open Finance, for review before saving; nil for types StockBar doesn't track.
    private func newEditor(_ inv: PluggyInvestment) -> Editor? {
        let quantity = inv.quantity ?? 0
        let cost = inv.averagePrice
        let name = inv.name ?? inv.code ?? ""
        switch inv.type {
        case "EQUITY", "ETF":
            return .stock(ticker: normalizedCode(inv).isEmpty ? name : normalizedCode(inv), quantity: quantity, price: cost)
        case "FIXED_INCOME":
            return .bond(bond(from: inv, quantity: quantity, unitPrice: cost))
        case "MUTUAL_FUND":
            let cnpj = [inv.code, inv.number].compactMap { $0?.filter(\.isNumber) }.first { $0.count == 14 } ?? ""
            let subtype = (inv.subtype ?? "").uppercased(), folded = fold(name).uppercased()
            let kind: FundHoldingKind = subtype.contains("FIDC") || folded.contains("FIDC") ? .fidc
                : subtype.contains("FIP") || folded.contains("FIP") ? .fip : .fif
            return .fund(FundHolding(cnpj: cnpj, name: name, kind: kind, quantity: quantity,
                                     taxExempt: folded.contains("INCENT") || folded.contains("INFRA"),
                                     statementPrice: inv.value, statementDay: inv.date.map(isoDayKey) ?? DayKey.from(.now)))
        default:
            return nil
        }
    }

    /// Maps Open Finance's rate fields to an indexer; the form shows them for checking before saving.
    private func bond(from inv: PluggyInvestment, quantity: Double, unitPrice: Double?) -> Bond {
        let subtype = (inv.subtype ?? "").uppercased()
        let kind: BondKind = BondKind(rawValue: subtype)
            ?? (subtype.contains("DEBENTURE") ? .debenture : subtype.contains("LCI") ? .lci : subtype.contains("LCA") ? .lca : .cdb)
        // Pluggy gives "rate % of the index + fixedAnnualRate % a year": "0% + 15,68%" is a fixed-rate bond
        // whatever the index says, "92% + 0%" of CDI is 92% of CDI, "100% + 1,5%" is CDI + 1,5%.
        let index = (inv.rateType ?? "").uppercased()
        let share = inv.rate ?? 0, fixed = inv.fixedAnnualRate ?? 0
        let (indexer, rate): (BondIndexer, Double) =
            if index.contains("IPCA") { (.ipca, fixed > 0 ? fixed : share) }
            else if share == 0 { (.fixed, fixed) }
            else if index.contains("CDI") || index == "DI" || index.contains("SELIC") { fixed > 0 ? (.cdiPlus, fixed) : (.cdi, share) }
            else { (.fixed, fixed > 0 ? fixed : share) }
        let today = DayKey.from(.now)
        let cnpj = inv.issuerCNPJ?.filter(\.isNumber)
        return Bond(kind: kind, issuer: inv.issuer ?? inv.name ?? "", issuerCNPJ: cnpj?.count == 14 ? cnpj : nil, code: normalizedCode(inv),
                    issueDay: (inv.issueDate ?? inv.purchaseDate ?? inv.date).map(isoDayKey) ?? today,
                    maturityDay: inv.dueDate.map(isoDayKey) ?? today,
                    indexer: indexer, rate: rate, quantity: quantity, unitPrice: unitPrice ?? 1000)
    }

    private func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { $0.isLetter || $0.isNumber }
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "EQUITY": String(localized: "Stocks")
        case "ETF": "ETFs"
        case "FIXED_INCOME": String(localized: "Fixed income")
        case "MUTUAL_FUND": String(localized: "Funds")
        case "SECURITY": String(localized: "Securities")
        case "COE": "COE"
        default: type.capitalized
        }
    }

    private func isoDayKey(_ iso: String) -> Int { Int(iso.prefix(10).replacingOccurrences(of: "-", with: "")) ?? 0 }

    private func isoDay(_ iso: String) -> String {
        let key = isoDayKey(iso)
        return key > 0 ? DayKey.date(key).formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits).locale(Locale(identifier: "pt_BR"))) : iso
    }
}

/// Open Finance in Settings: a short setup guide, the Pluggy application's credentials, and the connections,
/// added and renewed through Pluggy Connect.
struct PluggySettingsSection: View {
    @Environment(PluggyStore.self) private var pluggy
    @State private var secret = ""
    @State private var newItem = ""
    @State private var connecting: ConnectRequest?
    @State private var showManual = false

    /// Opens the Connect widget, to add an item or reconnect one.
    struct ConnectRequest: Identifiable {
        var updating: String?
        var id: String { updating ?? "new" }
    }

    var body: some View {
        @Bindable var pluggy = pluggy
        Section {
            if !pluggy.isConfigured { guide }
            TextField("Client ID", text: $pluggy.clientId, prompt: Text("From your Pluggy application"))
                .disabled(pluggy.hasSecret)
            if pluggy.hasSecret {
                LabeledContent("Client secret") {
                    HStack {
                        Label("Saved in Keychain", systemImage: "lock.fill").foregroundStyle(.secondary)
                        Button("Forget", role: .destructive) { pluggy.forgetCredentials() }
                    }
                }
            } else {
                HStack {
                    SecureField("Client secret", text: $secret)
                    Button("Save") { pluggy.saveSecret(secret); secret = "" }
                        .disabled(pluggy.clientId.isEmpty || secret.isEmpty)
                }
            }

            ForEach(pluggy.itemIDs, id: \.self) { id in connectionRow(id) }

            HStack {
                Button {
                    connecting = ConnectRequest()
                } label: {
                    Label(pluggy.itemIDs.isEmpty ? "Connect a bank or broker" : "Connect another bank or broker", systemImage: "link.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!pluggy.isConfigured)
                Spacer()
                if pluggy.isSyncing { ProgressView().controlSize(.small) }
                Button("Sync now") { Task { await pluggy.sync() } }
                    .disabled(!pluggy.isConfigured || pluggy.itemIDs.isEmpty || pluggy.isSyncing)
            }
            if let error = pluggy.error {
                Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3)
            } else if let last = pluggy.lastSync {
                Text("Synced \(pluggy.investments.count) investments at \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }

            DisclosureGroup("Advanced: add an item ID by hand", isExpanded: $showManual) {
                HStack {
                    TextField("Item ID", text: $newItem, prompt: Text("00000000-0000-0000-0000-000000000000"))
                        .onSubmit { pluggy.addItem(newItem); newItem = "" }
                    Button("Add") { pluggy.addItem(newItem); newItem = "" }
                        .disabled(UUID(uuidString: newItem.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }
            .font(.callout)
        } header: {
            Text("Open Finance (Pluggy)")
        } footer: {
            Text("Your client secret stays in your login keychain and never leaves this Mac except to sign in to Pluggy. Meu Pluggy consent lasts a year; when it lapses, use Reconnect.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(item: $connecting) { request in
            PluggyConnectView(updating: request.updating).environment(pluggy)
        }
        .task { if pluggy.isConfigured, !pluggy.itemIDs.isEmpty, pluggy.lastSync == nil { await pluggy.sync() } }
    }

    /// What a new user needs before the first connection: their own (free) Pluggy application.
    private var guide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set up once").font(.callout.weight(.semibold))
            Group {
                Text("1. Create a free account at [meu.pluggy.ai](https://meu.pluggy.ai) and connect your banks and brokers there.")
                Text("2. In the [Pluggy dashboard](https://dashboard.pluggy.ai), open your application and copy its Client ID and Client Secret.")
                Text("3. Paste them below and click Connect a bank or broker. Each connection shares one institution from Meu Pluggy; connect again for the next one.")
            }
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func connectionRow(_ id: String) -> some View {
        let item = pluggy.items.first { $0.id == id }
        let reconnect = pluggy.needsReconnect(id)
        return HStack(spacing: 8) {
            Circle().fill(reconnect ? Color.orange : item?.status == "UPDATED" ? .green : .secondary).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(pluggy.institutions(of: id) ?? item?.connector?.name ?? "Connection")
                Text(reconnect ? (item?.error?.message ?? "Needs to be reconnected") : Privacy.isOn ? "•••" : id)
                    .font(.caption.monospaced()).foregroundStyle(reconnect ? .orange : .secondary)
                    .lineLimit(1).textSelection(.enabled)
            }
            Spacer()
            Button(reconnect ? "Reconnect" : "Renew") { connecting = ConnectRequest(updating: id) }
                .buttonStyle(.borderless)
                .foregroundStyle(reconnect ? .orange : Color.accentColor)
                .help("Open Pluggy Connect to sign in again for this connection")
            Button { pluggy.removeItem(id) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from StockBar (the connection stays in Pluggy)")
        }
    }
}
