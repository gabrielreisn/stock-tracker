import SwiftUI

/// Tools for working on StockBar, in the sidebar of dev builds only (see `Bundle.isDevBuild`).
struct DeveloperPage: View {
    @State private var showOnboarding = false
    @State private var pendingAccount: DataAccount?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Picker("Data", selection: Binding(get: { DataAccount.current }, set: { pendingAccount = $0 == DataAccount.current ? nil : $0 })) {
                    Text("Personal").tag(DataAccount.personal)
                    Text("Demo").tag(DataAccount.demo)
                }
                .pickerStyle(.segmented)
                if DataAccount.current == .demo {
                    LabeledContent("Demo data") {
                        Button("Reset") { confirmReset = true }
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Demo runs on made-up data (a portfolio, bonds, funds and two years of spending), kept apart from yours and never connected to Open Finance, for showing the app. Its spending moves to the current month every month. Switching relaunches StockBar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Setup guide") {
                    Button("Launch") { showOnboarding = true }
                }
            } header: {
                Text("Onboarding")
            } footer: {
                Text("Shown only in dev builds: ones made with build.sh outside GitHub Actions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .alert(pendingAccount == .demo ? "Switch to the demo account?" : "Switch to your personal account?",
               isPresented: Binding(get: { pendingAccount != nil }, set: { if !$0 { pendingAccount = nil } })) {
            Button("Relaunch") { if let pendingAccount { DataAccount.switchTo(pendingAccount) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("StockBar relaunches with the other account's data. Nothing in either account is changed.")
        }
        .alert("Reset the demo data?", isPresented: $confirmReset) {
            Button("Reset and relaunch", role: .destructive) { DataAccount.resetDemo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Changes made in the demo account are replaced by the original made-up data.")
        }
    }
}
