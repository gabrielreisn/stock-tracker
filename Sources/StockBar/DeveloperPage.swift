import SwiftUI

/// Tools for working on StockBar, in the sidebar of dev builds only (see `Bundle.isDevBuild`).
struct DeveloperPage: View {
    @State private var showOnboarding = false

    var body: some View {
        Form {
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
    }
}
