import SwiftUI

struct SettingsScreen: View {
    @Environment(PortfolioStore.self) private var portfolio
    var body: some View {
        CymbaPage(spacing: 24) {
            CymbaRootTitle(title: "Settings", identifier: "settings-title")
            VStack(alignment: .leading, spacing: 8) {
                CymbaHeading(title: "Benchmarks")
                VStack(spacing: 0) {
                    ForEach(BenchmarkID.allCases) { b in
                        if b != BenchmarkID.allCases.first { Divider().overlay(CymbaTheme.selected).padding(.leading, 16) }
                        HStack(alignment: .top, spacing: 16) {
                            HStack(spacing: 2) { RoundedRectangle(cornerRadius: 1.5).fill(b.color); if b.isRate { RoundedRectangle(cornerRadius: 1.5).fill(b.color) } }.frame(width: 14, height: 3).padding(.top, 10)
                            Toggle(isOn: Binding(get: { portfolio.enabledBenchmarks.contains(b) }, set: { portfolio.setBenchmark(b, enabled: $0) })) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.label).font(.system(size: 16))
                                    Text(b.detail).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.tint(CymbaTheme.accent)
                                .disabled(!portfolio.enabledBenchmarks.contains(b) && portfolio.enabledBenchmarks.count >= BenchmarkID.maxEnabled)
                        }.padding(16)
                    }
                }.background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                CymbaCaption(text: "Up to 3 at a time, so every line stays distinguishable. Rate-based ones are drawn dashed.").padding(.horizontal, 4)
            }
            ConnectionSettingsGroup()
            VStack(alignment: .leading, spacing: 12) {
                CymbaHeading(title: "More")
                CymbaDestination(title: "AI") { ChatScreen() }
                CymbaDestination(title: "Fund Comparison") { ComparisonScreen() }
                CymbaDestination(title: "Price alerts") { PriceAlertsScreen() }
                CymbaDestination(title: "Appearance") { AppearanceScreen() }
            }
        }.toolbar(.hidden, for: .navigationBar)
    }
}

struct AppearanceScreen: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("appLanguage") private var language = "system"
    var body: some View {
        Form {
            Picker("Theme", selection: $theme) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            Picker("Language", selection: $language) { Text("System").tag("system"); Text("English").tag("en"); Text("Português").tag("pt-BR") }
                .onChange(of: language) { _, value in
                    if value == "system" { UserDefaults.standard.removeObject(forKey: "AppleLanguages") }
                    else { UserDefaults.standard.set([value], forKey: "AppleLanguages") }
                }
            CymbaCaption(text: "Restart the app after changing the language.")
            PrivacyButton()
            Section("About") {
                Text("Cymba Native for iPhone").font(.headline)
                CymbaCaption(text: "Your portfolio and expenses are stored on this device. Credentials are stored in Keychain. Market data comes from Yahoo Finance, Banco Central, B3 and CVM.")
            }
        }.cymbaList().tint(CymbaTheme.accent).cymbaNavigationTitle("Appearance")
    }
}

struct ConnectionSettingsGroup: View {
    @Environment(PluggyStore.self) private var pluggy
    @Environment(AppModel.self) private var app
    @State private var clientID = ""
    @State private var secret = ""
    @State private var connecting = false
    @State private var updating: String?
    @State private var removing: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CymbaHeading(title: "Open Finance")
            VStack(alignment: .leading, spacing: 0) {
                if !pluggy.isConfigured {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect your banks with Meu Pluggy").font(.system(size: 16, weight: .semibold))
                        CymbaCaption(text: "Use your own Pluggy application to connect banks and brokers. Your credentials stay on this device.")
                        Link("Open Meu Pluggy", destination: URL(string: "https://meu.pluggy.ai")!).foregroundStyle(CymbaTheme.link)
                    }.padding(16)
                    Divider().padding(.leading, 16)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Client ID").font(.system(size: 16))
                    TextField("Client ID", text: $clientID).textFieldStyle(CymbaInputStyle(inset: true)).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                }.padding(16)
                Divider().padding(.leading, 16)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Client secret").font(.system(size: 16))
                    SecureField(pluggy.hasSecret ? "Saved in secure storage" : "Client secret", text: $secret).textFieldStyle(CymbaInputStyle(inset: true))
                    Button("Save credentials") { pluggy.clientId = clientID.trimmingCharacters(in: .whitespacesAndNewlines); pluggy.saveSecret(secret); secret = "" }
                        .buttonStyle(CymbaActionStyle()).disabled(clientID.isEmpty || secret.isEmpty)
                }.padding(16)
                ForEach(pluggy.itemIDs, id: \.self) { id in
                    Divider().padding(.leading, 16)
                    HStack(spacing: 8) {
                        Circle().fill(pluggy.needsReconnect(id) ? CymbaTheme.warning : CymbaTheme.success).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pluggy.institutions(of: id) ?? "Connection").font(.system(size: 16))
                            Text(Privacy.isOn ? Privacy.mask : id).font(.system(size: 13)).lineLimit(1).foregroundStyle(CymbaTheme.secondary)
                        }
                        Spacer()
                        Button("Reconnect") { updating = id; connecting = true }.font(.system(size: 14)).foregroundStyle(CymbaTheme.link)
                        Button { removing = id } label: { Image(systemName: "minus.circle").foregroundStyle(CymbaTheme.secondary) }.accessibilityLabel("Remove")
                    }.padding(16)
                }
                Divider().padding(.leading, 16)
                VStack(spacing: 8) {
                    Button("Connect a bank or broker") { updating = nil; connecting = true }.buttonStyle(CymbaActionStyle(primary: true)).disabled(!pluggy.isConfigured)
                    Button("Sync now") { Task { await app.sync(force: true) } }.buttonStyle(CymbaActionStyle()).disabled(!pluggy.isConfigured || pluggy.itemIDs.isEmpty || pluggy.isSyncing)
                    if pluggy.isSyncing { ProgressView() }
                    if let error = pluggy.error { Text(error).font(.system(size: 13)).foregroundStyle(CymbaTheme.warning) }
                    if let date = pluggy.lastSync { Text(date, style: .relative).font(.system(size: 13)).foregroundStyle(CymbaTheme.secondary) }
                }.padding(16)
            }.background(CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            CymbaCaption(text: "Your client secret stays in secure storage on this device and only leaves it to sign in to Pluggy. Meu Pluggy consent lasts a year; when it lapses, use Reconnect.").padding(.horizontal, 4)
        }
        .onAppear { clientID = pluggy.clientId }
        .sheet(isPresented: $connecting) { BankConnectScreen(updating: updating) }
        .confirmationDialog("Remove this connection from Cymba?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) { if let id = removing { pluggy.removeItem(id) }; removing = nil }
        }
    }
}

struct AISettingsScreen: View {
    @Environment(AIAccount.self) private var account
    @Environment(LocalModel.self) private var local
    @State private var key = ""
    @AppStorage("ollamaServer") private var server = "http://localhost:11434"
    var body: some View {
        @Bindable var account = account
        @Bindable var local = local
        Form {
            Picker("Engine", selection: $account.engine) { Text("Apple Intelligence").tag(AIEngine.apple); Text("Cloud").tag(AIEngine.cloud); Text("Ollama server").tag(AIEngine.local) }
            Section("Apple Intelligence") { Text("Requires iOS 26, a compatible iPhone and Apple Intelligence enabled in Settings. Queries run on the device.").font(.caption) }
            Section("Cloud") {
                SecureField("API key", text: $key).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button("Save key") { Task { await account.save(key: key); key = "" } }.disabled(key.isEmpty || account.isChecking)
                if account.isChecking { ProgressView() }
                if let provider = account.provider { Text(provider.label) }
                if !account.models.isEmpty { Picker("Model", selection: $account.model) { ForEach(account.models, id: \.self) { Text($0).tag($0) } } }
                if let error = account.error { Text(error).foregroundStyle(.orange) }
                Text("Your questions and the results of read-only financial queries are sent to the selected provider.").font(.caption).foregroundStyle(CymbaTheme.secondary)
                Button("Remove API key", role: .destructive) { account.forget() }
            }
            Section("Ollama server") {
                TextField("Server URL", text: $server).keyboardType(.URL).autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Enter the address of an Ollama server on your network. Ollama runs on your computer; keep this server on a trusted network.").font(.caption).foregroundStyle(CymbaTheme.secondary)
                Button("Refresh models") { Task { await local.refresh() } }
                if !local.models.isEmpty { Picker("Model", selection: $local.model) { ForEach(local.models, id: \.name) { Text($0.name).tag($0.name) } } }
                if !local.isReady { Text("No tool-capable model is available from this server.").font(.caption).foregroundStyle(.orange) }
            }
        }.cymbaList().cymbaNavigationTitle("AI settings").task { await account.loadModels() }
    }
}

struct ChatScreen: View {
    @AppStorage(Privacy.key) private var hidden = false
    @Environment(AIChat.self) private var chat
    @State private var prompt = ""
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if chat.messages.isEmpty {
                        ContentUnavailableView("Ask about your money", systemImage: "sparkles", description: Text("Ask about spending, holdings, returns or upcoming bills."))
                    }
                    ForEach(chat.messages) { message in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(message.role == .user ? "You" : "Cymba").font(.caption.bold()).foregroundStyle(CymbaTheme.secondary)
                            if hidden { Text(Privacy.mask) } else { Text(message.text.isEmpty ? "…" : message.text).textSelection(.enabled).foregroundStyle(message.failed ? CymbaTheme.danger : CymbaTheme.text) }
                            if !hidden && !message.lookups.isEmpty {
                                DisclosureGroup("What the assistant looked up") {
                                    ForEach(Array(message.lookups.enumerated()), id: \.offset) { _, lookup in
                                        Text(lookup.label).font(.caption.bold())
                                        Text(lookup.output).font(.caption).textSelection(.enabled)
                                    }
                                }.font(.caption)
                            }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading)
                            .background(message.role == .user ? CymbaTheme.accent.opacity(0.12) : CymbaTheme.surface, in: RoundedRectangle(cornerRadius: 16)).id(message.id)
                    }
                    if chat.isResponding { ProgressView() }
                }.padding()
            }.onChange(of: chat.messages.last?.text) { if let id = chat.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if case .unavailable(let reason) = chat.availability { Text(reason).font(.caption).foregroundStyle(.orange) }
                HStack(alignment: .bottom) {
                    TextField("Ask a question", text: $prompt, axis: .vertical).lineLimit(1...6).textFieldStyle(.roundedBorder)
                    if chat.isResponding { Button("Stop") { chat.stop() } }
                    else { Button { chat.send(prompt); prompt = "" } label: { Label("Send", systemImage: "arrow.up.circle.fill").labelStyle(.iconOnly).font(.title) }.disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.availability != .available) }
                }
            }.padding().background(.bar)
        }
        .cymbaNavigationTitle("AI")
        .toolbar {
            Button { chat.reset() } label: { Label("New conversation", systemImage: "square.and.pencil") }.disabled(chat.isResponding)
            NavigationLink { AISettingsScreen() } label: { Label("AI settings", systemImage: "gearshape") }
        }
        .onDisappear { chat.releaseLocalModel() }
    }
}
