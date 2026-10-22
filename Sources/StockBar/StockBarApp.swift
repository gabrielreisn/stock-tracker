import SwiftUI

@main
struct StockBarApp: App {
    @State private var store: PortfolioStore
    @State private var funds: FundStore

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
            let title = store.menuBarTitle
            if title.isEmpty {
                Image(systemName: "chart.line.uptrend.xyaxis")
            } else {
                Text("\(Image(systemName: "chart.line.uptrend.xyaxis")) \(title)")
            }
        }
        .menuBarExtraStyle(.window)

        Window("StockBar", id: "main") {
            MainWindow()
                .environment(store)
                .environment(funds)
        }
        .defaultSize(width: 1200, height: 860)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
    }
}
