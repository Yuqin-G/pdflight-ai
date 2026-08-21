import Foundation

public struct OpenAICompatibleClient: Sendable {
    public init() {}

    public func streamChat(
        messages: [AIChatMessage],
        configuration: AIProviderConfiguration,
        apiKey: String,
        conversationKey: String? = nil,
        conversationTitle: String? = nil
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        messages: messages,
                        configuration: configuration,
                        apiKey: apiKey,
                        conversationKey: conversationKey,
                        conversationTitle: conversationTitle
                    )
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw OpenAICompatibleError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var lines: [String] = []
                        for try await line in bytes.lines {
                            lines.append(line)
                            if lines.joined(separator: "\n").count >= 8_000 { break }
                        }
                        let body = lines.joined(separator: "\n")
                        throw OpenAICompatibleError.httpStatus(
                            http.statusCode,
                            serviceMessage(from: body) ?? body
                        )
                    }

                    var decoder = OpenAIStreamDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = try decoder.decode(line: line) else { continue }
                        switch event {
                        case .contentDelta, .reasoningDelta:
                            continuation.yield(event)
                        case .finished:
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func makeRequest(
        messages: [AIChatMessage],
        configuration: AIProviderConfiguration,
        apiKey: String,
        conversationKey: String? = nil,
        conversationTitle: String? = nil
    ) throws -> URLRequest {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw OpenAICompatibleError.invalidConfiguration("Enter a model in AI Settings.")
        }
        let endpoint = try endpointURL(from: configuration.baseURL)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(RequestBody(
            model: model,
            messages: messages.map { RequestMessage(role: $0.role.rawValue, content: $0.content) },
            stream: true,
            conversationKey: conversationKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationTitle: conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        return request
    }

    private func endpointURL(from rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            throw OpenAICompatibleError.invalidConfiguration("Enter a valid AI Base URL.")
        }
        let isLoopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLoopback) else {
            throw OpenAICompatibleError.invalidConfiguration(
                "Use HTTPS, or HTTP only for localhost AI services."
            )
        }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") {
            components.path = "/" + [path, "chat/completions"]
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }
        guard let endpoint = components.url else {
            throw OpenAICompatibleError.invalidConfiguration("Enter a valid AI Base URL.")
        }
        return endpoint
    }

    private func serviceMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = value["error"] as? [String: Any],
              let message = error["message"] as? String else { return nil }
        return message
    }
}

private struct RequestBody: Encodable {
    let model: String
    let messages: [RequestMessage]
    let stream: Bool
    let conversationKey: String?
    let conversationTitle: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case conversationKey = "conversation_key"
        case conversationTitle = "conversation_title"
    }
}

private struct RequestMessage: Encodable {
    let role: String
    let content: String
}
