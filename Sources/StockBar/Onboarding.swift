import SwiftUI

/// The setup guide's steps, in order. A new step is a case here, its title and icon, and its page in `OnboardingView`.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome, pluggyAccount, dashboard, openFinance, categories, done
    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .welcome: "Welcome"
        case .pluggyAccount: "Create Pluggy account"
        case .dashboard: "Get dashboard info"
        case .openFinance: "Sync with Open Finance"
        case .categories: "Expense categories"
        case .done: "Done"
        }
    }
}

/// A wizard shown as a sheet: the steps listed down the left, one question or task per page on the right,
/// Back / Continue below. Every step can be skipped; finishing records `onboardingCompleted`.
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PluggyStore.self) private var pluggy
    @Environment(ExpenseStore.self) private var expenses
    @AppStorage("onboardingCompleted") private var completed = false
    @AppStorage("mainSection") private var section: MainSection = .overview
    /// Category names picked on the categories step.
    @State private var pickedCategories: Set<String> = []
    /// Taken when the guide opens: on a fresh install the picks replace the starting set; otherwise the
    /// categories the user already has are shown checked, and picks are added to them.
    @State private var categoryStart: (replacing: Bool, existing: Set<String>)?
    @State private var step = OnboardingStep.welcome
    /// The furthest step reached, so the list can jump back to any of them.
    @State private var reached = OnboardingStep.welcome

    var body: some View {
        HStack(spacing: 0) {
            OnboardingStepper(current: step, reached: reached) { go(to: $0) }
                .padding(10)
                .frame(width: 240)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .padding(12)
            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Divider()
                footer
                    .padding(16)
            }
        }
        .frame(width: 860, height: 580)
        .onAppear {
            guard categoryStart == nil else { return }
            let replacing = expenses.usingDefaultCategories
            let existing = replacing ? [] : Set(ExpenseStore.onboardingCategories.filter(expenses.hasCategory(like:)).map(\.name))
            categoryStart = (replacing, existing)
            pickedCategories = existing
        }
    }

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome:
            OnboardingPage(systemImage: "chart.line.uptrend.xyaxis", title: "Welcome to StockBar",
                           message: "Your stocks, bonds, funds and spending in one place, checked against CDI, IPCA and the market. A few quick steps and you're set.")
        case .pluggyAccount:
            OnboardingPage(systemImage: "person.crop.circle.badge.plus", title: "Create your Meu Pluggy account",
                           message: "Meu Pluggy is a free service that reaches your banks and brokers through Open Finance. Create an account and connect your banks and brokers there; StockBar reads them from it.") {
                Link(destination: URL(string: "https://meu.pluggy.ai")!) {
                    Label("Open meu.pluggy.ai", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        case .dashboard:
            OnboardingPage(systemImage: "key", title: "Get your Client ID and secret",
                           message: "In the Pluggy dashboard, open your application and copy its Client ID and Client Secret. You'll paste them in the next step.") {
                Link(destination: URL(string: "https://dashboard.pluggy.ai")!) {
                    Label("Open the Pluggy dashboard", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        case .openFinance:
            OnboardingPage(systemImage: "building.2", title: "Sync with Open Finance",
                           message: "Paste the Client ID and secret, then connect each bank or broker. Each connection shares one institution from Meu Pluggy; connect again for the next one.") {
                Form { PluggySettingsSection(inOnboarding: true) }
                    .formStyle(.grouped)
                    // A Form inside the page's ScrollView needs a height of its own; more connections scroll inside it.
                    .frame(height: 300)
            }
        case .categories:
            OnboardingPage(systemImage: "square.grid.2x2", title: "What do you spend on?",
                           message: "Pick the kinds of expenses you have. Transactions from your banks are sorted into them, and you can set a monthly limit for each in Categories & limits.") {
                CategoryPicker(picked: $pickedCategories, locked: categoryStart?.existing ?? [])
                    .padding(.top, 8)
            }
        case .done:
            OnboardingPage(systemImage: "checkmark.circle", title: "You're all set",
                           message: "Before relying on the numbers, review everything Open Finance brought in on the Open Finance page: the positions it found, how they were matched to what StockBar tracks, and their average prices.") {
                Button { finish(showing: .openFinance) } label: {
                    Label("Review on the Open Finance page", systemImage: "building.2")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }
        }
    }

    private var footer: some View {
        HStack {
            if step != .done {
                Button("Skip setup") { finish() }
                    .buttonStyle(.link)
            }
            Spacer()
            if step == .openFinance, !canPassOpenFinance {
                Text("Connect at least one bank or broker to continue")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let previous = OnboardingStep(rawValue: step.rawValue - 1) {
                Button("Back") { go(to: previous) }
            }
            if let next = OnboardingStep(rawValue: step.rawValue + 1) {
                Button(step == .welcome ? "Get started" : "Continue") { go(to: next) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == .openFinance && !canPassOpenFinance)
            } else {
                Button("Finish") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// The steps after Open Finance need a connection; "Skip setup" stays available for anyone not ready to connect.
    private var canPassOpenFinance: Bool { !pluggy.itemIDs.isEmpty }

    private func go(to target: OnboardingStep) {
        guard target.rawValue <= OnboardingStep.openFinance.rawValue || canPassOpenFinance else { return }
        if step == .categories, target.rawValue > step.rawValue { saveCategories() }
        withAnimation(.easeInOut(duration: 0.2)) {
            step = target
            if target.rawValue > reached.rawValue { reached = target }
        }
    }

    private func saveCategories() {
        guard let start = categoryStart else { return }
        let picks = ExpenseStore.onboardingCategories.filter { pickedCategories.contains($0.name) }
        // Nothing picked on a fresh install: keep the starting set rather than leave no categories at all.
        guard !picks.isEmpty || !start.replacing else { return }
        expenses.adoptCategories(picks, replacingDefaults: start.replacing)
    }

    private func finish(showing destination: MainSection? = nil) {
        completed = true
        if let destination { section = destination }
        dismiss()
    }

    /// True only on a first launch: the guide was never finished or skipped, and nothing has been saved yet.
    /// Someone upgrading from a version without the guide already has data, so they're marked done instead.
    static func shouldStartOnLaunch() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "onboardingCompleted") == nil else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: PortfolioStore.directory.path)) ?? []
        let hasData = files.contains { $0.hasSuffix(".json") && !$0.hasSuffix("-cache.json") }
            || !(defaults.string(forKey: "pluggyClientId") ?? "").isEmpty
        if hasData { defaults.set(true, forKey: "onboardingCompleted") }
        return !hasData
    }
}

/// The steps as a list: done ones show a check, the current one is outlined (the outline slides between rows),
/// and any step already reached can be clicked.
private struct OnboardingStepper: View {
    var current: OnboardingStep
    var reached: OnboardingStep
    var select: (OnboardingStep) -> Void
    @Namespace private var highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(OnboardingStep.allCases) { step in
                Button { select(step) } label: {
                    HStack(spacing: 10) {
                        badge(step)
                        Text(step.title)
                            .foregroundStyle(step.rawValue <= reached.rawValue ? .primary : .secondary)
                            .fontWeight(step == current ? .semibold : .regular)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if step == current {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                                .matchedGeometryEffect(id: "current", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(step.rawValue > reached.rawValue)
            }
        }
    }

    private func badge(_ step: OnboardingStep) -> some View {
        ZStack {
            Circle()
                .fill(step == current ? Color.accentColor : step.rawValue < current.rawValue ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12))
            if step.rawValue < current.rawValue {
                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Color.accentColor)
            } else {
                Text(verbatim: "\(step.rawValue + 1)").font(.caption.bold().monospacedDigit())
                    .foregroundStyle(step == current ? Color.white : .secondary)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// The guide's category options as tiles: an icon in a rounded square with the name below; picked ones are
/// outlined like the current step. Categories the user already has stay checked.
private struct CategoryPicker: View {
    @Binding var picked: Set<String>
    var locked: Set<String>

    private let columns = Array(repeating: GridItem(.fixed(84), spacing: 6, alignment: .top), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(ExpenseStore.onboardingCategories) { category in
                tile(category)
            }
        }
    }

    private func tile(_ category: ExpenseCategory) -> some View {
        let isPicked = picked.contains(category.name)
        let isLocked = locked.contains(category.name)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isPicked { picked.remove(category.name) } else { picked.insert(category.name) }
            }
        } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isPicked ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    .strokeBorder(isPicked ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isPicked ? 1.5 : 1)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: category.symbol)
                            .font(.system(size: 24))
                            .foregroundStyle(isPicked ? Color.accentColor : .primary)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isPicked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, Color.accentColor)
                                .offset(x: 6, y: -6)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(category.name)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isPicked ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .help(isLocked ? String(localized: "Already in your categories") : "")
    }
}

/// One step's page: an icon, a heading, a line of explanation and whatever the step asks for.
private struct OnboardingPage<Content: View>: View {
    var systemImage: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        // Centered in the page while it fits; taller content scrolls from the top.
        GeometryReader { proxy in
            ScrollView {
                column
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    private var column: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundStyle(Color.accentColor)
            Text(title).font(.title2.bold())
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
                .frame(maxWidth: 540)
        }
        .padding(24)
    }
}

private extension OnboardingPage where Content == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey?) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}
