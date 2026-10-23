import SwiftUI

enum OpenFinanceSort: String {
    case name, quantity, value, status
}

/// What Open Finance (via Pluggy) reports, side by side with what StockBar tracks. Read-only: nothing is imported.
struct OpenFinancePage: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @AppStorage("mainSection") private var section: MainSection = .stocks
    @State private var showClosed = false
    @State private var editor: Editor?
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
                    Text(item.connector?.name ?? "Item").fontWeight(.semibold)
                    Text(item.status ?? "").font(.caption).foregroundStyle(.secondary)
                    if let message = item.error?.message { Text(message).font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    if let updated = item.lastUpdatedAt ?? item.updatedAt { Text("updated \(isoDay(updated))").font(.caption).foregroundStyle(.secondary) }
                    Text(item.id).font(.caption.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
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
                        Text([a.type, a.subtype, a.number].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
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
                    Text(typeLabel(type)).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                    HStack(alignment: .top, spacing: 12) {
                        column("Name", .name, ascendingFirst: true).frame(maxWidth: .infinity, alignment: .leading)
                        column("Quantity", .quantity).frame(width: 150, alignment: .trailing)
                        column("Value", .value).frame(width: 150, alignment: .trailing)
                        column("StockBar", .status, ascendingFirst: true).frame(width: 210, alignment: .leading)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.bottom, 4)
                    Divider()
                    ForEach(sorted(groups[type]!)) { inv in
                        investmentRow(inv)
                        Divider().padding(.horizontal, 14)
                    }
                }
                .card()
            }
        }
    }

    private func investmentRow(_ inv: PluggyInvestment) -> some View {
        let closed = isClosed(inv)
        let match = closed ? nil : compare(inv)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.name ?? inv.code ?? "Investment").lineLimit(1)
                Text(details(inv)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(inv.quantity.map { $0.formatted(.number.precision(.fractionLength(0...8)).locale(Locale(identifier: "pt_BR"))) } ?? "—")
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
                .font(.caption)
                .frame(width: 210, alignment: .leading)
        }
        .font(.callout.monospacedDigit())
        .padding(.horizontal, 14).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { if !closed { editor = match?.target.map(editor(for:)) ?? newEditor(inv) } }
        .help(closed ? "" : match?.target == nil ? "Click to add to StockBar" : "Click to edit in StockBar")
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
        } else if let match, let target = match.target {
            if match.matches {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Matches \(match.label)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let ours = ourValue(target), let theirs = gross(inv), theirs > 0 {
                        let diff = ours - theirs
                        Text("StockBar \(ours.reais) (\(diff >= 0 ? "+" : "")\(diff.reais))")
                            .foregroundStyle(abs(diff / theirs) < 0.005 ? Color.secondary : .orange)
                            .help("StockBar's gross value vs. Open Finance's. Small differences come from different price dates.")
                    }
                }
            } else {
                Button { update(target, to: match.quantity) } label: {
                    Label("Update to \(match.quantity.quantity) (StockBar has \(match.ours.quantity))", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless).foregroundStyle(.orange)
                .help("Set \(match.label) to the Open Finance quantity")
            }
        } else if let new = newEditor(inv) {
            Button { editor = new } label: { Label("Add to StockBar", systemImage: "plus.circle.fill") }
                .buttonStyle(.borderless)
        } else {
            Label("Not supported", systemImage: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func details(_ inv: PluggyInvestment) -> String {
        var parts: [String] = []
        if let code = inv.code { parts.append(code) }
        if let subtype = inv.subtype { parts.append(subtype) }
        if let issuer = inv.issuer { parts.append(issuer) }
        if let rate = inv.rate { parts.append("\(rate.formatted(.number.precision(.fractionLength(0...2))))% \(inv.rateType ?? "")") }
        if let fixed = inv.fixedAnnualRate, fixed != 0 { parts.append("+\(fixed.formatted(.number.precision(.fractionLength(0...2))))% a.a.") }
        if let due = inv.dueDate { parts.append("due \(isoDay(due))") }
        return parts.joined(separator: " · ")
    }

    private func column(_ title: String, _ key: OpenFinanceSort, ascendingFirst: Bool = false) -> some View {
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
        var matches: Bool { abs(ours - quantity) <= max(0.0001, abs(quantity) * 0.0001) }
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

    private func update(_ target: Target, to quantity: Double) {
        switch target {
        case .stock(let h): store.setQuantity(h.ticker, to: quantity, averagePrice: h.averagePrice)
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
        let cost = (inv.amountOriginal ?? 0) > 0 && quantity > 0 ? inv.amountOriginal! / quantity : nil
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
        case "EQUITY": "Stocks"
        case "ETF": "ETFs"
        case "FIXED_INCOME": "Fixed income"
        case "MUTUAL_FUND": "Funds"
        case "SECURITY": "Securities"
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

/// Credentials and item IDs, in Settings.
struct PluggySettingsSection: View {
    @Environment(PluggyStore.self) private var pluggy
    @State private var secret = ""
    @State private var newItem = ""

    var body: some View {
        @Bindable var pluggy = pluggy
        Section {
            TextField("Client ID", text: $pluggy.clientId)
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
            ForEach(pluggy.itemIDs, id: \.self) { id in
                LabeledContent("Item") {
                    HStack {
                        Text(id).font(.caption.monospaced()).textSelection(.enabled)
                        Button { pluggy.removeItem(id) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
            }
            HStack {
                TextField("Add item ID", text: $newItem, prompt: Text("00000000-0000-0000-0000-000000000000"))
                    .onSubmit { pluggy.addItem(newItem); newItem = "" }
                Button("Add") { pluggy.addItem(newItem); newItem = "" }
                    .disabled(UUID(uuidString: newItem.trimmingCharacters(in: .whitespaces)) == nil)
            }
            HStack {
                if let error = pluggy.error { Text(error).font(.caption).foregroundStyle(.orange).lineLimit(3) }
                else if let last = pluggy.lastSync { Text("Synced \(pluggy.investments.count) investments at \(last.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if pluggy.isSyncing { ProgressView().controlSize(.small) }
                Button("Sync now") { Task { await pluggy.sync() } }
                    .disabled(!pluggy.isConfigured || pluggy.itemIDs.isEmpty || pluggy.isSyncing)
            }
        } header: {
            Text("Open Finance (Pluggy)")
        } footer: {
            Text("The secret is stored in your login keychain. Meu Pluggy can't list connections through the API, so add the item ID of each connection from the Pluggy dashboard.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
