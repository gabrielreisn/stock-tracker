import SwiftUI

@main
struct StockBarApp: App {
    @State private var store: PortfolioStore
    @State private var funds: FundStore
    @State private var pluggy: PluggyStore
    @State private var expenses: ExpenseStore
    @State private var bills: BillStore
    @State private var updater = Updater()
    @State private var chat: AIChat
    @State private var aiAccount: AIAccount
    @State private var localModel: LocalModel

    init() {
        DataAccount.prepareDemo()
        let store = PortfolioStore()
        let pluggy = PluggyStore()
        let funds = FundStore(portfolio: store)
        // Every sync makes StockBar match Open Finance, whichever page started it.
        pluggy.reconcile = { OpenFinanceMatcher(store: store, funds: funds, investments: $0).reconcile(updatedItems: $1) }
        _store = State(initialValue: store)
        _funds = State(initialValue: funds)
        _pluggy = State(initialValue: pluggy)
        let expenses = ExpenseStore(pluggy: pluggy)
        _expenses = State(initialValue: expenses)
        _bills = State(initialValue: BillStore(pluggy: pluggy, expenses: expenses))
        let account = AIAccount()
        let local = LocalModel()
        _aiAccount = State(initialValue: account)
        _localModel = State(initialValue: local)
        _chat = State(initialValue: AIChat(data: AIData(portfolio: store, funds: funds, expenses: expenses, pluggy: pluggy),
                                           account: account, local: local))
        let chat = _chat.wrappedValue
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { chat.stop() }
            local.shutdown()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(systemName: "chart.line.uptrend.xyaxis")
        }
        .menuBarExtraStyle(.window)

        Window("StockBar", id: "main") {
            MainWindow()
                .environment(store)
                .environment(funds)
                .environment(pluggy)
                .environment(expenses)
                .environment(bills)
                .environment(updater)
                .environment(chat)
                .environment(aiAccount)
                .environment(localModel)
        }
        .defaultSize(width: 1200, height: 860)
        .defaultPosition(.center)
        // The main window is the app; the menu bar item is a quick-look widget.
        .defaultLaunchBehavior(.presented)
    }
}
