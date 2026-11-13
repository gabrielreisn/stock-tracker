import SwiftUI

struct OpenFinanceScreen: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(AppModel.self) private var app
    @Environment(PortfolioStore.self) private var portfolio
    @Environment(FundStore.self) private var funds
    @State private var importing = false
    @State private var query = ""
    @State private var showClosed = false
    private var visible: [PluggyInvestment] {
        pluggy.investments.filter { inv in
            (showClosed || !OpenFinanceMatcher.isClosed(inv)) && (query.isEmpty || "\(inv.name ?? "") \(inv.code ?? "") \(inv.type ?? "")".localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        CymbaPage(spacing: 12) {
            Text("Open Finance").font(.system(size: 28, weight: .bold)).accessibilityAddTraits(.isHeader)
            CymbaCaption(text: "Personal account · saved on this device.")
            if let date = pluggy.lastSync { Text("\(String(localized: "Last sync")): \(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary) }
            else { CymbaCaption(text: "Waiting for sync") }
            CymbaCaption(text: "Refreshes after 6 hours and when the app opens with stale data.")
            CymbaCaption(text: "Background refresh is managed by the operating system; timing may vary.")
            Button("Sync now") { Task { await app.sync(force: true) } }.buttonStyle(CymbaActionStyle()).disabled(pluggy.isSyncing || pluggy.itemIDs.isEmpty)
            NavigationLink { CymbaPage { ConnectionSettingsGroup() }.cymbaNavigationTitle("Open Finance") } label: { Text("Manage connections in Settings").font(.system(size: 14)).foregroundStyle(CymbaTheme.link) }
            if let error = pluggy.error { Text(error).font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
            CymbaHeading(title: "Connections").padding(.top, 12)
            ForEach(pluggy.itemIDs, id: \.self) { id in
                CymbaCard(spacing: 6) {
                    Text(pluggy.institutions(of: id) ?? pluggy.items.first(where: { $0.id == id })?.connector?.name ?? "Connection").font(.system(size: 14))
                    Text(pluggy.items.first(where: { $0.id == id })?.status ?? String(localized: "Waiting for sync")).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                }
            }
            CymbaHeading(title: "Accounts").padding(.top, 12)
            ForEach(pluggy.accounts) { a in
                CymbaCard(spacing: 6) {
                    Text(a.marketingName ?? a.name ?? String(localized: "Account")).font(.system(size: 14))
                    Text("\(a.type ?? "") · \(Privacy.isOn ? Privacy.mask : a.number ?? "")").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                    Text(a.balance?.reais ?? "—").font(.system(size: 18, weight: .semibold))
                }
            }
            if pluggy.accounts.isEmpty { CymbaCaption(text: "No accounts available yet.") }
            CymbaHeading(title: "Investments").padding(.top, 12)
            CymbaCaption(text: "Positions with missing terms or fund identifiers remain here for review. No values are guessed.")
            TextField("Search investments", text: $query).textFieldStyle(CymbaInputStyle())
            Button(showClosed ? "Hide closed positions" : "Show closed positions") { showClosed.toggle() }.buttonStyle(CymbaActionStyle())
            Button("Import selected positions") { importing = true }.buttonStyle(CymbaActionStyle())
            ForEach(visible) { inv in
                CymbaCard(spacing: 6) {
                    Text(inv.name ?? inv.code ?? String(localized: "Investment")).font(.system(size: 14))
                    Text("\(inv.type ?? "") · \(inv.subtype ?? "") · \(inv.code ?? "")").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                    Text((inv.amount ?? inv.balance)?.reais ?? "—").font(.system(size: 14))
                    Text("\(String(localized: "Quantity")): \(inv.quantity?.quantity ?? "—")").font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                    let tracked = OpenFinanceMatcher(store: portfolio, funds: funds, investments: pluggy.investments).target(of: inv) != nil
                    Text(LocalizedStringKey(OpenFinanceMatcher.isClosed(inv) ? "Closed" : tracked ? "Tracked in portfolio" : "Review missing details")).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary)
                }
            }
        }.cymbaNavigationTitle("Open Finance")
        .sheet(isPresented: $importing) { BatchImportScreen() }
        .refreshable { await app.sync(force: true) }
    }
}

struct BatchImportScreen: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(PortfolioStore.self) private var store
    @Environment(FundStore.self) private var funds
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var averages: [String: String] = [:]
    @State private var note: String?
    private var candidates: [PluggyInvestment] {
        let matcher = OpenFinanceMatcher(store: store, funds: funds, investments: pluggy.investments)
        return pluggy.investments.filter { !OpenFinanceMatcher.isClosed($0) && matcher.target(of: $0) == nil && ["EQUITY", "ETF", "FIXED_INCOME", "MUTUAL_FUND"].contains($0.type ?? "") }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Complete positions are imported automatically. Select remaining positions and supply missing acquisition prices. Bonds still need their reported rate, issue date and maturity; funds need a CNPJ.").font(.caption).foregroundStyle(CymbaTheme.secondary)
                    Button("Select all bonds and funds") { selected = Set(candidates.filter { $0.type == "FIXED_INCOME" || $0.type == "MUTUAL_FUND" }.map(\.id)) }
                }
                ForEach(candidates) { inv in
                    Section {
                        Toggle(isOn: Binding(get: { selected.contains(inv.id) }, set: { if $0 { selected.insert(inv.id) } else { selected.remove(inv.id) } })) {
                            Text(inv.name ?? inv.code ?? "Investment")
                            Text("\((inv.quantity ?? 0).quantity) · \(inv.balance?.reais ?? "—")").font(.caption)
                        }
                        if inv.type != "MUTUAL_FUND" {
                            TextField("Average price", text: Binding(get: { averages[inv.id] ?? inv.averagePrice?.editableQuantity ?? "" }, set: { averages[inv.id] = $0 })).keyboardType(.decimalPad)
                        }
                    }
                }
                if candidates.isEmpty { Text("Every supported position is already tracked.") }
                if let note { Text(note).font(.caption).foregroundStyle(.orange) }
            }.cymbaList().cymbaNavigationTitle("Import positions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Import") { runImport() }.disabled(selected.isEmpty) }
            }
        }
    }
    private func runImport() {
        let entries = candidates.filter { selected.contains($0.id) }.map { inv in
            var inv = inv
            if let input = averages[inv.id], let cost = parseNumber(input), cost > 0, let quantity = inv.quantity {
                inv.amountOriginal = cost * quantity
            }
            return inv
        }
        let ids = Set(entries.compactMap(\.itemId))
        _ = OpenFinanceImporter.apply(entries, completedItems: ids, store: store, funds: funds, reconcile: false)
        let matcher = OpenFinanceMatcher(store: store, funds: funds, investments: pluggy.investments)
        let remaining = entries.filter { matcher.target(of: $0) == nil }.count
        selected = []
        note = remaining > 0 ? String(localized: "Some positions are missing contract terms or a fund CNPJ. Add them manually in Investments after checking your statement.") : String(localized: "Positions imported.")
    }
}
