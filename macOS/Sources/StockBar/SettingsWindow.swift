import ServiceManagement
import SwiftUI

struct SettingsWindow: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(PluggyStore.self) private var pluggy
    @Environment(Updater.self) private var updater
    @Environment(AIAccount.self) private var ai
    @Environment(LocalModel.self) private var local
    @AppStorage(AppTheme.key) private var theme: AppTheme = .system

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(spacing: 10) {
                SettingsGroup("appearance", title: "Appearance", systemImage: "paintbrush", summary: appearanceSummary) {
                    Section {
                        Picker("Theme", selection: $theme) {
                            ForEach(AppTheme.allCases) { Text(String(localized: $0.label)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: theme) { AppTheme.apply() }
                        LanguagePicker()
                    }
                }
                SettingsGroup("benchmarks", title: "Benchmarks", systemImage: "chart.xyaxis.line",
                              summary: store.enabledBenchmarks.map(\.label).joined(separator: " · ")) {
                    benchmarks
                }
                SettingsGroup("openFinance", title: "Open Finance", systemImage: "building.2", summary: openFinanceSummary) {
                    PluggySettingsSection(showsHeader: false)
                }
                SettingsGroup("ai", title: "AI", systemImage: "sparkles", summary: aiSummary) {
                    AISettingsSection()
                }
                SettingsGroup("general", title: "General", systemImage: "gearshape",
                              summary: String(localized: "Launch at login, data and sources")) {
                    Section {
                        LaunchAtLoginToggle()
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
                }
                SettingsGroup("updates", title: "Updates", systemImage: "arrow.down.circle", summary: updatesSummary) {
                    UpdatesSection()
                }
            }
            .padding(.bottom, 16)
            // Outside the groups, so it's a plain button rather than a row of its own.
            Button("Quit StockBar") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(width: 600)
    }

    private var benchmarks: some View {
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
        } footer: {
            Text("Up to \(BenchmarkID.maxEnabled) at a time, so every line stays distinguishable. Rate-based ones are drawn dashed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appearanceSummary: String {
        [String(localized: theme.label), LanguagePicker.savedLabel].joined(separator: " · ")
    }

    private var openFinanceSummary: String {
        guard pluggy.isConfigured else { return String(localized: "Not set up") }
        let connections = pluggy.itemIDs.count == 1 ? String(localized: "1 connection") : String(localized: "\(pluggy.itemIDs.count) connections")
        guard let last = pluggy.lastSync else { return connections }
        return connections + " · " + String(localized: "synced \(last.formatted(date: .omitted, time: .shortened))")
    }

    private var aiSummary: String {
        switch ai.engine {
        case .cloud: ai.provider.map { "\($0.label) · \(ai.model)" } ?? String(localized: "Your API key · not saved yet")
        case .local: LocalModel.displayName + " · " + (local.isReady ? String(localized: "on this Mac") : String(localized: "not downloaded"))
        case .apple: String(localized: "Apple Intelligence, on this Mac")
        }
    }

    private var updatesSummary: String {
        var parts = [String(localized: "Version \(Updater.currentVersion)")]
        if case .available(let release) = updater.state { parts.append(String(localized: "\(release.version) available")) }
        return parts.joined(separator: " · ")
    }
}

/// A collapsible card of settings: an icon, a title and a one-line summary of what's inside, so the page stays
/// short. `content` is one or more form `Section`s. Which cards are open is remembered.
struct SettingsGroup<Content: View>: View {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    let summary: String
    @ViewBuilder var content: Content
    @AppStorage("settingsExpanded") private var expandedIDs = ""

    init(_ id: String, title: LocalizedStringKey, systemImage: String, summary: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.summary = summary
        self.content = content()
    }

    private var isExpanded: Bool { expandedIDs.split(separator: ",").contains(Substring(id)) }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    var ids = expandedIDs.split(separator: ",").map(String.init)
                    if isExpanded { ids.removeAll { $0 == id } } else { ids.append(id) }
                    expandedIDs = ids.joined(separator: ",")
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.system(size: 15))
                        .frame(width: 32, height: 32)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                Divider()
                Form { content }
                    .formStyle(.grouped)
                    .scrollDisabled(true)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Light, dark or following the Mac. Set on the whole app, so the menu bar window follows too.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    static let key = "appTheme"
    var id: String { rawValue }

    var label: String.LocalizationValue {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    static func apply() {
        let theme = UserDefaults.standard.string(forKey: key).flatMap(AppTheme.init) ?? .system
        NSApp.appearance = switch theme {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The AI tab's engine: Apple Intelligence, the local model (downloaded here) or the user's own API key, in one
/// field for any provider (StockBar finds out whose it is).
struct AISettingsSection: View {
    @Environment(AIAccount.self) private var ai
    @Environment(LocalModel.self) private var local
    @State private var key = ""

    var body: some View {
        @Bindable var ai = ai
        Section {
            Picker("Engine", selection: $ai.engine) {
                Text("Apple Intelligence").tag(AIEngine.apple)
                Text(verbatim: LocalModel.displayName).tag(AIEngine.local)
                Text("Your API key").tag(AIEngine.cloud)
            }
            .pickerStyle(.radioGroup)
        } footer: {
            Group {
                switch ai.engine {
                case .apple:
                    Text("On this Mac, free and private. Needs macOS 26 and Apple silicon; the slowest and least capable of the three.")
                case .local:
                    Text("On this Mac, free and private, after a one-time download. About 1–2 seconds an answer on Apple silicon.")
                case .cloud:
                    Text("The provider's model, billed to your key. The fastest and most capable; your questions and what StockBar looks up leave the Mac.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        switch ai.engine {
        case .apple: EmptyView()
        case .local: localModel
        case .cloud: apiKey
        }
    }

    private var localModel: some View {
        Section {
            LabeledContent {
                switch local.state {
                case .missing:
                    Button("Download (\(LocalModel.size.formatted(.byteCount(style: .file))))") { local.startDownload() }
                case .downloading(let fraction):
                    HStack {
                        ProgressView(value: fraction).frame(width: 140)
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit().foregroundStyle(.secondary)
                        Button("Cancel") { local.cancelDownload() }
                    }
                case .verifying:
                    HStack { ProgressView().controlSize(.small); Text("Checking the download…").foregroundStyle(.secondary) }
                case .ready:
                    HStack {
                        Text("Downloaded").foregroundStyle(.secondary)
                        Button("Delete", role: .destructive) { local.delete() }
                    }
                case .failed(let message):
                    HStack {
                        Text(message).foregroundStyle(.orange).lineLimit(2)
                        Button("Try again") { local.startDownload() }
                    }
                }
            } label: {
                Text(verbatim: LocalModel.displayName)
            }
        } footer: {
            Group {
                #if arch(arm64)
                Text("Runs on this Mac with llama.cpp. While answering it uses about 3,5 GB of memory, freed ten minutes after the last question. Until it's downloaded, the AI tab uses Apple Intelligence.")
                #else
                Text("Runs on this Mac with llama.cpp. On an Intel Mac it runs on the processor and is slow. Until it's downloaded, the AI tab uses Apple Intelligence.")
                #endif
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var apiKey: some View {
        @Bindable var ai = ai
        Section {
            if let provider = ai.provider {
                LabeledContent("API key") {
                    HStack {
                        Label(provider.label, systemImage: "lock.fill").foregroundStyle(.secondary)
                        Button("Forget", role: .destructive) { ai.forget() }
                    }
                }
                Picker("Model", selection: $ai.model) {
                    ForEach(ai.models.isEmpty ? [ai.model] : ai.models, id: \.self) { Text(verbatim: $0).tag($0) }
                }
                .task { await ai.loadModels() }
            } else {
                HStack {
                    SecureField("API key", text: $key, prompt: Text(verbatim: "sk-…"))
                        .onSubmit(save)
                    if ai.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save", action: save).disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let error = ai.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        } footer: {
            Group {
                if ai.provider == .gemini {
                    Text("Questions in the AI tab, and what StockBar looks up to answer them (amounts, places, positions), are sent to Google. On Gemini's free tier, Google may use them to improve its products and people may review them; turn on Hide values to send amounts masked. Forget the key to go back to Apple Intelligence.")
                } else if let provider = ai.provider {
                    Text("Questions in the AI tab, and what StockBar looks up to answer them (amounts, places, positions), are sent to \(provider.label) and billed to your key. Forget the key to go back to Apple Intelligence.")
                } else {
                    Text("Works with OpenAI, Anthropic, DeepSeek and Google Gemini keys. Until one is saved, the AI tab uses Apple Intelligence. The key stays in your login keychain.")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let entered = key
        Task {
            await ai.save(key: entered)
            if ai.provider != nil { key = "" }
        }
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
    /// The language in effect from the next launch, as the picker names it.
    static var savedLabel: String {
        switch saved {
        case "en": "English"
        case "pt-BR": "Português (Brasil)"
        default: String(localized: "System language")
        }
    }

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
            Button("Relaunch now") { DataAccount.relaunch() }
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

}
