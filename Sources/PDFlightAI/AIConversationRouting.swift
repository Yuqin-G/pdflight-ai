import Foundation

public enum AIConversationRouting {
    /// Models reached through the local browser gateway must receive the
    /// user's actual text, without an injected agent/tool protocol.
    public static func usesWebGateway(_ configuration: AIProviderConfiguration) -> Bool {
        guard let components = URLComponents(string: configuration.baseURL),
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host) else { return false }
        if components.port == 8199 { return true }
        return components.port == 3425 && configuration.model.lowercased().hasPrefix("uwa-lite-local/")
    }

    public static func conversationKey(
        for localConversationID: String,
        configuration: AIProviderConfiguration
    ) -> String? {
        let identifier = localConversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              let components = URLComponents(string: configuration.baseURL),
              let host = components.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host),
              [8199, 3425].contains(components.port ?? -1) else {
            return nil
        }

        let routeTargetsQwen = components.path.lowercased().contains("chat.qwen.ai")
        let modelTargetsQwen = configuration.model.lowercased().contains("qwen")
        if components.port == 3425 && !configuration.model.lowercased().hasPrefix("uwa-lite-local/") { return nil }
        guard routeTargetsQwen || modelTargetsQwen else { return nil }
        return "pdflight:conversation:\(identifier)"
    }
}
