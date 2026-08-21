import Foundation

public enum AIConversationRouting {
    public static func conversationKey(
        for localConversationID: String,
        configuration: AIProviderConfiguration
    ) -> String? {
        let identifier = localConversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let components = URLComponents(string: configuration.baseURL),
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host),
              components.port == 8199 else {
            return nil
        }

        let routeTargetsQwen = components.path.lowercased().contains("chat.qwen.ai")
        let modelTargetsQwen = configuration.model.lowercased().contains("qwen")
        guard routeTargetsQwen || modelTargetsQwen else { return nil }
        return "pdflight:conversation:\(identifier)"
    }
}
