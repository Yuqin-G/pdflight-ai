import Foundation

public enum OpenAIStreamProgress: Sendable, Equatable {
    case thinking(reasoningCharacters: Int)
    case answering(receivedCharacters: Int)
    case finished
}

public struct OpenAIStreamAccumulator: Sendable {
    public private(set) var content = ""
    public private(set) var reasoningCharacters = 0

    public init() {}

    public mutating func consume(_ event: OpenAIStreamEvent) -> OpenAIStreamProgress {
        switch event {
        case .reasoningDelta(let reasoning):
            reasoningCharacters += reasoning.count
            return .thinking(reasoningCharacters: reasoningCharacters)
        case .contentDelta(let delta):
            content += delta
            return .answering(receivedCharacters: content.count)
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
