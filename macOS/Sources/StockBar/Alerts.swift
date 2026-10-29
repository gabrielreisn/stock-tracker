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

struct AlertsView: View {
    @Environment(PortfolioStore.self) private var store
    @Binding var screen: Screen

    @State private var ticker = ""
    @State private var kind: TradeKind = .buy
    @State private var price = ""
    @State private var checking = false
    @State private var error: String?
    @State private var pendingDelete: PriceAlert.ID?
    @State private var notificationsOff = false
    /// The alert loaded into the form for editing; nil while adding a new one.
    @State private var editing: PriceAlert.ID?
    @FocusState private var tickerFocused: Bool

    private var normalizedTicker: String {
        ticker.trimmingCharacters(in: .whitespaces).uppercased()
    }

    private var alert: PriceAlert? {
        guard !normalizedTicker.isEmpty, let target = parseNumber(price), target > 0 else { return nil }
        return PriceAlert(id: editing ?? UUID(), ticker: normalizedTicker, target: target, kind: kind)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "Price alerts", screen: $screen)
            form
            Divider()
            if store.alerts.isEmpty {
                Text("No alerts yet").foregroundStyle(.secondary).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.alerts) { alert in
                            row(alert)
                                .background(editing == alert.id ? Color.accentColor.opacity(0.12) : .clear)
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .frame(maxHeight: 340)
            }
        }
        .onAppear { tickerFocused = true }
        .onChange(of: ticker) { error = nil }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Type", selection: $kind) {
                    ForEach(TradeKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                TextField("Ticker", text: $ticker, prompt: Text("PETR4"))
                    .focused($tickerFocused)
                TextField("Price", text: $price, prompt: Text("38,50"))
                    .frame(width: 80)
                    .onSubmit(submit)
                Button {
                    submit()
                } label: {
                    if checking { ProgressView().controlSize(.small) } else { Text(editing == nil ? "Add" : "Save") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(alert == nil || checking)
                if editing != nil {
                    Button { stopEditing() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .keyboardShortcut(.cancelAction)
                        .help("Cancel editing")
                }
            }
            .textFieldStyle(.roundedBorder)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            } else {
                Text(kind == .buy ? "Notifies when the price drops to the target or below." : "Notifies when the price rises to the target or above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if notificationsOff {
                Label("Notifications are off. Allow StockBar in System Settings → Notifications.", systemImage: "bell.slash")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func row(_ alert: PriceAlert) -> some View {
        HStack(spacing: 10) {
            Toggle("Active", isOn: Binding(
                get: { alert.isEnabled },
                set: { store.setAlert(alert, enabled: $0) }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
            .help(alert.isEnabled ? "Active" : "Paused")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(alert.ticker).font(.callout.weight(.semibold))
                    KindBadge(kind: alert.kind)
                }
                Text(subtitle(alert)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .opacity(alert.isEnabled ? 1 : 0.55)

            Spacer()

            if let live = store.livePrice(alert.ticker) {
                Text(live.price(for: alert.ticker))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .help("Latest price")
            }
            Button { startEditing(alert) } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Edit")
            if pendingDelete == alert.id {
                Button("Delete") {
                    if editing == alert.id { stopEditing() }
                    store.deleteAlert(alert)
                    pendingDelete = nil
                }
                    .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
            } else {
                Button { pendingDelete = alert.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                    .help("Delete")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private func subtitle(_ alert: PriceAlert) -> String {
        let target = "\(alert.condition.prefix(1).uppercased())\(alert.condition.dropFirst()) \(alert.target.price(for: alert.ticker))"
        guard !alert.isEnabled, let fired = alert.triggeredAt else { return target }
        return String(localized: "Hit \(fired.formatted(date: .abbreviated, time: .shortened)) · \(target)")
    }

    /// Makes sure the ticker exists before saving, and asks for notification permission on the first alert.
    private func submit() {
        guard let alert, !checking else { return }
        checking = true
        Task {
            defer { checking = false }
            guard (try? await MarketData.intraday(for: alert.ticker)) != nil else {
                error = "Couldn't find \(alert.ticker)"
                return
            }
            notificationsOff = !(await AlertNotifier.shared.authorize())
            if editing == nil { store.addAlert(alert) } else { store.updateAlert(alert) }
            stopEditing()
        }
    }

    private func startEditing(_ alert: PriceAlert) {
        pendingDelete = nil
        editing = alert.id
        ticker = alert.ticker
        kind = alert.kind
        price = alert.target.editableQuantity
        tickerFocused = true
    }

    private func stopEditing() {
        editing = nil
        ticker = ""
        price = ""
        error = nil
        tickerFocused = true
    }
}

/// Small colored BUY / SELL tag.
struct KindBadge: View {
    let kind: TradeKind

    var body: some View {
        let color: Color = kind == .buy ? .green : .red
        Text(kind.label.uppercased())
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }
}
