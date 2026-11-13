import Foundation
import WidgetKit

@MainActor
enum WidgetSnapshot {
    static func update(portfolio: PortfolioStore, funds: FundStore) {
        guard let defaults = UserDefaults(suiteName: "group.app.cymba.native.shared") else { return }
        defaults.set(portfolio.totalValue + portfolio.bonds.reduce(0) { $0 + portfolio.bondPricer.value($1).gross } + funds.holdings.reduce(0) { $0 + (funds.value($1)?.gross ?? 0) }, forKey: "total")
        defaults.set(portfolio.dayChange, forKey: "change")
        defaults.set(portfolio.lastUpdated, forKey: "updated")
        defaults.set(Privacy.isOn, forKey: "hidden")
        defaults.set(portfolio.holdings.sorted { $0.weight > $1.weight }.prefix(3).map(\.ticker), forKey: "holdings")
        WidgetCenter.shared.reloadTimelines(ofKind: "StockBarPortfolio")
    }
}
