import Foundation

/// A model behind an HTTP API: a cloud model the user brings their own API key for, or Ollama on this Mac (the local
/// engine, no key). OpenAI, DeepSeek, Gemini and Ollama (through their OpenAI-compatible endpoints) share the Chat
/// Completions format; Anthropic has its own Messages API. Without either, the AI tab runs Apple Intelligence.
enum AIProvider: String, CaseIterable {
    case openAI, anthropic, deepSeek, gemini, ollama

    var label: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .deepSeek: "DeepSeek"
        case .gemini: "Google Gemini"
        case .ollama: "Ollama"
        }
    }

    fileprivate var modelsURL: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/models")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/models?limit=100")!
        case .deepSeek: URL(string: "https://api.deepseek.com/models")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/models")!
        case .ollama: LocalModel.server.appendingPathComponent("v1/models")
        }
    }

    fileprivate var chatURL: URL {
        switch self {
        case .openAI: URL(string: "https://api.openai.com/v1/chat/completions")!
        case .anthropic: URL(string: "https://api.anthropic.com/v1/messages")!
        case .deepSeek: URL(string: "https://api.deepseek.com/chat/completions")!
        case .gemini: URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .ollama: LocalModel.server.appendingPathComponent("v1/chat/completions")
        }
    }

    fileprivate func authorize(_ request: inout URLRequest, key: String) {
        if self == .ollama { return }
        if self == .anthropic {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        } else {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
    }

    /// The models worth offering for a chat, best default first.
    fileprivate func chatModels(_ ids: [String]) -> [String] {
        switch self {
        case .anthropic:
            let claude = ids.filter { $0.hasPrefix("claude-") }
            return (claude.contains("claude-opus-5-5") ? ["claude-opus-5-5"] : []) + claude.filter { $0 != "claude-opus-5-5" }
        case .deepSeek:
            return ids.sorted { a, _ in a == "deepseek-chat" }
        case .gemini:
            let skip = ["image", "embedding", "tts", "audio", "live", "vision", "aqa", "imagen", "veo", "learnlm", "gemma"]
            let chat = ids.map { $0.replacingOccurrences(of: "models/", with: "") }
                .filter { id in id.hasPrefix("gemini-") && !skip.contains { id.contains($0) } }
                .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            // The newest stable Flash: fast, and on the free tier.
            let preferred = chat.first { $0.range(of: #"^gemini-[\d.]+-flash$"#, options: .regularExpression) != nil }
                ?? chat.first { $0.contains("flash") }
            return (preferred.map { [$0] } ?? []) + chat.filter { $0 != preferred }
        case .openAI:
            let skip = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "dall-e", "whisper", "codex", "instruct"]
            let chat = ids.filter { id in id.hasPrefix("gpt-") && !skip.contains { id.contains($0) } }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            // The newest "mini": cheap, fast and good at tool calls.
            let preferred = chat.first { $0.range(of: #"^gpt-\d+(\.\d+)?-mini$"#, options: .regularExpression) != nil }
                ?? chat.first { $0 == "gpt-4o-mini" }
            return (preferred.map { [$0] } ?? []) + chat.filter { $0 != preferred }
        case .ollama:
            return ids
        }
    }
}

/// Which model answers in the AI tab, as chosen in Settings → AI.
enum AIEngine: String, CaseIterable {
    /// Apple Intelligence: on the Mac, free; needs macOS 26 and Apple silicon.
    case apple
    /// Qwen 3.8 through Ollama (`LocalModel`): on the Mac, free, once Ollama and the model are installed.
    case local
    /// The user's own API key.
    case cloud
}

/// The engine choice, and the user's own API key (one field for every provider): which provider it belongs to
/// and the model to use.
@MainActor
@Observable
final class AIAccount {
    var engine: AIEngine { didSet { UserDefaults.standard.set(engine.rawValue, forKey: "aiEngine") } }
    private static let keychainService = "StockBar AI"
    private static let keychainAccount = "api-key"

    private(set) var provider: AIProvider? { didSet { UserDefaults.standard.set(provider?.rawValue, forKey: "aiProvider") } }
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "aiModel") } }
    private(set) var models: [String] = []
    private(set) var isChecking = false
    private(set) var error: String?
    /// Read from the Keychain on first use, then kept for the rest of the launch.
    @ObservationIgnored private var cachedKey: String?

    init() {
        let saved = UserDefaults.standard.string(forKey: "aiProvider").flatMap(AIProvider.init)
        let configured = saved != nil && Keychain.hasSecret(for: Self.keychainAccount, service: Self.keychainService) ? saved : nil
        engine = UserDefaults.standard.string(forKey: "aiEngine").flatMap(AIEngine.init) ?? (configured != nil ? .cloud : .apple)
        provider = configured
        model = UserDefaults.standard.string(forKey: "aiModel") ?? ""
    }

    var isConfigured: Bool { provider != nil && !model.isEmpty }

    var key: String? {
        if cachedKey == nil { cachedKey = Keychain.secret(for: Self.keychainAccount, service: Self.keychainService) }
        return cachedKey
    }

    /// Finds which provider the key belongs to by asking each for its models, then keeps the key and a default model.
    func save(key: String) async {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isChecking = true
        error = nil
        defer { isChecking = false }
        // Anthropic and Google keys say whose they are; OpenAI and DeepSeek keys both start with "sk-",
        // so those are tried in turn.
        let candidates: [AIProvider] = key.hasPrefix("sk-ant-") ? [.anthropic] : key.hasPrefix("AIza") ? [.gemini] : [.openAI, .deepSeek]
        for candidate in candidates {
            guard let ids = try? await Self.listModels(candidate, key: key) else { continue }
            let chat = candidate.chatModels(ids)
            guard let first = chat.first else { continue }
            guard Keychain.setSecret(key, for: Self.keychainAccount, service: Self.keychainService) else {
                error = String(localized: "Couldn't save the key in the Keychain.")
                return
            }
            cachedKey = key
            models = chat
            model = first
            provider = candidate
            engine = .cloud
            return
        }
        error = String(localized: "No provider accepted this key. StockBar works with OpenAI, Anthropic, DeepSeek and Google Gemini keys.")
    }

    /// The provider's models, for the picker (asked again on each launch, since they change).
    func loadModels() async {
        guard let provider, let key, models.isEmpty else { return }
        if let ids = try? await Self.listModels(provider, key: key) {
            models = provider.chatModels(ids)
            if !models.contains(model), let first = models.first { model = first }
        }
    }

    func forget() {
        Keychain.deleteSecret(for: Self.keychainAccount, service: Self.keychainService)
        cachedKey = nil
        provider = nil
        models = []
        model = ""
        error = nil
        if engine == .cloud { engine = .apple }
    }

    private static func listModels(_ provider: AIProvider, key: String) async throws -> [String] {
        var request = URLRequest(url: provider.modelsURL)
        request.timeoutInterval = 20
        provider.authorize(&request, key: key)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.userAuthenticationRequired) }
        struct List: Decodable { struct Model: Decodable { var id: String }; var data: [Model] }
        return try JSONDecoder().decode(List.self, from: data).data.map(\.id)
    }
}

/// A conversation with a cloud model, kept in the provider's own message format so every turn only appends
/// (Anthropic's thinking blocks must come back exactly as they were sent).
@MainActor
final class AICloudConversation {
    let provider: AIProvider
    let model: String
    private let key: String
    /// Turns off a local model's thinking (see chatCompletionsBody).
    private let skipThinking: Bool
    private var messages: [[String: Any]] = []

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    init(provider: AIProvider, model: String, key: String, skipThinking: Bool = false) {
        self.provider = provider
        self.model = model
        self.key = key
        self.skipThinking = skipThinking
    }

    /// Asks the model, runs the tools it calls and asks again, until it answers (at most 6 rounds).
    /// `phase` reports each model request's duration as it finishes.
    func ask(_ prompt: String, system: String, data: AIData,
             note: (_ label: String, _ output: String, _ seconds: Double) -> Void,
             phase: (_ seconds: Double) -> Void) async throws -> String {
        messages.append(["role": "user", "content": prompt])
        for _ in 0..<6 {
            let start = Date.now
            let body = provider == .anthropic ? anthropicBody(system: system) : chatCompletionsBody(system: system)
            let reply = try await send(body)
            phase(Date.now.timeIntervalSince(start))
            let calls = provider == .anthropic ? try anthropicCalls(reply) : try chatCompletionsCalls(reply)
            guard case .tools(let requests) = calls else {
                if case .answer(let text) = calls { return text }
                return ""
            }
            var results: [(id: String, output: String)] = []
            for call in requests {
                let started = Date.now
                let (label, output) = await AIToolbox.run(call.name, arguments: call.arguments, data: data)
                note(label, output, Date.now.timeIntervalSince(started))
                results.append((call.id, output))
            }
            if provider == .anthropic {
                messages.append(["role": "user", "content": results.map { ["type": "tool_result", "tool_use_id": $0.id, "content": $0.output] }])
            } else {
                messages += results.map { ["role": "tool", "tool_call_id": $0.id, "content": $0.output] }
            }
        }
        throw Failure(message: String(localized: "The model kept looking things up without answering. Try a more specific question."))
    }

    private enum Step {
        case answer(String)
        case tools([(id: String, name: String, arguments: [String: Any])])
    }

    // MARK: Anthropic Messages API

    private func anthropicBody(system: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model, "max_tokens": 16_000, "system": system, "messages": messages,
            "tools": AIToolbox.specs.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] },
        ]
        // Claude 5 models take an effort level; a chat about the user's data doesn't need deep reasoning.
        if model.range(of: #"^claude-(opus|sonnet|haiku|fable)-5"#, options: .regularExpression) != nil {
            body["output_config"] = ["effort": "low"]
        }
        if Self.takesFallbacks(model) { body["fallbacks"] = "default" }
        return body
    }

    /// Models whose safety classifiers can decline a request, which then re-run it on another model instead.
    private static func takesFallbacks(_ model: String) -> Bool {
        model.range(of: #"^claude-(opus-5|sonnet-5-5|fable-5)"#, options: .regularExpression) != nil
    }

    private func anthropicCalls(_ reply: [String: Any]) throws -> Step {
        let content = reply["content"] as? [[String: Any]] ?? []
        if reply["stop_reason"] as? String == "refusal" {
            throw Failure(message: String(localized: "The model declined to answer that. Try rephrasing the question."))
        }
        // Kept exactly as returned, thinking blocks included.
        messages.append(["role": "assistant", "content": content])
        let uses = content.filter { $0["type"] as? String == "tool_use" }
        if reply["stop_reason"] as? String == "tool_use", !uses.isEmpty {
            return .tools(uses.map { ($0["id"] as? String ?? "", $0["name"] as? String ?? "", $0["input"] as? [String: Any] ?? [:]) })
        }
        return .answer(content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined())
    }

    // MARK: Chat Completions (OpenAI, DeepSeek, Gemini, Ollama)

    private func chatCompletionsBody(system: String) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system]] + messages,
            "tools": AIToolbox.specs.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] },
        ]
        // Thinking models (Qwen 3.x and others) think before answering by default, which on a Mac takes longer than
        // the answer itself; looking up and restating the user's figures doesn't need it. Sent only to models that
        // think: Ollama can reject it for the others.
        if provider == .ollama, skipThinking { body["reasoning_effort"] = "none" }
        return body
    }

    private func chatCompletionsCalls(_ reply: [String: Any]) throws -> Step {
        guard let choice = (reply["choices"] as? [[String: Any]])?.first, let message = choice["message"] as? [String: Any] else {
            throw Failure(message: String(localized: "The model's answer was empty."))
        }
        if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw Failure(message: refusal) }
        let calls = message["tool_calls"] as? [[String: Any]] ?? []
        // Only what the API takes back: not reasoning_content (DeepSeek's reasoner rejects it) or annotations.
        var kept: [String: Any] = ["role": "assistant", "content": message["content"] as? String ?? NSNull()]
        if !calls.isEmpty { kept["tool_calls"] = calls }
        messages.append(kept)
        guard !calls.isEmpty else { return .answer(message["content"] as? String ?? "") }
        return .tools(calls.map { call in
            let function = call["function"] as? [String: Any] ?? [:]
            let arguments = (function["arguments"] as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] } ?? [:]
            return (call["id"] as? String ?? "", function["name"] as? String ?? "", arguments)
        })
    }

    // MARK: HTTP

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: provider.chatURL)
        request.httpMethod = "POST"
        // A local model may first have to load (18 GB from disk) before it reads the question.
        request.timeoutInterval = provider == .ollama ? 300 : 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        provider.authorize(&request, key: key)
        if provider == .anthropic, Self.takesFallbacks(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            throw Failure(message: Self.explain(status, provider: provider) + (detail.isEmpty ? "" : "\n\(detail)"))
        }
        return json
    }

    private static func explain(_ status: Int, provider: AIProvider) -> String {
        if provider == .ollama {
            return status == 404
                ? String(localized: "Ollama doesn't have this model anymore. Pick another in Settings → AI.")
                : String(localized: "Ollama returned error \(status).")
        }
        return switch status {
        case 401, 403: String(localized: "\(provider.label) rejected the API key. Check it in Settings → AI.")
        case 402: String(localized: "The \(provider.label) account is out of credit.")
        case 429: String(localized: "\(provider.label) is rate-limiting this key, or its credit ran out. Try again in a moment.")
        case 500...599: String(localized: "\(provider.label) is having problems (error \(status)). Try again in a moment.")
        default: String(localized: "\(provider.label) returned error \(status).")
        }
    }
}

/// The tools, once for every engine: what the model is told about them (JSON Schema for the cloud APIs;
/// Apple's framework reads the @Guide descriptions in AIHarness.swift) and how a call is answered.
enum AIToolbox {
    struct Spec {
        var name: String
        var description: String
        var parameters: [String: Any]
    }

    static let queryDescription = "Searches, counts and totals the user's card and bank transactions; every answer includes the largest one and, over several months, a total per month. Filters are optional; set each one the question mentions. Examples: 'Uber rides this month' → text uber. 'PIX to João this year' → text João, method pix, period this year. 'Biggest purchase in September' → month 2026-09, largestFirst. 'Uber per month in 2026' → text uber, month 2026. 'Delivery per week' → category delivery, groupBy week. 'Purchases over R$ 500' → amountAbove 500. 'Under R$ 50 on debit' → amountBelow 50, method debit card."
    static let spendingDescription = "Totals the user's spending in a period: by category (with limits) and top places. Use for 'how much did I spend', 'where does my money go'."
    static let overviewDescription = "The user's portfolio totals by asset class, today's change, largest stock positions, and dividends received this year and coming up."
    static let holdingsDescription = "Lists the user's positions of one kind: stocks (quantity, value, price, average price, gain), bonds (CDB, LCI, LCA: rate, maturity, value, what they earned this month and since purchase) or funds."

    private static func string(_ description: String, _ values: [String]? = nil) -> [String: Any] {
        var schema: [String: Any] = ["type": "string", "description": description]
        if let values { schema["enum"] = values }
        return schema
    }

    private static var periodFields: [String: Any] {
        ["period": string("The period", AIPeriod.allCases.map(\.rawValue)),
         "month": string("A month the user names, as YYYY-MM, or a year as YYYY. It replaces period.")]
    }

    static let specs: [Spec] = [
        Spec(name: "queryTransactions", description: queryDescription, parameters: [
            "type": "object", "required": ["period"],
            "properties": periodFields.merging([
                "text": string("Merchant or person the money went to or came from, like 'uber', 'ifood' or 'João'."),
                "category": string("Expense category name, like 'Transport'."),
                "method": string("How the money moved", AIData.methods.map(\.0)),
                "account": string("Account or card name, like 'Nubank' or 'XP'."),
                "direction": string("Money out (spending), in (income) or both", ["out", "in", "both"]),
                "amountAbove": ["type": "number", "description": "Only transactions of this many reais or more."],
                "amountBelow": ["type": "number", "description": "Only transactions of this many reais or less."],
                "groupBy": string("Only when the user asks for totals per something ('per week', 'by category')",
                                  ["merchant", "category", "method", "account", "day", "week", "month"]),
                "largestFirst": ["type": "boolean", "description": "List the largest first instead of the newest."],
            ]) { a, _ in a },
        ]),
        Spec(name: "spendingSummary", description: spendingDescription, parameters: [
            "type": "object", "required": ["period"], "properties": periodFields,
        ]),
        Spec(name: "portfolioOverview", description: overviewDescription, parameters: ["type": "object", "properties": [String: Any]()]),
        Spec(name: "listHoldings", description: holdingsDescription, parameters: [
            "type": "object", "required": ["kind"],
            "properties": ["kind": string("Which positions", ["stocks", "bonds", "funds"]),
                           "indexer": string("Bonds only. fixed: prefixado, pré-fixado, taxa fixa. cdi: pós-fixado, % do CDI. ipca: IPCA+, inflação.", ["fixed", "cdi", "ipca"])],
        ]),
    ]

    /// Answers one tool call, with the line shown under the answer.
    @MainActor
    static func run(_ name: String, arguments a: [String: Any], data: AIData) async -> (label: String, output: String) {
        func text(_ key: String) -> String? { (a[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        // Small models sometimes fill every field; an empty text or a zero amount means "no filter".
        func number(_ key: String) -> Double? {
            ((a[key] as? NSNumber)?.doubleValue ?? (a[key] as? String).flatMap(Double.init)).flatMap { $0 > 0 ? $0 : nil }
        }
        let period = text("period") ?? AIPeriod.thisMonth.rawValue
        switch name {
        case "queryTransactions":
            let query = TransactionQuery(period: period, month: text("month"), text: text("text"), category: text("category"),
                                         method: text("method"), account: text("account"), direction: text("direction"),
                                         minimumAmount: number("amountAbove"), maximumAmount: number("amountBelow"),
                                         groupBy: text("groupBy"), largestFirst: a["largestFirst"] as? Bool)
            let parts = [query.text, query.category, query.method, query.account, query.minimumAmount.map { "≥ \($0.reais)" },
                         query.maximumAmount.map { "≤ \($0.reais)" }, query.month ?? AIPeriod.label(period),
                         query.groupBy.map { String(localized: String.LocalizationValue("per " + $0)) }].compactMap { $0 }
            return (([String(localized: "Transactions")] + parts).joined(separator: " · "), await data.queryTransactions(query))
        case "spendingSummary":
            return (String(localized: "Spending") + " · " + (text("month") ?? AIPeriod.label(period)), await data.spendingSummary(period: period, month: text("month")))
        case "portfolioOverview":
            return (String(localized: "Portfolio"), data.portfolioOverview())
        case "listHoldings":
            let kind = text("kind") ?? "stocks"
            return ([String(localized: "Positions"), kind, text("indexer")].compactMap { $0 }.joined(separator: " · "),
                    data.holdings(kind: kind, indexer: text("indexer")))
        default:
            return (name, "There's no tool called \(name).")
        }
    }
}
