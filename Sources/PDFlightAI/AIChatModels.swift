import Foundation

public enum AIChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
}

public struct AIChatImageAttachment: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var fileName: String
    public var mimeType: String
    public var data: Data

    public init(
        id: String = UUID().uuidString,
        fileName: String,
        mimeType: String,
        data: Data
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }
}

public struct AIChatSubmission: Sendable, Equatable, Identifiable {
    public let id: String
    public var question: String
    public var imageAttachments: [AIChatImageAttachment]
    public var promptPreset: AIPromptPreset
    public var includeCurrentPDF: Bool
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        question: String,
        imageAttachments: [AIChatImageAttachment] = [],
        promptPreset: AIPromptPreset,
        includeCurrentPDF: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.imageAttachments = imageAttachments
        self.promptPreset = promptPreset
        self.includeCurrentPDF = includeCurrentPDF
        self.createdAt = createdAt
    }
}

public struct AIChatSubmissionQueue: Sendable, Equatable {
    public private(set) var submissions: [AIChatSubmission]

    public init(submissions: [AIChatSubmission] = []) {
        self.submissions = submissions
    }

    public var count: Int { submissions.count }
    public var isEmpty: Bool { submissions.isEmpty }

    public mutating func enqueue(_ submission: AIChatSubmission) {
        submissions.append(submission)
    }

    @discardableResult
    public mutating func dequeue() -> AIChatSubmission? {
        guard !submissions.isEmpty else { return nil }
        return submissions.removeFirst()
    }

    @discardableResult
    public mutating func remove(id: String) -> AIChatSubmission? {
        guard let index = submissions.firstIndex(where: { $0.id == id }) else { return nil }
        return submissions.remove(at: index)
    }

    public mutating func removeAll() {
        submissions.removeAll()
    }
}

public struct AIChatMessage: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let role: AIChatRole
    public var content: String
    public var imageAttachments: [AIChatImageAttachment]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: AIChatRole,
        content: String,
        imageAttachments: [AIChatImageAttachment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageAttachments = imageAttachments
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, imageAttachments, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(AIChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        imageAttachments = try container.decodeIfPresent(
            [AIChatImageAttachment].self,
            forKey: .imageAttachments
        ) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        if !imageAttachments.isEmpty {
            try container.encode(imageAttachments, forKey: .imageAttachments)
        }
        try container.encode(createdAt, forKey: .createdAt)
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
    public static let currentFormatVersion = 2

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
