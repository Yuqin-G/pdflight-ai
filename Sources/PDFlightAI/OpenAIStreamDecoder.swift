import Foundation

public enum OpenAIStreamEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case contentDelta(String)
    case toolCallDeltas([AIChatToolCallDelta], content: String?, reasoning: String?)
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
    private let api: String
    private var argumentDeltasSeen: Set<Int> = []
    public init(api: String = "openai-completions") { self.api = api }

    public mutating func decode(line: String) throws -> OpenAIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .finished }

        guard let data = payload.data(using: .utf8) else {
            throw OpenAICompatibleError.invalidResponse
        }
        if api != "openai-completions" {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String else { throw OpenAICompatibleError.invalidResponse }
            if type == "response.output_text.delta", let delta = object["delta"] as? String { return .contentDelta(delta) }
            if type == "response.reasoning_summary_text.delta", let delta = object["delta"] as? String { return .reasoningDelta(delta) }
            if type == "response.output_item.added", let item = object["item"] as? [String: Any], item["type"] as? String == "function_call" {
                let index = object["output_index"] as? Int ?? 0
                return .toolCallDeltas([.init(index: index, id: item["call_id"] as? String, name: item["name"] as? String, arguments: item["arguments"] as? String)], content: nil, reasoning: nil)
            }
            if type == "response.function_call_arguments.delta", let delta = object["delta"] as? String {
                let index = object["output_index"] as? Int ?? 0; argumentDeltasSeen.insert(index)
                return .toolCallDeltas([.init(index: index, arguments: delta)], content: nil, reasoning: nil)
            }
            if type == "response.function_call_arguments.done", let arguments = object["arguments"] as? String {
                let index = object["output_index"] as? Int ?? 0
                if !argumentDeltasSeen.contains(index) { return .toolCallDeltas([.init(index: index, arguments: arguments)], content: nil, reasoning: nil) }
            }
            if type == "content_block_start", let block = object["content_block"] as? [String: Any], block["type"] as? String == "tool_use" {
                let index = object["index"] as? Int ?? 0
                return .toolCallDeltas([.init(index: index, id: block["id"] as? String, name: block["name"] as? String)], content: nil, reasoning: nil)
            }
            if type == "response.completed" || type == "message_stop" { return .finished }
            if type == "content_block_delta", let delta = object["delta"] as? [String: Any] {
                if delta["type"] as? String == "text_delta", let text = delta["text"] as? String { return .contentDelta(text) }
                if delta["type"] as? String == "thinking_delta", let text = delta["thinking"] as? String { return .reasoningDelta(text) }
                if delta["type"] as? String == "input_json_delta", let text = delta["partial_json"] as? String {
                    return .toolCallDeltas([.init(index: object["index"] as? Int ?? 0, arguments: text)], content: nil, reasoning: nil)
                }
            }
            if type == "error" || type == "response.failed" {
                let response = object["response"] as? [String: Any]
                let error = (object["error"] as? [String: Any]) ?? (response?["error"] as? [String: Any])
                throw OpenAICompatibleError.service(error?["message"] as? String ?? "The model request failed.")
            }
            return nil
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
        if let calls = response.choices?.first?.delta?.toolCalls, !calls.isEmpty {
            let deltas = calls.enumerated().map { offset, call in
                AIChatToolCallDelta(index: call.index ?? offset, id: call.id, name: call.function?.name, arguments: call.function?.arguments)
            }
            return .toolCallDeltas(deltas, content: response.choices?.first?.delta?.content, reasoning: response.choices?.first?.delta?.reasoningContent)
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
    let toolCalls: [StreamToolCall]?

    private enum CodingKeys: String, CodingKey {
        case content
        case reasoningContent = "reasoning_content"
        case reasoning
        case thinking
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        reasoningContent = try container.decodeIfPresent(String.self, forKey: .reasoningContent)
            ?? container.decodeIfPresent(String.self, forKey: .reasoning)
            ?? container.decodeIfPresent(String.self, forKey: .thinking)
        toolCalls = try container.decodeIfPresent([StreamToolCall].self, forKey: .toolCalls)
    }
}

private struct StreamToolCall: Decodable {
    let index: Int?
    let id: String?
    let function: StreamToolFunction?
}

private struct StreamToolFunction: Decodable {
    let name: String?
    let arguments: String?
}

private struct ServiceError: Decodable {
    let message: String
}
