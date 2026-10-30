import NaturalLanguage
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A conversation about the user's data. With an API key in Settings → AI it goes to that provider's model
/// (see AIProviders.swift); without one, to Apple Intelligence's on-device model (Foundation Models, macOS 26),
/// which is free and private. Either reads the app's data through the same tools (`AIToolbox`). Kept for the
/// whole app, so switching pages doesn't lose it.
@MainActor
@Observable
final class AIChat {
    struct Message: Identifiable, Equatable {
        enum Role { case user, assistant }
        let id = UUID()
        var role: Role
        var text: String
        var failed = false
        /// What the model looked up to answer, so the user can tell an answer from a guess.
        var lookups: [Lookup] = []
        var timing: Timing?
    }

    /// Where an answer's time went. On-device, the model reads everything before it writes (the rules, the tools
    /// and each tool's answer), and that reading is the slow part: about 50 tokens a second on an M1 Max.
    struct Timing: Equatable {
        enum Kind {
            /// On-device: from sending to the first tool call, or to the first word when no tool is used.
            case thinking
            /// Running the tools: StockBar's own queries, including fetching a month from Open Finance.
            case lookup
            /// On-device: from the last tool's answer to the first word, the model reading what the tools returned.
            case reading
            /// On-device: from the first word to the last.
            case writing
            /// One request to a model's API (a cloud provider, or Ollama on this Mac), from sending it to its whole
            /// reply. With Ollama, the first one also loads the model.
            case model
        }
        struct Phase: Equatable {
            var kind: Kind
            var seconds: Double
        }
        var phases: [Phase]
        var total: Double
    }

    /// The answer in progress: timestamps for the on-device model, steps in order for a cloud one.
    private struct Clock {
        var start = Date.now
        var firstTool: Date?
        var lastTool: Date?
        var lookup = 0.0
        var firstWord: Date?
        var steps: [Timing.Phase] = []

        mutating func add(_ kind: Timing.Kind, _ seconds: Double) {
            // Tools called in the same round count as one lookup.
            if kind == .lookup, steps.last?.kind == .lookup { steps[steps.count - 1].seconds += seconds }
            else { steps.append(Timing.Phase(kind: kind, seconds: seconds)) }
        }

        func timing(end: Date) -> Timing {
            let total = end.timeIntervalSince(start)
            if !steps.isEmpty { return Timing(phases: steps, total: total) }
            let firstWord = firstWord ?? end
            var phases = [Timing.Phase(kind: .thinking, seconds: (firstTool ?? firstWord).timeIntervalSince(start))]
            if let lastTool {
                phases += [Timing.Phase(kind: .lookup, seconds: lookup), Timing.Phase(kind: .reading, seconds: firstWord.timeIntervalSince(lastTool))]
            }
            phases.append(Timing.Phase(kind: .writing, seconds: end.timeIntervalSince(firstWord)))
            return Timing(phases: phases, total: total)
        }
    }

    struct Lookup: Equatable {
        var label: String
        /// The tool's answer as the model read it; shown in dev builds, to debug the harness.
        var output: String
    }

    enum Availability: Equatable {
        case available
        /// Why it can't run, for the user.
        case unavailable(String)
    }

    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    /// A `LanguageModelSession`, untyped so the class builds for macOS 15.
    @ObservationIgnored private var session: AnyObject?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// The assistant message being answered, for the tools' notes.
    @ObservationIgnored private var answering: Int?
    @ObservationIgnored private var clock = Clock()
    /// The conversation with the API behind the cloud or local engine.
    @ObservationIgnored private var cloud: AICloudConversation?
    @ObservationIgnored private var unloadWhenDone = false
    private let data: AIData
    let account: AIAccount
    let local: LocalModel

    init(data: AIData, account: AIAccount, local: LocalModel) {
        self.data = data
        self.account = account
        self.local = local
    }

    /// The engine that answers: the one chosen in Settings → AI, or Apple Intelligence until it's set up
    /// (no key yet, Ollama not running or without the model).
    var activeEngine: AIEngine {
        switch account.engine {
        case .cloud where account.isConfigured: .cloud
        case .local where local.isReady: .local
        default: .apple
        }
    }

    /// Which model answers, for the page header.
    var engineLabel: String {
        switch activeEngine {
        case .cloud: "\(account.provider?.label ?? "") · \(account.model)"
        case .local: "\(local.model) · " + String(localized: "on this Mac")
        case .apple: String(localized: "Apple Intelligence · on this Mac")
        }
    }

    var availability: Availability {
        if activeEngine != .apple { return .available }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(String(localized: "Apple Intelligence needs a Mac with Apple silicon."))
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(String(localized: "Turn on Apple Intelligence in System Settings → Apple Intelligence & Siri."))
            case .unavailable(.modelNotReady):
                return .unavailable(String(localized: "Apple Intelligence is still downloading its model. Try again in a few minutes."))
            case .unavailable:
                return .unavailable(String(localized: "Apple Intelligence isn't available on this Mac right now."))
            }
        }
        #endif
        return .unavailable(String(localized: "Apple Intelligence needs macOS 26 or later."))
    }

    func send(_ prompt: String) {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        messages.append(Message(role: .user, text: prompt))
        messages.append(Message(role: .assistant, text: ""))
        let index = messages.count - 1
        isResponding = true
        answering = index
        clock = Clock()
        task = Task {
            defer {
                if messages.indices.contains(index) { messages[index].timing = clock.timing(end: .now) }
                isResponding = false
                answering = nil
            }
            switch activeEngine {
            case .cloud:
                guard let provider = account.provider, let key = account.key else {
                    fail(index, String(localized: "StockBar couldn't read the API key from the Keychain. Enter it again in Settings → AI."))
                    return
                }
                await ask(provider, model: account.model, key: key, prompt + Self.languageHint(prompt), at: index)
                return
            case .local:
                await ask(.ollama, model: local.model, key: "", skipThinking: local.selected?.thinks ?? false, prompt + Self.languageHint(prompt), at: index)
                if unloadWhenDone { unloadWhenDone = false; local.unload() }
                return
            case .apple: break
            }
            #if canImport(FoundationModels)
            if #available(macOS 26, *) {
                do {
                    do {
                        try await respond(to: prompt + Self.languageHint(prompt), at: index)
                    } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
                        // The model holds about 4.000 tokens, tool answers included: ask again in a fresh
                        // conversation rather than get stuck. Earlier questions are forgotten.
                        session = nil
                        messages[index].text = ""
                        messages[index].lookups = []
                        try await respond(to: prompt + Self.languageHint(prompt), at: index)
                    }
                } catch is CancellationError {
                } catch let error as LanguageModelSession.GenerationError {
                    if case .exceededContextWindowSize = error { session = nil }
                    fail(index, Self.message(for: error), detail: String(describing: error))
                } catch {
                    fail(index, error.localizedDescription, detail: String(describing: error))
                }
                return
            }
            #endif
            fail(index, String(localized: "Apple Intelligence needs macOS 26 or later."))
        }
    }

    /// Small models drift into the language of their rules and tool results (English) when asked in Portuguese,
    /// or the other way round; naming the question's language at the end of it keeps them on track.
    /// Sent to the model only, not shown in the chat.
    private static func languageHint(_ prompt: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.portuguese, .english]
        recognizer.processString(prompt)
        return switch recognizer.dominantLanguage {
        case .portuguese?: "\n\n(Reply in Portuguese.)"
        case .english?: "\n\n(Reply in English.)"
        default: ""
        }
    }

    /// Asks a model behind an API (a cloud provider, or Ollama for the local engine), which runs StockBar's tools
    /// and answers.
    private func ask(_ provider: AIProvider, model: String, key: String, skipThinking: Bool = false, _ prompt: String, at index: Int) async {
        // A new conversation when the provider or model changed: each keeps its own format.
        if cloud == nil || cloud?.provider != provider || cloud?.model != model {
            cloud = AICloudConversation(provider: provider, model: model, key: key, skipThinking: skipThinking)
        }
        do {
            messages[index].text = try await cloud!.ask(prompt, system: AIRules.instructions, data: data,
                note: { label, output, seconds in noteLookup(Lookup(label: label, output: output), seconds: seconds, step: true) },
                phase: { clock.add(.model, $0) })
            if messages[index].text.isEmpty { fail(index, String(localized: "The model's answer was empty.")) }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch let error as URLError where provider == .ollama && [.cannotConnectToHost, .networkConnectionLost].contains(error.code) {
            fail(index, String(localized: "Ollama isn't running. Open it, then ask again."), detail: String(describing: error))
        } catch {
            fail(index, error.localizedDescription, detail: String(describing: error))
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func respond(to prompt: String, at index: Int) async throws {
        let session = (session as? LanguageModelSession) ?? LanguageModelSession(
            tools: AITools.all(data) { [weak self] in self?.noteLookup(Lookup(label: $0, output: $1), seconds: $2) },
            instructions: AIRules.instructions)
        self.session = session
        for try await snapshot in session.streamResponse(to: prompt) {
            if clock.firstWord == nil, !snapshot.content.isEmpty { clock.firstWord = .now }
            messages[index].text = snapshot.content
        }
    }

    /// What went wrong, in words; the framework's own descriptions are often just "error -1".
    @available(macOS 26, *)
    private static func message(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize:
            String(localized: "This question needs more than the on-device model can hold. Try a shorter period or a narrower question.")
        case .guardrailViolation, .refusal:
            String(localized: "Apple Intelligence declined to answer that. Try rephrasing the question.")
        case .unsupportedLanguageOrLocale:
            String(localized: "Apple Intelligence doesn't support this language yet.")
        case .assetsUnavailable:
            String(localized: "Apple Intelligence's model isn't available right now. Try again in a few minutes.")
        case .rateLimited, .concurrentRequests:
            String(localized: "Apple Intelligence is busy. Try again in a moment.")
        case .decodingFailure, .unsupportedGuide:
            String(localized: "The model gave an answer StockBar couldn't read. Try asking again.")
        @unknown default:
            String(localized: "Apple Intelligence couldn't answer. Try asking again.")
        }
    }
    #endif

    private func noteLookup(_ lookup: Lookup, seconds: Double, step: Bool = false) {
        if step { clock.add(.lookup, seconds) }
        let now = Date.now
        clock.firstTool = min(clock.firstTool ?? now, now.addingTimeInterval(-seconds))
        clock.lastTool = now
        clock.lookup += seconds
        guard let answering, messages.indices.contains(answering), !messages[answering].lookups.contains(lookup) else { return }
        messages[answering].lookups.append(lookup)
    }

    func stop() { task?.cancel() }

    /// The AI tab was left: free the local model's memory, after the answer being written, if there is one.
    func releaseLocalModel() {
        if isResponding, activeEngine == .local { unloadWhenDone = true } else { local.unload() }
    }

    func reset() {
        task?.cancel()
        messages = []
        session = nil
        cloud = nil
    }

    /// Shows `text` in the answer; dev builds add the raw error, to tell the cases apart.
    private func fail(_ index: Int, _ text: String, detail: String? = nil) {
        guard messages.indices.contains(index) else { return }
        let text = Bundle.main.isDevBuild && detail != nil ? text + "\n(\(detail!))" : text
        if messages[index].text.isEmpty { messages[index].text = text } else { messages[index].text += "\n\n" + text }
        messages[index].failed = true
    }
}

struct AIPage: View {
    let chat: AIChat
    @State private var draft = ""
    @FocusState private var focused: Bool

    /// The conversation and the composer share one centered column.
    private static let columnWidth: CGFloat = 760

    private static var suggestions: [String] {
        [String(localized: "How many times did I take an Uber this month?"),
         String(localized: "Where did my money go last month?"),
         String(localized: "How is my portfolio doing today?")]
    }

    var body: some View {
        VStack(spacing: 0) {
            // No page title: the sidebar already says where this is. Engine and New chat sit in the window's corner.
            Divider()
            switch chat.availability {
            case .available:
                conversation
                composer
            case .unavailable(let reason):
                ContentUnavailableView {
                    Label("Apple Intelligence unavailable", systemImage: "sparkles")
                } description: {
                    Text(reason)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar { AIToolbar(chat: chat) { focused = true } }
        .onAppear { focused = true }
        // The local model holds about 1 GB while loaded; it reloads in about half a second.
        .task { await chat.local.refresh() }
        .onDisappear { chat.releaseLocalModel() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty { welcome }
                    ForEach(chat.messages) { bubble($0).id($0.id) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.vertical, PageLayout.padding)
                .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.8, Self.columnWidth) }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: chat.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: chat.messages.count) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 34)).foregroundStyle(.tint)
            Text("Ask about your portfolio and expenses").font(.title3.weight(.semibold))
            Group {
                if chat.activeEngine == .local {
                    Text("Answers come from \(chat.local.model), running on this Mac: free, and neither your questions nor your data leave it. Check the figures it looked up under each answer.")
                } else if chat.activeEngine == .cloud, let provider = chat.account.provider {
                    Text("Answers come from \(provider.label), with your API key. Your question and what StockBar looks up to answer it (amounts, places, positions) are sent to \(provider.label). Check the figures it looked up under each answer.")
                } else {
                    Text("Answers come from Apple Intelligence, on this Mac: free, and neither your questions nor your data leave it. It reads what StockBar has; check the figures it looked up under each answer.")
                }
            }
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button { send(suggestion) } label: {
                        Text(suggestion)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func bubble(_ message: AIChat.Message) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.lookups.indices, id: \.self) { i in
                let lookup = message.lookups[i]
                if Bundle.main.isDevBuild {
                    DisclosureGroup {
                        Text(lookup.output).font(.caption.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    } label: {
                        Label(lookup.label, systemImage: "magnifyingglass")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label(lookup.label, systemImage: "magnifyingglass")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("What the assistant looked up in StockBar to answer")
                }
            }
            bubbleText(message)
            if let timing = message.timing { timingLine(timing) }
        }
    }

    /// Inline markdown (bold, italics) keeps list markers as typed; "* " and "- " at a line's start become bullets.
    private static func bullets(_ text: String) -> String {
        text.replacingOccurrences(of: #"(?m)^(\s*)[*-] "#, with: "$1• ", options: .regularExpression)
    }

    private func timingLine(_ t: AIChat.Timing) -> some View {
        func seconds(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) + " s" }
        let parts = t.phases.map { phase in
            switch phase.kind {
            case .thinking: String(localized: "thinking \(seconds(phase.seconds))")
            case .lookup: String(localized: "lookup \(seconds(phase.seconds))")
            case .reading: String(localized: "reading \(seconds(phase.seconds))")
            case .writing: String(localized: "writing \(seconds(phase.seconds))")
            case .model: String(localized: "model \(seconds(phase.seconds))")
            }
        }
        return Label(seconds(t.total) + "  ·  " + parts.joined(separator: " · "), systemImage: "clock")
            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            .help("Thinking: deciding what to look up. Lookup: StockBar's queries. Reading: the model reading what they returned. Writing: the answer itself. Model: one request to the model, in the cloud or in Ollama on this Mac.")
    }
    private func bubbleText(_ message: AIChat.Message) -> some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 80) }
            Group {
                if message.text.isEmpty {
                    ProgressView().controlSize(.small).padding(.vertical, 2)
                } else if message.role == .assistant, let markdown = try? AttributedString(markdown: Self.bullets(message.text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                    Text(markdown)
                } else {
                    Text(message.text)
                }
            }
            .textSelection(.enabled)
            .foregroundStyle(message.failed ? AnyShapeStyle(.orange) : message.role == .user ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.role == .user ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: RoundedRectangle(cornerRadius: 12))
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 10) {
            TextField("Ask anything", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...6)
                .focused($focused)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14).padding(.vertical, 13)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            if chat.isResponding {
                Button { chat.stop() } label: { Image(systemName: "stop.circle.fill").font(.system(size: 30)) }
                    .buttonStyle(.plain)
                    .help("Stop")
            } else {
                Button { send(draft) } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Send (⌘↩)")
            }
        }
        // At least 10% of the page on each side, and never wider than the conversation above it.
        .containerRelativeFrame(.horizontal) { width, _ in min(width * 0.8, Self.columnWidth) }
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    private func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        chat.send(text)
        draft = ""
    }
}

/// The engine in use on the left, New chat in the window's top-right corner: plain text and a borderless button
/// (macOS 26 would otherwise wrap them in a glass capsule). New chat is always there, greyed out until there's a
/// conversation to clear.
private struct AIToolbar: ToolbarContent {
    let chat: AIChat
    let onReset: () -> Void

    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .automatic) { engine }.sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) { newChat }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .automatic) { engine }
            ToolbarItem(placement: .primaryAction) { newChat }
        }
    }

    private var engine: some View {
        Text(chat.engineLabel).font(.caption).foregroundStyle(.secondary)
            .padding(.leading, 24)
            .help("Change it in Settings → AI")
    }

    private var newChat: some View {
        let enabled = !chat.messages.isEmpty
        return Button { chat.reset(); onReset() } label: {
            HStack(spacing: 6) {
                Text("New chat")
                Image(systemName: "square.and.pencil")
            }
            .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.borderless)
        .padding(.trailing, 24)
        .disabled(!enabled)
        .help("Start a new conversation")
    }
}
