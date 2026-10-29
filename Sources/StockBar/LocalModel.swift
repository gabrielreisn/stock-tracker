import CryptoKit
import Foundation
import llama

/// Qwen3 4B Instruct, run on the Mac with llama.cpp: free, private and quick on Apple silicon (about 1–2 s an
/// answer on an M1 Max once loaded). The user downloads it from Settings → AI and can delete it there.
@MainActor
@Observable
final class LocalModel {
    enum State: Equatable {
        case missing
        case downloading(Double)
        case verifying
        case ready
        case failed(String)
    }

    /// Pinned to a revision and checked against its hash, so the file is exactly the one tested.
    static let displayName = "Qwen3 4B Instruct"
    private static let fileName = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf"
    private static let source = URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/a06e946bb6b655725eafa393f4a9745d460374c9/Qwen3-4B-Instruct-2507-Q4_K_M.gguf")!
    nonisolated static let size: Int64 = 2_497_281_120
    private static let sha256 = "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597"

    private static var directory: URL { PortfolioStore.directory.appendingPathComponent("Models") }
    static var file: URL { directory.appendingPathComponent(fileName) }

    private(set) var state: State
    @ObservationIgnored private var download: Task<Void, Never>?
    @ObservationIgnored private var idleUnload: Task<Void, Never>?
    /// Loaded on the first question and kept for ten minutes after the last one.
    nonisolated let runner = LlamaRunner()

    init() {
        let size = (try? FileManager.default.attributesOfItem(atPath: Self.file.path))?[.size] as? Int64
        state = size == Self.size ? .ready : .missing
    }

    var isReady: Bool { state == .ready }

    func startDownload() {
        guard download == nil else { return }
        state = .downloading(0)
        download = Task {
            defer { download = nil }
            do {
                try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
                let progress = DownloadProgress { [weak self] fraction in
                    Task { @MainActor in if case .downloading = self?.state { self?.state = .downloading(fraction) } }
                }
                let (temporary, response) = try await URLSession.shared.download(from: Self.source, delegate: progress)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                state = .verifying
                let staged = Self.directory.appendingPathComponent(Self.fileName + ".part")
                try? FileManager.default.removeItem(at: staged)
                try FileManager.default.moveItem(at: temporary, to: staged)
                let hash = try await Task.detached(priority: .userInitiated) { try Self.hash(staged) }.value
                guard hash == Self.sha256 else {
                    try? FileManager.default.removeItem(at: staged)
                    state = .failed(String(localized: "The download was damaged. Try again."))
                    return
                }
                try? FileManager.default.removeItem(at: Self.file)
                try FileManager.default.moveItem(at: staged, to: Self.file)
                // 2,5 GB that can be downloaded again: keep it out of Time Machine.
                var file = Self.file
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? file.setResourceValues(values)
                state = .ready
            } catch is CancellationError {
                state = .missing
            } catch let error as URLError where error.code == .cancelled {
                state = .missing
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
    }

    func delete() {
        idleUnload?.cancel()
        Task { await runner.unload() }
        try? FileManager.default.removeItem(at: Self.file)
        state = .missing
    }

    /// Frees the model before the app exits: llama.cpp's Metal backend aborts (a crash report) when the process
    /// ends with a model still loaded. Waits up to three seconds for an answer in progress to stop.
    nonisolated func shutdown() {
        let done = DispatchSemaphore(value: 0)
        Task.detached { [runner] in
            await runner.unload()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
    }

    /// Frees the model's memory now (see `AIChat.releaseLocalModel`); the next question loads it again (about 0,5 s).
    func unload() {
        idleUnload?.cancel()
        Task { [runner] in await runner.unload() }
    }

    /// Frees the model's memory (about 1 GB of working memory) once nobody has asked anything for ten minutes.
    func scheduleUnload() {
        idleUnload?.cancel()
        idleUnload = Task { [runner] in
            try? await Task.sleep(for: .seconds(600))
            guard !Task.isCancelled else { return }
            await runner.unload()
        }
    }

    nonisolated private static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        private var last = 0.0
        init(report: @escaping @Sendable (Double) -> Void) { self.report = report }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
            let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : LocalModel.size
            let fraction = Double(totalBytesWritten) / Double(expected)
            // A few hundred updates are plenty for a progress bar.
            if fraction - last >= 0.005 || fraction >= 1 { last = fraction; report(fraction) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }
}

/// llama.cpp behind an actor: one generation at a time, off the main thread. It keeps what it has already read
/// (the KV cache) and, for the next prompt, reads only what comes after the part they share. The rules and the
/// tools, about 1.600 tokens, are read once per load instead of on every round.
actor LlamaRunner {
    struct Result {
        var text: String
        /// Reading the new part of the prompt: from the call to the first generated token.
        var reading: Double
        var writing: Double
    }

    enum Failure: LocalizedError {
        case load, decode, contextFull
        var errorDescription: String? {
            switch self {
            case .load: String(localized: "The local model couldn't be loaded. Delete it in Settings → AI and download it again.")
            case .decode: String(localized: "The local model stopped while answering. Try again.")
            case .contextFull: String(localized: "This conversation got too long for the local model.")
            }
        }
    }

    static let contextSize: Int32 = 6144
    private static let batchSize: Int32 = 512

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var sampler: UnsafeMutablePointer<llama_sampler>?
    /// The tokens the KV cache holds, in order.
    private var cached: [llama_token] = []

    private static let backend: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    var isLoaded: Bool { context != nil }

    func load(_ file: URL) throws {
        guard context == nil else { return }
        _ = Self.backend
        var modelParams = llama_model_default_params()
        #if arch(arm64)
        modelParams.n_gpu_layers = 999
        #else
        modelParams.n_gpu_layers = 0  // Intel Macs: the CPU, slowly
        #endif
        guard let model = llama_model_load_from_file(file.path, modelParams) else { throw Failure.load }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(Self.contextSize)
        contextParams.n_batch = UInt32(Self.batchSize)
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw Failure.load
        }
        // Greedy: the same question over the same data gets the same answer.
        let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())
        (self.model, self.context, self.vocab, self.sampler) = (model, context, llama_model_get_vocab(model), sampler)
        cached = []
    }

    func unload() {
        if let sampler { llama_sampler_free(sampler) }
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        (model, context, vocab, sampler) = (nil, nil, nil, nil)
        cached = []
    }

    /// Continues `prompt` (already in the model's chat format) until the model ends its turn. `onText` gets the
    /// text so far after each token.
    func generate(_ prompt: String, maxTokens: Int = 700, onText: @Sendable (String) -> Void) throws -> Result {
        guard let context, let vocab, let sampler else { throw Failure.load }
        let start = Date.now
        let tokens = tokenize(prompt)
        guard tokens.count + maxTokens < Int(Self.contextSize) else { throw Failure.contextFull }

        // Keep the shared beginning, drop the rest, read only what's new (at least one token, for the logits).
        var keep = 0
        while keep < min(cached.count, tokens.count), cached[keep] == tokens[keep] { keep += 1 }
        keep = min(keep, tokens.count - 1)
        llama_memory_seq_rm(llama_get_memory(context), 0, Int32(keep), -1)
        cached = Array(cached.prefix(keep))
        var next = keep
        while next < tokens.count {
            try Task.checkCancellation()
            let count = min(Int(Self.batchSize), tokens.count - next)
            var chunk = Array(tokens[next..<next + count])
            let status = chunk.withUnsafeMutableBufferPointer { llama_decode(context, llama_batch_get_one($0.baseAddress, Int32(count))) }
            guard status == 0 else { cached = []; llama_memory_clear(llama_get_memory(context), true); throw Failure.decode }
            cached += chunk
            next += count
        }

        var bytes: [UInt8] = []
        var firstToken: Date?
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if firstToken == nil { firstToken = .now }
            if llama_vocab_is_eog(vocab, token) { break }
            bytes += piece(token)
            onText(String(decoding: bytes, as: UTF8.self))
            let status = llama_decode(context, llama_batch_get_one(&token, 1))
            guard status == 0 else { cached = []; llama_memory_clear(llama_get_memory(context), true); throw Failure.decode }
            cached.append(token)
            if cached.count >= Int(Self.contextSize) - 1 { break }
        }
        let end = Date.now
        let first = firstToken ?? end
        return Result(text: String(decoding: bytes, as: UTF8.self), reading: first.timeIntervalSince(start), writing: end.timeIntervalSince(first))
    }

    private func tokenize(_ text: String) -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        // parse_special: the chat format's <|im_start|> and <|im_end|> are single special tokens.
        var count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), false, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), false, true)
        }
        return Array(tokens.prefix(Int(max(count, 0))))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(count, 0))).map { UInt8(bitPattern: $0) }
    }
}

/// Qwen3's chat format (ChatML with Hermes-style tool calls), written out as its official template renders it,
/// so what the model reads matches what it was trained on.
enum QwenChat {
    enum Message {
        case user(String)
        /// What the model wrote, tool calls included, exactly as generated (so the KV cache still matches).
        case assistant(String)
        case toolResults([String])
    }

    /// The tools as the template lists them, one JSON object per line; built once, so every prompt starts the same.
    private static let toolLines: String = AIToolbox.specs.map { spec in
        let tool: [String: Any] = ["type": "function", "function": ["name": spec.name, "description": spec.description, "parameters": spec.parameters]]
        let data = (try? JSONSerialization.data(withJSONObject: tool, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }.joined(separator: "\n")

    /// The tool call the model's turn starts with when it must look something up first (see `prompt`).
    static let toolCallStart = "<tool_call>\n"

    /// `startWithToolCall` begins the model's turn with a tool call, so it can't answer from nothing: a 4B model
    /// will otherwise sometimes skip the tools and make up figures.
    static func prompt(system: String, messages: [Message], startWithToolCall: Bool = false) -> String {
        var text = "<|im_start|>system\n\(system)\n\n# Tools\n\nYou may call one or more functions to assist with the user query.\n\n"
            + "You are provided with function signatures within <tools></tools> XML tags:\n<tools>\n\(toolLines)\n</tools>\n\n"
            + "For each function call, return a json object with function name and arguments within <tool_call></tool_call> XML tags:\n"
            + "<tool_call>\n{\"name\": <function-name>, \"arguments\": <args-json-object>}\n</tool_call><|im_end|>\n"
        for message in messages {
            switch message {
            case .user(let content): text += "<|im_start|>user\n\(content)<|im_end|>\n"
            case .assistant(let content): text += "<|im_start|>assistant\n\(content)<|im_end|>\n"
            case .toolResults(let outputs):
                text += "<|im_start|>user" + outputs.map { "\n<tool_response>\n\($0)\n</tool_response>" }.joined() + "<|im_end|>\n"
            }
        }
        return text + "<|im_start|>assistant\n" + (startWithToolCall ? toolCallStart : "")
    }

    /// The tool calls in what the model wrote, and the text around them.
    static func calls(in output: String) -> (calls: [(name: String, arguments: [String: Any])], text: String) {
        var calls: [(String, [String: Any])] = []
        let pattern = try! NSRegularExpression(pattern: #"<tool_call>\s*(\{.*?\})\s*</tool_call>"#, options: [.dotMatchesLineSeparators])
        for match in pattern.matches(in: output, range: NSRange(output.startIndex..., in: output)) {
            guard let range = Range(match.range(at: 1), in: output),
                  let json = try? JSONSerialization.jsonObject(with: Data(output[range].utf8)) as? [String: Any],
                  let name = json["name"] as? String else { continue }
            calls.append((name, json["arguments"] as? [String: Any] ?? [:]))
        }
        let text = pattern.stringByReplacingMatches(in: output, range: NSRange(output.startIndex..., in: output), withTemplate: "")
        return (calls, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// While streaming: the text without tool calls, or nothing yet if a call is being written.
    static func visible(_ partial: String) -> String {
        if let start = partial.range(of: "<tool_call>") { return String(partial[..<start.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        return partial.hasPrefix("<") ? "" : partial
    }
}
