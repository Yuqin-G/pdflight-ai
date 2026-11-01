import Foundation

/// The single boundary where visible chat history becomes an API request.
/// Keeping this in PDFlightAI makes hidden prompt/context behavior testable.
public enum AIChatRequestBuilder {
    public static func needsPaperContext(for preset: AIPromptPreset) -> Bool {
        false
    }

    /// Resolves the visible user turn without turning an attachment into a
    /// hidden instruction. Prompt modes remain independent system messages.
    public static func displayQuestion(
        question: String,
        template: AIPromptTemplate,
        hasImageAttachments: Bool,
        includeCurrentPDF: Bool
    ) -> String? {
        if let displayQuestion = template.displayQuestion(for: question) {
            return displayQuestion
        }
        if includeCurrentPDF { return "Attached PDF" }
        if hasImageAttachments { return "Attached image" }
        return nil
    }

    public static func messages(
        preset: AIPromptPreset,
        title: String,
        paperContext: PaperContext?,
        conversation: [AIChatMessage]
    ) -> [AIChatMessage] {
        messages(
            instruction: preset.instruction(title: title),
            paperContext: paperContext,
            conversation: conversation
        )
    }

    public static func messages(
        instruction: String?,
        paperContext: PaperContext?,
        conversation: [AIChatMessage]
    ) -> [AIChatMessage] {
        var result: [AIChatMessage] = []
        if let instruction,
           !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(AIChatMessage(role: .system, content: instruction))
        }
        let visible = conversation.filter { message in
            if message.role == .tool { return !(message.toolEvent?.callID ?? "").isEmpty }
            if message.role == .assistant && message.content.isEmpty { return !(message.toolCalls ?? []).isEmpty }
            return true
        }
        var pending: [AIChatToolCall] = []
        func finishInterruptedCalls() {
            for call in pending {
                result.append(AIChatMessage(role: .tool, content: "", toolEvent: .init(name: call.name, arguments: call.arguments,
                    result: "工具调用中断，未返回结果。", isError: true, callID: call.id)))
            }
            pending.removeAll()
        }
        for message in visible {
            if message.role == .tool {
                guard let id = message.toolEvent?.callID, pending.contains(where: { $0.id == id }) else { continue }
                result.append(message); pending.removeAll { $0.id == id }
            } else {
                finishInterruptedCalls()
                result.append(message)
                pending = message.toolCalls ?? []
            }
        }
        finishInterruptedCalls()
        return result
    }
}
