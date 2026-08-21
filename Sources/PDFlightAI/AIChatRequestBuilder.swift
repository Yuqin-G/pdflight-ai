import Foundation

/// The single boundary where visible chat history becomes an API request.
/// Keeping this in PDFlightAI makes hidden prompt/context behavior testable.
public enum AIChatRequestBuilder {
    public static func needsPaperContext(for preset: AIPromptPreset) -> Bool {
        false
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
        result.append(contentsOf: conversation)
        return result
    }
}
