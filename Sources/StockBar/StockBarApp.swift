import SwiftUI

@main
struct StockBarApp: App {
    @State private var store: PortfolioStore
    @State private var funds: FundStore
    @State private var pluggy = PluggyStore()

    init() {
        let store = PortfolioStore()
        _store = State(initialValue: store)
        _funds = State(initialValue: FundStore(portfolio: store))
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
        }
        .defaultSize(width: 1200, height: 860)
        .defaultPosition(.center)
        // The main window is the app; the menu bar item is a quick-look widget.
        .defaultLaunchBehavior(.presented)
    }
}
