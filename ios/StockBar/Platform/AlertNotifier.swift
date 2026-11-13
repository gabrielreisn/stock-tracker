import SwiftUI
import UserNotifications

/// Posts price-alert notifications. The app is a menu bar app, so they're shown even while its window is open.
final class AlertNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlertNotifier()

    /// Notifications need a bundled app; a bare `swift run` binary has no bundle and would crash.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func setUp() {
        center?.delegate = self
    }

    /// Asks the first time; afterwards just reports whether notifications are allowed.
    func authorize() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    @discardableResult
    func send(_ alert: PriceAlert, price: Double) async -> Bool {
        guard let center, await authorize() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "\(alert.kind.label) \(alert.ticker)"
        content.body = String(localized: "\(alert.ticker) is at \(price.price(for: alert.ticker)), \(alert.condition) your target of \(alert.target.price(for: alert.ticker)).")
        content.sound = .default
        do {
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            return true
        } catch {
            return false
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

