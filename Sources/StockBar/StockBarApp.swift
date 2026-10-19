import SwiftUI

@main
struct StockBarApp: App {
    @State private var store = PortfolioStore()

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

        Window("StockBar Settings", id: "settings") {
            SettingsWindow()
                .environment(store)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
    }
}
