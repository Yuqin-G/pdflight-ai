import Foundation

public enum AIChatAgentEvent: Sendable, Equatable {
    case modelDelta(OpenAIStreamEvent)
    case assistantCompleted(AIChatMessage)
    case toolStarted(AIChatToolCall)
    case toolCompleted(AIChatMessage)
}

/// Runs model/tool rounds until the model supplies a final answer. Model and
/// tool transports are injected so the complete loop can be tested offline.
public enum AIChatAgentRunner {
    public typealias Model = @Sendable ([AIChatMessage], Int) -> AsyncThrowingStream<OpenAIStreamEvent, Error>
    public typealias Tool = @Sendable (AIChatToolCall) async -> AIChatToolResult

    public static func run(
        messages: [AIChatMessage],
        maximumRounds: Int = 12,
        model: @escaping Model,
        execute: @escaping Tool
    ) -> AsyncThrowingStream<AIChatAgentEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var transcript = messages
                    for round in 0..<max(1, maximumRounds) {
                        try Task.checkCancellation()
                        var accumulator = OpenAIStreamAccumulator()
                        for try await event in model(transcript, round) {
                            try Task.checkCancellation()
                            _ = accumulator.consume(event)
                            if event != .finished { continuation.yield(.modelDelta(event)) }
                        }
                        let calls = accumulator.toolCalls
                        if calls.isEmpty {
                            let answer = try accumulator.finalAnswer()
                            continuation.yield(.assistantCompleted(AIChatMessage(role: .assistant, content: answer, reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning)))
                            continuation.finish()
                            return
                        }
                        guard calls.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }), Set(calls.map(\.id)).count == calls.count else {
                            throw OpenAICompatibleError.service("模型返回了缺少标识或名称的工具调用。")
                        }
                        let assistant = AIChatMessage(role: .assistant, content: accumulator.content, reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning, toolCalls: calls)
                        transcript.append(assistant)
                        continuation.yield(.assistantCompleted(assistant))
                        for call in calls {
                            try Task.checkCancellation()
                            continuation.yield(.toolStarted(call))
                            let result = await execute(call)
                            try Task.checkCancellation()
                            let message = AIChatMessage(role: .tool, content: "", toolEvent: .init(name: call.name, arguments: call.arguments, result: result.content, isError: result.isError, callID: call.id))
                            transcript.append(message)
                            continuation.yield(.toolCompleted(message))
                        }
                    }
                    throw OpenAICompatibleError.service("工具调用轮数已达到上限，请继续对话以执行后续步骤。")
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
