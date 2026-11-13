import SwiftUI
import BackgroundTasks
import UIKit

@MainActor @Observable
final class AppModel {
    let portfolio: PortfolioStore
    let funds: FundStore
    let pluggy: PluggyStore
    let expenses: ExpenseStore
    let bills: BillStore
    let ai = AIAccount()
    let local = LocalModel()
    let chat: AIChat
    private var lastAttempt = Date.distantPast
    private var syncing = false
    init() {
        let portfolio = PortfolioStore()
        let funds = FundStore(portfolio: portfolio)
        let pluggy = PluggyStore()
        let expenses = ExpenseStore(pluggy: pluggy)
        self.portfolio = portfolio; self.funds = funds; self.pluggy = pluggy; self.expenses = expenses
        bills = BillStore(pluggy: pluggy, expenses: expenses)
        pluggy.reconcile = { OpenFinanceImporter.apply($0, completedItems: $1, store: portfolio, funds: funds) }
        chat = AIChat(data: AIData(portfolio: portfolio, funds: funds, expenses: expenses, pluggy: pluggy), account: ai, local: local)
    }
    func sync(force: Bool = false) async {
        guard !syncing, pluggy.isConfigured, !pluggy.itemIDs.isEmpty else { return }
        guard force || (Date.now.timeIntervalSince(pluggy.lastSync ?? .distantPast) >= 21600 && Date.now.timeIntervalSince(lastAttempt) >= 900) else { return }
        syncing = true; lastAttempt = .now
        defer { syncing = false }
        let firstSync = pluggy.lastSync == nil
        await pluggy.sync()
        let month = DayKey.from(.now) / 100
        for step in 0...2 { await expenses.loadMonth(DayKey.addMonths(month * 100 + 1, -step) / 100) }
        if firstSync {
            await expenses.loadYear(month / 100 - 1)
            await expenses.loadYear(month / 100)
        }
        await bills.refresh()
        await portfolio.refresh()
        funds.loadHoldings()
    }
    nonisolated static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: "app.cymba.native.refresh")
        request.earliestBeginDate = .now.addingTimeInterval(21600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

@main
struct StockBarApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    @AppStorage("theme") private var theme = "system"
    init() {
        let foreground = CymbaTheme.adaptiveUIColor(0x171717, 0xededed)
        let background = CymbaTheme.adaptiveUIColor(0xffffff, 0x0a0a0a)
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = background
        navigation.shadowColor = .clear
        navigation.titleTextAttributes = [.foregroundColor: foreground]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().tintColor = foreground
        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = background
        tabs.shadowColor = .clear
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
        UITabBar.appearance().tintColor = foreground
    }
    var body: some Scene {
        WindowGroup {
            PhoneTabs()
                .environment(model).environment(model.portfolio).environment(model.funds)
                .environment(model.pluggy).environment(model.expenses).environment(model.bills)
                .environment(model.ai).environment(model.local).environment(model.chat)
                .onChange(of: model.portfolio.lastUpdated) { WidgetSnapshot.update(portfolio: model.portfolio, funds: model.funds) }
                .onChange(of: model.funds.holdingSeriesVersion) { WidgetSnapshot.update(portfolio: model.portfolio, funds: model.funds) }
                .preferredColorScheme(theme == "system" ? nil : theme == "dark" ? .dark : .light)
                .task {
                    model.funds.loadHoldings()
                    await model.expenses.loadCacheIfNeeded()
                    await model.bills.load()
                    while !Task.isCancelled {
                        await model.sync()
                        try? await Task.sleep(for: .seconds(60))
                    }
                }
                .onChange(of: phase) { _, value in
                    if value == .active { Task { await model.sync() } }
                    if value == .background { AppModel.schedule() }
                }
        }
        .backgroundTask(.appRefresh("app.cymba.native.refresh")) {
            await model.sync()
            AppModel.schedule()
        }
    }
}
