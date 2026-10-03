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
        result.append(contentsOf: conversation)
        return result
    }
}
