import Foundation

public struct OpenAICompatibleClient: Sendable {
    public init() {}

    public func streamChat(
        messages: [AIChatMessage],
        configuration: AIProviderConfiguration,
        apiKey: String,
        conversationKey: String? = nil,
        conversationTitle: String? = nil,
        currentPDFURL: URL? = nil
    ) -> AsyncThrowingStream<OpenAIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(
                        messages: messages,
                        configuration: configuration,
                        apiKey: apiKey,
                        conversationKey: conversationKey,
                        conversationTitle: conversationTitle,
                        currentPDFURL: currentPDFURL
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

                    var decoder = OpenAIStreamDecoder(api: configuration.api)
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
        conversationTitle: String? = nil,
        currentPDFURL: URL? = nil
    ) throws -> URLRequest {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw OpenAICompatibleError.invalidConfiguration("Enter a model in AI Settings.")
        }
        if configuration.api != "openai-completions" {
            return try makeAlternateRequest(messages: messages, configuration: configuration, apiKey: apiKey, currentPDFURL: currentPDFURL)
        }
        let endpoint = try endpointURL(from: configuration.baseURL)
        if currentPDFURL != nil {
            let host = endpoint.host?.lowercased() ?? ""
            guard host == "localhost" || host == "127.0.0.1" || host == "::1" else {
                throw OpenAICompatibleError.invalidConfiguration(
                    "Local PDF attachment is available only with a localhost AI service."
                )
            }
        }
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
            messages: messages.map(RequestMessage.init),
            stream: true,
            reasoningEffort: configuration.reasoningEffort,
            maxTokens: configuration.maxTokens.flatMap { $0 > 0 ? $0 : nil },
            conversationKey: conversationKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            conversationTitle: conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
            pdfAttachments: currentPDFURL.map {
                [RequestPDFAttachment(
                    path: $0.standardizedFileURL.path,
                    name: $0.lastPathComponent,
                    mimeType: "application/pdf"
                )]
            }
        ))
        return request
    }

    private func makeAlternateRequest(messages: [AIChatMessage], configuration: AIProviderConfiguration, apiKey: String, currentPDFURL: URL?) throws -> URLRequest {
        guard ["openai-responses", "anthropic-messages"].contains(configuration.api) else {
            throw OpenAICompatibleError.invalidConfiguration("Unsupported model API: \(configuration.api)")
        }
        guard var components = URLComponents(string: configuration.baseURL),
              let host = components.host?.lowercased(), let scheme = components.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)) else {
            throw OpenAICompatibleError.invalidConfiguration("Use HTTPS, or HTTP only for localhost AI services.")
        }
        let oldPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ending = configuration.api == "openai-responses" ? "responses" : "messages"
        let prefix = oldPath.isEmpty && configuration.api == "anthropic-messages" ? "v1" : oldPath
        if !prefix.hasSuffix(ending) { components.path = "/" + [prefix, ending].filter { !$0.isEmpty }.joined(separator: "/") }
        guard let url = components.url else { throw OpenAICompatibleError.invalidConfiguration("Invalid model endpoint.") }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUserID = messages.last(where: { $0.role == .user })?.id
        if let currentPDFURL,
           let size = try currentPDFURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 100 * 1_024 * 1_024 {
            throw OpenAICompatibleError.invalidConfiguration("PDF 附件超过 100 MB，请先缩小文件。")
        }
        let pdfData = try currentPDFURL.map { try Data(contentsOf: $0) }
        guard pdfData == nil || lastUserID != nil else {
            throw OpenAICompatibleError.invalidConfiguration("PDF 附件需要一条用户消息。")
        }
        if configuration.api == "anthropic-messages" {
            if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let turns: [[String: Any]] = messages.filter { $0.role != .system }.map { message in
                var content: [[String: Any]] = []
                if !message.content.isEmpty { content.append(["type": "text", "text": message.content]) }
                for image in message.imageAttachments {
                    content.append(["type": "image", "source": ["type": "base64", "media_type": image.mimeType, "data": image.data.base64EncodedString()]])
                }
                if message.id == lastUserID, let pdfData {
                    content.append(["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": pdfData.base64EncodedString()]])
                }
                return ["role": message.role.rawValue, "content": content]
            }
            let system = messages.filter { $0.role == .system }.map(\.content).joined(separator: "\n\n")
            var body: [String: Any] = ["model": configuration.model, "max_tokens": max(1, configuration.maxTokens ?? 4096), "stream": true, "system": system, "messages": turns]
            if let effort = configuration.reasoningEffort, effort != "off" { body["output_config"] = ["effort": effort] }
            if configuration.forceAdaptiveThinking == true { body["thinking"] = ["type": "adaptive"] }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else {
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            let input: [[String: Any]] = messages.map { message in
                let includesPDF = message.id == lastUserID && pdfData != nil
                guard !message.imageAttachments.isEmpty || includesPDF else { return ["role": message.role.rawValue, "content": message.content] }
                var content: [[String: Any]] = []
                if !message.content.isEmpty { content.append(["type": "input_text", "text": message.content]) }
                for image in message.imageAttachments { content.append(["type": "input_image", "image_url": "data:\(image.mimeType);base64,\(image.data.base64EncodedString())"]) }
                if includesPDF, let pdfData, let currentPDFURL {
                    content.append(["type": "input_file", "filename": currentPDFURL.lastPathComponent, "file_data": "data:application/pdf;base64,\(pdfData.base64EncodedString())"])
                }
                return ["role": message.role.rawValue, "content": content]
            }
            var body: [String: Any] = ["model": configuration.model, "stream": true, "input": input]
            if let maxTokens = configuration.maxTokens, maxTokens > 0 { body["max_output_tokens"] = maxTokens }
            if let effort = configuration.reasoningEffort, effort != "off" { body["reasoning"] = ["effort": effort] }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
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
    let reasoningEffort: String?
    let maxTokens: Int?
    let conversationKey: String?
    let conversationTitle: String?
    let pdfAttachments: [RequestPDFAttachment]?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case reasoningEffort = "reasoning_effort"
        case maxTokens = "max_tokens"
        case conversationKey = "conversation_key"
        case conversationTitle = "conversation_title"
        case pdfAttachments = "pdf_attachments"
    }
}

private struct RequestPDFAttachment: Encodable {
    let path: String
    let name: String
    let mimeType: String

    enum CodingKeys: String, CodingKey {
        case path, name
        case mimeType = "mime_type"
    }
}

private struct RequestMessage: Encodable {
    let role: String
    let message: AIChatMessage

    init(_ message: AIChatMessage) {
        role = message.role.rawValue
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case role, content
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        guard !message.imageAttachments.isEmpty else {
            try container.encode(message.content, forKey: .content)
            return
        }
        var content = container.nestedUnkeyedContainer(forKey: .content)
        if !message.content.isEmpty {
            try content.encode(RequestContent.text(message.content))
        }
        for attachment in message.imageAttachments {
            try content.encode(RequestContent.image(attachment))
        }
    }
}

private enum RequestContent: Encodable {
    case text(String)
    case image(AIChatImageAttachment)

    enum CodingKeys: String, CodingKey {
        case type, text, imageURL = "image_url"
    }

    enum ImageURLCodingKeys: String, CodingKey {
        case url
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .image(attachment):
            try container.encode("image_url", forKey: .type)
            var imageURL = container.nestedContainer(
                keyedBy: ImageURLCodingKeys.self,
                forKey: .imageURL
            )
            let url = "data:\(attachment.mimeType);base64,\(attachment.data.base64EncodedString())"
            try imageURL.encode(url, forKey: .url)
        }
    }
}
