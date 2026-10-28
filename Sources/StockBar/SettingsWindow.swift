import ServiceManagement
import SwiftUI

struct SettingsWindow: View {
    @Environment(PortfolioStore.self) private var store
    @State private var showOnboarding = false

    var body: some View {
        Form {
            Section {
                ForEach(BenchmarkID.allCases) { id in
                    Toggle(isOn: Binding(
                        get: { store.enabledBenchmarks.contains(id) },
                        set: { store.setBenchmark(id, enabled: $0) }
                    )) {
                        HStack(alignment: .top, spacing: 10) {
                            LegendSwatch(series: .benchmark(id))
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(id.label)
                                Text(id.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .disabled(!store.enabledBenchmarks.contains(id) && store.enabledBenchmarks.count >= BenchmarkID.maxEnabled)
                }
            } header: {
                Text("Benchmarks")
            } footer: {
                Text("Up to \(BenchmarkID.maxEnabled) at a time, so every line stays distinguishable. Rate-based ones are drawn dashed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            PluggySettingsSection()

            Section("General") {
                LanguagePicker()
                LaunchAtLoginToggle()
                LabeledContent("Setup guide") {
                    Button("Show") { showOnboarding = true }
                }
                LabeledContent("Data") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([PortfolioStore.dataURL])
                    }
                }
                LabeledContent("Sources") {
                    Text("Prices, USD/BRL, S&P 500, IBOV: Yahoo Finance\nCDI and IPCA: Banco Central (SGS)\nIFIX history: B3")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }

            UpdatesSection()

            Section {
                HStack {
                    Spacer()
                    Button("Quit StockBar") { NSApplication.shared.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
    }
}

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
    }
}

private struct UpdatesSection: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Section {
            LabeledContent("Version") {
                Text(verbatim: Updater.currentVersion).monospacedDigit()
            }
            HStack {
                status
                Spacer()
                if case .available = updater.state {
                    Button("Update and relaunch") { updater.install() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Check now") { Task { await updater.check() } }
                        .disabled(updater.isBusy)
                }
            }
            Toggle("Check for updates automatically", isOn: $updater.checkAutomatically)
            Toggle("Include beta versions", isOn: $updater.includeBetas)
        } header: {
            Text("Updates")
        } footer: {
            Text("Updates come from StockBar's releases on GitHub and are installed only when signed like this copy.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }.foregroundStyle(.secondary)
        case .upToDate:
            VStack(alignment: .leading, spacing: 2) {
                Text("StockBar is up to date")
                if let last = updater.lastCheck {
                    Text("Checked \(last.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                }
            }
        case .available(let release):
            VStack(alignment: .leading, spacing: 2) {
                Text("StockBar \(release.version) is available")
                Link("Release notes", destination: release.page).font(.caption)
            }
        case .downloading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading update…") }.foregroundStyle(.secondary)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing update…") }.foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

/// The app's language. macOS reads it (AppleLanguages in the app's own preferences) only at launch,
/// so a change asks to relaunch; "Later" keeps it for the next launch.
struct LanguagePicker: View {
    @State private var language = Self.saved
    @State private var pending: String?

    private static var bundleID: CFString { (Bundle.main.bundleIdentifier ?? "com.gabrielreis.stockbar") as CFString }

    /// Only the app's own setting, not the Mac's language list from the global domain.
    private static var saved: String {
        (CFPreferencesCopyValue("AppleLanguages" as CFString, bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String])?.first ?? "system"
    }

    var body: some View {
        Picker("Language", selection: Binding(get: { language }, set: { new in
            guard new != language else { return }
            language = new
            save(new)
            pending = new
        })) {
            Text("System").tag("system")
            Text(verbatim: "English").tag("en")
            Text(verbatim: "Português (Brasil)").tag("pt-BR")
        }
        .alert("Relaunch StockBar to change the language?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Relaunch now") { relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The new language is used from the next launch.")
        }
    }

    private func save(_ language: String) {
        let value: CFPropertyList? = language == "system" ? nil : [language] as CFArray
        CFPreferencesSetValue("AppleLanguages" as CFString, value, Self.bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSynchronize(Self.bundleID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
