import Foundation

public enum AIChatRole: String, Codable, Sendable, Equatable {
    case system
    case user
    case assistant
    case tool
}

public struct AIChatToolEvent: Codable, Sendable, Equatable {
    public var name: String
    public var arguments: String
    public var result: String?
    public var isError: Bool
    public var callID: String?
    public init(name: String, arguments: String, result: String? = nil, isError: Bool = false, callID: String? = nil) {
        self.name = name; self.arguments = arguments; self.result = result; self.isError = isError; self.callID = callID
    }
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
    public var additionalPDFPaths: [String]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        question: String,
        imageAttachments: [AIChatImageAttachment] = [],
        promptPreset: AIPromptPreset,
        includeCurrentPDF: Bool = false,
        additionalPDFPaths: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.question = question
        self.imageAttachments = imageAttachments
        self.promptPreset = promptPreset
        self.includeCurrentPDF = includeCurrentPDF
        self.additionalPDFPaths = additionalPDFPaths
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
    public var pdfAttachmentName: String?
    public var additionalPDFNames: [String]?
    public var reasoning: String?
    public var toolEvent: AIChatToolEvent?
    public var toolCalls: [AIChatToolCall]?
    public var feedback: String?
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: AIChatRole,
        content: String,
        imageAttachments: [AIChatImageAttachment] = [],
        createdAt: Date = Date(),
        reasoning: String? = nil,
        toolEvent: AIChatToolEvent? = nil,
        pdfAttachmentName: String? = nil,
        additionalPDFNames: [String]? = nil,
        toolCalls: [AIChatToolCall]? = nil,
        feedback: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.imageAttachments = imageAttachments
        self.pdfAttachmentName = pdfAttachmentName
        self.additionalPDFNames = additionalPDFNames
        self.createdAt = createdAt
        self.reasoning = reasoning
        self.toolEvent = toolEvent
        self.toolCalls = toolCalls
        self.feedback = feedback
    }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, imageAttachments, createdAt, reasoning, toolEvent, pdfAttachmentName, additionalPDFNames, toolCalls, feedback
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
        pdfAttachmentName = try container.decodeIfPresent(String.self, forKey: .pdfAttachmentName)
        additionalPDFNames = try container.decodeIfPresent([String].self, forKey: .additionalPDFNames)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        toolEvent = try container.decodeIfPresent(AIChatToolEvent.self, forKey: .toolEvent)
        toolCalls = try container.decodeIfPresent([AIChatToolCall].self, forKey: .toolCalls)
        feedback = try container.decodeIfPresent(String.self, forKey: .feedback)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        if !imageAttachments.isEmpty {
            try container.encode(imageAttachments, forKey: .imageAttachments)
        }
        try container.encodeIfPresent(pdfAttachmentName, forKey: .pdfAttachmentName)
        try container.encodeIfPresent(additionalPDFNames, forKey: .additionalPDFNames)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(toolEvent, forKey: .toolEvent)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(feedback, forKey: .feedback)
    }
}

public enum AIChatAccessMode: String, Codable, Sendable, CaseIterable {
    case readOnly = "read-only"
    case fullAccess = "full-access"

    public var title: String {
        switch self {
        case .readOnly: return "仅可查看"
        case .fullAccess: return "完全权限"
        }
    }
}

public struct AIConversation: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var title: String
    public var promptPreset: AIPromptPreset
    public var messages: [AIChatMessage]
    public let createdAt: Date
    public var updatedAt: Date
    public var draft: AIChatDraft?
    public var modelRouteID: String?
    public var webConversationKey: String?
    public var webConversationURL: String?
    public var reasoningEffort: String?
    public var accessMode: AIChatAccessMode?

    public init(
        id: String = UUID().uuidString,
        title: String = "New conversation",
        promptPreset: AIPromptPreset = .defaultForNewConversation,
        messages: [AIChatMessage] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        draft: AIChatDraft? = nil,
        modelRouteID: String? = nil,
        webConversationKey: String? = nil,
        webConversationURL: String? = nil,
        reasoningEffort: String? = nil,
        accessMode: AIChatAccessMode? = nil
    ) {
        self.id = id
        self.title = title
        self.promptPreset = promptPreset
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.draft = draft
        self.modelRouteID = modelRouteID
        self.webConversationKey = webConversationKey
        self.webConversationURL = webConversationURL
        self.reasoningEffort = reasoningEffort
        self.accessMode = accessMode
    }
}

public struct AIChatDraft: Codable, Sendable, Equatable {
    public var text: String
    public var imageAttachments: [AIChatImageAttachment]
    public var includeCurrentPDF: Bool
    public var additionalPDFPaths: [String]?
    public init(text: String = "", imageAttachments: [AIChatImageAttachment] = [], includeCurrentPDF: Bool = false, additionalPDFPaths: [String]? = nil) {
        self.text = text; self.imageAttachments = imageAttachments; self.includeCurrentPDF = includeCurrentPDF
        self.additionalPDFPaths = additionalPDFPaths
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
    public var api: String
    public var reasoningEffort: String?
    public var forceAdaptiveThinking: Bool?
    public var maxTokens: Int?

    public init(baseURL: String = "https://api.openai.com/v1", model: String = "", api: String = "openai-completions", reasoningEffort: String? = nil, forceAdaptiveThinking: Bool? = nil, maxTokens: Int? = nil) {
        self.baseURL = baseURL
        self.model = model
        self.api = api
        self.reasoningEffort = reasoningEffort
        self.forceAdaptiveThinking = forceAdaptiveThinking
        self.maxTokens = maxTokens
    }

    private enum CodingKeys: String, CodingKey { case baseURL, model, api, reasoningEffort, forceAdaptiveThinking, maxTokens }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        api = try c.decodeIfPresent(String.self, forKey: .api) ?? "openai-completions"
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        forceAdaptiveThinking = try c.decodeIfPresent(Bool.self, forKey: .forceAdaptiveThinking)
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens)
    }
}
