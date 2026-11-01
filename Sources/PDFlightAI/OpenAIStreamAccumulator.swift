import Foundation

public enum OpenAIStreamProgress: Sendable, Equatable {
    case thinking(reasoningCharacters: Int)
    case answering(receivedCharacters: Int)
    case toolCalling
    case finished
}

public struct OpenAIStreamAccumulator: Sendable {
    public private(set) var content = ""
    public private(set) var reasoningCharacters = 0
    public private(set) var reasoning = ""
    private var callsByIndex: [Int: AIChatToolCall] = [:]
    public var toolCalls: [AIChatToolCall] { callsByIndex.keys.sorted().compactMap { callsByIndex[$0] } }

    public init() {}

    public mutating func consume(_ event: OpenAIStreamEvent) -> OpenAIStreamProgress {
        switch event {
        case .reasoningDelta(let reasoning):
            reasoningCharacters += reasoning.count
            self.reasoning += reasoning
            return .thinking(reasoningCharacters: reasoningCharacters)
        case .contentDelta(let delta):
            content += delta
            return .answering(receivedCharacters: content.count)
        case let .toolCallDeltas(deltas, text, thought):
            for delta in deltas {
                var call = callsByIndex[delta.index] ?? AIChatToolCall(id: "", name: "", arguments: "")
                if let id = delta.id, id != call.id { call.id += id }
                if let name = delta.name, name != call.name { call.name += name }
                if let arguments = delta.arguments { call.arguments += arguments }
                callsByIndex[delta.index] = call
            }
            if let text { content += text }
            if let thought { reasoning += thought; reasoningCharacters += thought.count }
            if text?.isEmpty == false { return .answering(receivedCharacters: content.count) }
            if thought?.isEmpty == false { return .thinking(reasoningCharacters: reasoningCharacters) }
            return .toolCalling
        case .finished:
            return .finished
        }
    }

    public func finalAnswer() throws -> String {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw reasoningCharacters > 0
                ? OpenAICompatibleError.missingFinalContent
                : OpenAICompatibleError.invalidResponse
        }
        return content
    }
}
