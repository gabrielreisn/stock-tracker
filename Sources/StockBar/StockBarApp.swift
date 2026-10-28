import SwiftUI

@main
struct StockBarApp: App {
    @State private var store: PortfolioStore
    @State private var funds: FundStore
    @State private var pluggy: PluggyStore
    @State private var expenses: ExpenseStore
    @State private var bills: BillStore
    @State private var updater = Updater()

    init() {
        let store = PortfolioStore()
        let pluggy = PluggyStore()
        let funds = FundStore(portfolio: store)
        // Every sync makes StockBar match Open Finance, whichever page started it.
        pluggy.reconcile = { OpenFinanceMatcher(store: store, funds: funds, investments: $0).reconcile() }
        _store = State(initialValue: store)
        _funds = State(initialValue: funds)
        _pluggy = State(initialValue: pluggy)
        let expenses = ExpenseStore(pluggy: pluggy)
        _expenses = State(initialValue: expenses)
        _bills = State(initialValue: BillStore(pluggy: pluggy, expenses: expenses))
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
        }
        .defaultSize(width: 1200, height: 860)
        .defaultPosition(.center)
        // The main window is the app; the menu bar item is a quick-look widget.
        .defaultLaunchBehavior(.presented)
    }
}
