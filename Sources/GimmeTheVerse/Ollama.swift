import Foundation

enum OllamaError: LocalizedError {
    case notRunning
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Ollama läuft nicht. Starte es im Terminal mit: brew services start ollama"
        case let .http(code, msg):
            return "Ollama-Fehler \(code): \(msg)"
        case .badResponse:
            return "Unerwartete Antwort von Ollama."
        }
    }
}

/// Merkt sich Modelle, die in Ollama keine Structured Outputs unterstützen (z. B. gemma4).
private enum StructuredSupport {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lacking = Set<String>()

    static func lacks(_ model: String) -> Bool { lock.withLock { lacking.contains(model) } }
    static func markLacking(_ model: String) { _ = lock.withLock { lacking.insert(model) } }
}

/// Minimaler Client für die lokale Ollama-API.
struct Ollama: Sendable {
    static let embedModel = "embeddinggemma-2"
    /// Ollama nimmt sonst 4096 – knapp für die Kandidatenliste.
    static let contextLength = 8192
    var base = URL(string: "http://localhost:11434")!

    func embed(_ texts: [String]) async throws -> [[Float]] {
        let json = try await post("api/embed", ["model": Self.embedModel, "input": texts])
        guard let e = json["embeddings"] as? [[Double]], e.count == texts.count else { throw OllamaError.badResponse }
        return e.map { $0.map(Float.init) }
    }

    /// Chat mit JSON-Antwort. Nutzt Structured Outputs, wenn das Modell sie kann,
    /// sonst wird das Schema in den Prompt gelegt und das JSON aus der Antwort geschnitten.
    func chatJSON<T: Decodable>(_: T.Type, model: String, system: String, user: String,
                                schema: [String: Any], example: String, temperature: Double = 0.2) async throws -> T {
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "30m",
            "format": schema,
            "options": ["temperature": temperature, "num_ctx": Self.contextLength],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        let fallback = {
            body["format"] = nil
            body["messages"] = [
                ["role": "system", "content": system + "\n\nAntworte ausschließlich mit einem einzigen JSON-Objekt in genau dieser Form, ohne weiteren Text:\n" + example],
                ["role": "user", "content": user],
            ]
        }
        let json: [String: Any]
        if StructuredSupport.lacks(model) {
            fallback()
            json = try await post("api/chat", body)
        } else {
            do {
                json = try await post("api/chat", body)
            } catch let OllamaError.http(_, msg) where msg.contains("structured output") {
                StructuredSupport.markLacking(model)
                fallback()
                json = try await post("api/chat", body)
            }
        }
        guard let content = (json["message"] as? [String: Any])?["content"] as? String,
              let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"),
              let data = String(content[start...end]).data(using: .utf8) else { throw OllamaError.badResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// Chat mit gestreamter Antwort, liefert Text-Stücke.
    func chatStream(model: String, system: String, user: String, temperature: Double = 0.7) -> AsyncThrowingStream<String, Error> {
        chatStream(model: model, messages: [["role": "system", "content": system], ["role": "user", "content": user]],
                   temperature: temperature)
    }

    /// Gestreamter Chat mit beliebigem Verlauf ([["role": …, "content": …]]).
    func chatStream(model: String, messages: [[String: String]], temperature: Double = 0.7) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request("api/chat", [
                        "model": model,
                        "stream": true,
                        "think": false,
                        "keep_alive": "30m",
                        "options": ["temperature": temperature, "num_ctx": Self.contextLength],
                        "messages": messages,
                    ])
                    let (bytes, response) = try await data(for: req)
                    try check(response)
                    for try await line in bytes.lines {
                        guard let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        if let err = obj["error"] as? String { throw OllamaError.http(500, err) }
                        if let chunk = (obj["message"] as? [String: Any])?["content"] as? String, !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                        if obj["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Installierte Chat-Modelle (ohne Embedding-Modelle).
    func chatModels() async throws -> [String] {
        var req = URLRequest(url: base.appendingPathComponent("api/tags"))
        req.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let names = (json?["models"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        return names.filter { !$0.contains("embed") }.sorted()
    }

    /// Lädt das Modell vorab in den Speicher, damit die erste Anfrage schnell ist.
    func warmUp(model: String) async {
        _ = try? await post("api/generate", ["model": model, "keep_alive": "30m"])
        _ = try? await embed(["warmup"])
    }

    // MARK: - HTTP

    private func request(_ path: String, _ body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 300
        return req
    }

    private func data(for req: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do { return try await URLSession.shared.bytes(for: req) }
        catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            throw OllamaError.notRunning
        }
    }

    private func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let req = try request(path, body)
        let result: (Data, URLResponse)
        do { result = try await URLSession.shared.data(for: req) }
        catch let e as URLError where e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
            throw OllamaError.notRunning
        }
        try check(result.1, body: result.0)
        guard let json = try JSONSerialization.jsonObject(with: result.0) as? [String: Any] else { throw OllamaError.badResponse }
        return json
    }

    private func check(_ response: URLResponse, body: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var msg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if let body, let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let e = obj["error"] as? String { msg = e }
            throw OllamaError.http(http.statusCode, msg)
        }
    }
}
