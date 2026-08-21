import Foundation

public enum AIChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
}

public struct AIChatMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: AIChatRole
    public var content: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: AIChatRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct AIConversation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var promptPreset: AIPromptPreset
    public var messages: [AIChatMessage]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String = "New conversation",
        promptPreset: AIPromptPreset = .defaultForNewConversation,
        messages: [AIChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.promptPreset = promptPreset
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AIPaperChatHistory: Codable, Sendable, Equatable, Identifiable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var documentTitle: String
    public var documentPath: String
    public var activeConversationID: String
    public var conversations: [AIConversation]

    public var id: String { documentPath }

    public init(
        formatVersion: Int = currentFormatVersion,
        documentTitle: String,
        documentPath: String,
        activeConversationID: String,
        conversations: [AIConversation]
    ) {
        self.formatVersion = formatVersion
        self.documentTitle = documentTitle
        self.documentPath = documentPath
        self.activeConversationID = activeConversationID
        self.conversations = conversations
    }

    public static func new(for documentURL: URL) -> AIPaperChatHistory {
        let conversation = AIConversation()
        return AIPaperChatHistory(
            documentTitle: documentURL.lastPathComponent,
            documentPath: documentURL.standardizedFileURL.path,
            activeConversationID: conversation.id,
            conversations: [conversation]
        )
    }
}

public struct AIProviderConfiguration: Codable, Sendable, Equatable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String = "https://api.openai.com/v1", model: String = "") {
        self.baseURL = baseURL
        self.model = model
    }
}
