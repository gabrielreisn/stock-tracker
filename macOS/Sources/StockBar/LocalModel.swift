import Foundation

/// The local engine: a model the user has in Ollama, run on the Mac, free and private. StockBar doesn't run models
/// itself; it talks to Ollama's local server, which the user installs from ollama.com. Settings → AI lists the
/// installed models that can call tools (the chat needs them) and remembers the choice; with none, it offers to
/// download a small one through Ollama. Chats go through Ollama's OpenAI-compatible endpoint (`AIProvider.ollama`),
/// so they share the cloud engines' tool-calling code.
@MainActor
@Observable
final class LocalModel {
    enum State: Equatable {
        case checking
        /// Ollama isn't installed, or isn't open.
        case notRunning
        /// Ollama is running but has no model that can call tools.
        case missing
        case downloading(Double)
        case ready
        case failed(String)
    }

    struct Installed: Hashable {
        var name: String
        var size: Int64
        /// Thinks before answering by default (Qwen 3.x and others); StockBar turns that off.
        var thinks: Bool
    }

    /// Offered when Ollama has no suitable model: small enough for most Macs, and good at tool calls.
    static let suggested = "qwen3:8b"
    nonisolated static let server = URL(string: "http://127.0.0.1:11434")!
    static let downloadPage = URL(string: "https://ollama.com/download")!

    private(set) var state: State = .checking
    private(set) var models: [Installed] = []
    /// The model the AI tab uses, chosen in Settings → AI.
    var model: String { didSet { UserDefaults.standard.set(model, forKey: "ollamaModel") } }
    @ObservationIgnored private var download: Task<Void, Never>?

    init() {
        model = UserDefaults.standard.string(forKey: "ollamaModel") ?? ""
        Self.removeOldModel()
        Task { await refresh() }
    }

    var isReady: Bool { state == .ready }
    var selected: Installed? { models.first { $0.name == model } }

    /// Asks Ollama whether it's running and which models it has. Called when Settings → AI or the AI tab appears.
    func refresh() async {
        if case .downloading = state { return }
        var request = URLRequest(url: Self.server.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else {
            state = .notRunning
            return
        }
        struct Tags: Decodable {
            struct Model: Decodable { var name: String; var size: Int64; var capabilities: [String]? }
            var models: [Model]
        }
        let all = (try? JSONDecoder().decode(Tags.self, from: data))?.models ?? []
        models = all.filter { $0.capabilities?.contains("tools") ?? false }
            .map { Installed(name: $0.name, size: $0.size, thinks: $0.capabilities?.contains("thinking") ?? false) }
            .sorted { $0.size < $1.size }
        // Keep the choice while it's installed; otherwise the smallest model, the one most Macs can run.
        if selected == nil, let first = models.first { model = first.name }
        state = models.isEmpty ? .missing : .ready
    }

    /// Has Ollama download the suggested model, reporting its progress.
    func startDownload() {
        guard download == nil else { return }
        state = .downloading(0)
        download = Task {
            defer { download = nil }
            do {
                var request = URLRequest(url: Self.server.appendingPathComponent("api/pull"))
                request.httpMethod = "POST"
                request.timeoutInterval = 600
                request.httpBody = try JSONSerialization.data(withJSONObject: ["model": Self.suggested, "stream": true])
                let (lines, response) = try await URLSession.shared.bytes(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                // One JSON object per line: {"status", "total", "completed"} while the layers download, then "success".
                for try await line in lines.lines {
                    guard let update = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                    if let error = update["error"] as? String { throw Failure(message: error) }
                    if let total = (update["total"] as? NSNumber)?.doubleValue, total > 100_000_000,
                       let completed = (update["completed"] as? NSNumber)?.doubleValue {
                        state = .downloading(completed / total)
                    }
                }
                model = Self.suggested
                state = .checking
                await refresh()
            } catch is CancellationError {
                await refresh()
            } catch let error as URLError where error.code == .cancelled {
                await refresh()
            } catch let error as URLError where error.code == .cannotConnectToHost {
                state = .notRunning
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancelDownload() {
        download?.cancel()
    }

    /// Asks Ollama to free the model's memory now (see `AIChat.releaseLocalModel`); otherwise it keeps it loaded
    /// for five minutes after the last answer. The next question loads it again.
    func unload() {
        guard !model.isEmpty else { return }
        var request = URLRequest(url: Self.server.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "keep_alive": 0])
        URLSession.shared.dataTask(with: request).resume()
    }

    struct Failure: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// StockBar 3.0 downloaded Qwen3 4B itself (2,5 GB in Application Support/StockBar/Models). Ollama replaced it,
    /// so the file only takes space.
    private static func removeOldModel() {
        let folder = DataAccount.baseDirectory.appendingPathComponent("Models")
        for name in ["Qwen3-4B-Instruct-2507-Q4_K_M.gguf", "Qwen3-4B-Instruct-2507-Q4_K_M.gguf.part"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
