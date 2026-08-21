import Foundation

public enum OpenAIStreamEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case contentDelta(String)
    case finished
}

public enum OpenAICompatibleError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration(String)
    case invalidResponse
    case missingFinalContent
    case httpStatus(Int, String)
    case service(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message): message
        case .invalidResponse: "The AI provider returned an invalid response."
        case .missingFinalContent: "The model finished thinking but returned no final answer."
        case .httpStatus(let status, let message):
            message.isEmpty ? "The AI provider returned HTTP \(status)." : "HTTP \(status): \(message)"
        case .service(let message): message
        }
    }
}

public struct OpenAIStreamDecoder: Sendable {
    public init() {}

    public mutating func decode(line: String) throws -> OpenAIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .finished }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAICompatibleError.invalidResponse
        }
        let response: StreamResponse
        do {
            response = try JSONDecoder().decode(StreamResponse.self, from: data)
        } catch {
            throw OpenAICompatibleError.invalidResponse
        }
        if let message = response.error?.message, !message.isEmpty {
            throw OpenAICompatibleError.service(message)
        }
        if let reasoning = response.choices?.first?.delta?.reasoningContent,
           !reasoning.isEmpty {
            return .reasoningDelta(reasoning)
        }
        if let content = response.choices?.first?.delta?.content, !content.isEmpty {
            return .contentDelta(content)
        }
        return nil
    }
}

private struct StreamResponse: Decodable {
    let choices: [Choice]?
    let error: ServiceError?
}

private struct Choice: Decodable {
    let delta: Delta?
}

private struct Delta: Decodable {
    let content: String?
    let reasoningContent: String?

    private enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case reasoning
        case thinking
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
            ?? container.decodeIfPresent(String.self, forKey: .reasoning)
            ?? container.decodeIfPresent(String.self, forKey: .thinking)
    }
}

private struct ServiceError: Decodable {
    let message: String
}
