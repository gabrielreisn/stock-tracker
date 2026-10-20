import ServiceManagement
import SwiftUI

struct SettingsWindow: View {
    @Environment(PortfolioStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var store = store
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

            Section("Menu bar") {
                Picker("Show", selection: $store.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
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
    }
}
