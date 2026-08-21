import CryptoKit
import Foundation

public actor AIChatHistoryStore {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public nonisolated var storageDirectoryURL: URL { directoryURL }

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = dateFormatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected an ISO-8601 date with fractional seconds."
                )
            }
            return date
        }
        self.decoder = decoder
    }

    public func history(for documentURL: URL) throws -> AIPaperChatHistory {
        let fileURL = historyURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .new(for: documentURL)
        }
        let data = try Data(contentsOf: fileURL)
        if var history = try? decoder.decode(AIPaperChatHistory.self, from: data) {
            history.documentTitle = documentURL.lastPathComponent
            history.documentPath = documentURL.standardizedFileURL.path
            return normalized(history, for: documentURL)
        }

        // Version 0 stored one bare message array per PDF. Reading it here keeps
        // existing chats intact while the next save upgrades them to version 1.
        let legacyMessages = try JSONDecoder().decode([AIChatMessage].self, from: data)
        let timestamp = legacyMessages.last?.createdAt ?? Date()
        let conversation = AIConversation(
            title: "Previous conversation",
            promptPreset: .none,
            messages: legacyMessages,
            createdAt: legacyMessages.first?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        let migrated = AIPaperChatHistory(
            documentTitle: documentURL.lastPathComponent,
            documentPath: documentURL.standardizedFileURL.path,
            activeConversationID: conversation.id,
            conversations: [conversation]
        )
        try save(migrated, for: documentURL)
        return migrated
    }

    public func save(_ history: AIPaperChatHistory, for documentURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(normalized(history, for: documentURL))
        try data.write(to: historyURL(for: documentURL), options: .atomic)
    }

    public func allHistories() throws -> [AIPaperChatHistory] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else { return [] }
        let URLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return URLs
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { URL in
                guard let data = try? Data(contentsOf: URL),
                      let history = try? decoder.decode(AIPaperChatHistory.self, from: data) else {
                    return nil
                }
                return history
            }
            .sorted { lhs, rhs in
                let left = lhs.conversations.map(\.updatedAt).max() ?? .distantPast
                let right = rhs.conversations.map(\.updatedAt).max() ?? .distantPast
                return left > right
            }
    }

    public func clear(for documentURL: URL) throws {
        let fileURL = historyURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private func historyURL(for documentURL: URL) -> URL {
        let identity = documentURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).json")
    }

    private func normalized(
        _ source: AIPaperChatHistory,
        for documentURL: URL
    ) -> AIPaperChatHistory {
        var history = source
        history.formatVersion = AIPaperChatHistory.currentFormatVersion
        history.documentTitle = documentURL.lastPathComponent
        history.documentPath = documentURL.standardizedFileURL.path
        if history.conversations.isEmpty {
            let conversation = AIConversation()
            history.conversations = [conversation]
            history.activeConversationID = conversation.id
        } else if !history.conversations.contains(where: { $0.id == history.activeConversationID }) {
            history.activeConversationID = history.conversations[0].id
        }
        return history
    }
}
