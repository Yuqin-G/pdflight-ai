import CryptoKit
import Foundation

public actor AIChatHistoryStore {
    private let directoryURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public nonisolated var storageDirectoryURL: URL { directoryURL }

    /// The portable JSON file used for one PDF's conversations.
    ///
    /// Exposing this URL lets the app reveal the current paper's record in
    /// Finder without duplicating the stable path-hashing scheme.
    public nonisolated func fileURL(for documentURL: URL) -> URL {
        let identity = documentURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directoryURL.appendingPathComponent("\(digest).json")
    }

    /// Drafts use their own atomic sidecar so the latest edit survives even
    /// when a window closes before an asynchronous history save finishes.
    public nonisolated func saveDraft(_ draft: AIChatDraft, sessionID: String, for documentURL: URL) throws {
        let url = try draftURL(sessionID: sessionID, documentURL: documentURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public nonisolated func readDraft(sessionID: String, for documentURL: URL) throws -> AIChatDraft? {
        let url = try draftURL(sessionID: sessionID, documentURL: documentURL)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(AIChatDraft.self, from: Data(contentsOf: url))
    }

    private nonisolated func draftURL(sessionID: String, documentURL: URL) throws -> URL {
        guard sessionID.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return directoryURL.appendingPathComponent("drafts", isDirectory: true)
            .appendingPathComponent(fileURL(for: documentURL).deletingPathExtension().lastPathComponent, isDirectory: true)
            .appendingPathComponent(sessionID + ".json")
    }

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
        let fileURL = fileURL(for: documentURL)
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
        try data.write(to: fileURL(for: documentURL), options: .atomic)
    }

    public func importHarnessIfNeeded(for documentURL: URL, dataDirectory: URL, pathMappingsURL: URL?, draftDirectory: URL? = nil, recoveredArchivesDirectory: URL? = nil, projectionDirectory: URL? = nil) throws -> AIPaperChatHistory {
        let documentKey = fileURL(for: documentURL).deletingPathExtension().lastPathComponent
        let marker = directoryURL.appendingPathComponent("harness-originals", isDirectory: true)
            .appendingPathComponent(documentKey, isDirectory: true).appendingPathComponent(".migration-complete")
        if FileManager.default.fileExists(atPath: marker.path) { return try history(for: documentURL) }
        let prepared = try HarnessChatImport.prepare(documentURL: documentURL, dataDirectory: dataDirectory, pathMappingsURL: pathMappingsURL, recoveredArchivesDirectory: recoveredArchivesDirectory, projectionDirectory: projectionDirectory)
        guard prepared.paperID != nil else { return try history(for: documentURL) }
        var merged = try importHarness(prepared, for: documentURL)
        if let draftDirectory, FileManager.default.fileExists(atPath: draftDirectory.path) {
            var candidates: [String: Set<String>] = [:]
            let files = try FileManager.default.contentsOfDirectory(at: draftDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                guard let raw = try? Data(contentsOf: file),
                      let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let drafts = object["drafts"] as? [[String: Any]] else { continue }
                for entry in drafts {
                    guard let id = entry["sessionId"] as? String,
                          let draft = entry["draft"] as? [String: Any],
                          let text = draft["text"] as? String, !text.isEmpty,
                          (draft["references"] as? [Any] ?? []).isEmpty else { continue }
                    candidates[id, default: []].insert(text)
                }
            }
            var changed = false
            for index in merged.conversations.indices {
                let conversation = merged.conversations[index]
                guard conversation.draft == nil, let values = candidates[conversation.id], values.count == 1,
                      let text = values.first else { continue }
                merged.conversations[index].draft = AIChatDraft(text: text)
                changed = true
            }
            if changed { try save(merged, for: documentURL) }
        }
        // Keep retrying any sessions whose source files were incomplete or
        // unsupported; their originals remain in Harness untouched.
        if prepared.skippedSessionIDs.isEmpty {
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try Data("1\n".utf8).write(to: marker, options: .atomic)
        }
        return merged
    }

    /// Merge prepared Harness conversations without overwriting existing local
    /// sessions. Keep each complete source archive as a private sidecar before
    /// writing the converted history; re-running this operation is idempotent.
    public func importHarness(_ result: HarnessChatImport.Result, for documentURL: URL) throws -> AIPaperChatHistory {
        var history = try history(for: documentURL)
        var existing = Set(history.conversations.map(\.id))
        guard !result.conversations.isEmpty else { return history }
        let backupDirectory = directoryURL.appendingPathComponent("harness-originals", isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let documentKey = fileURL(for: documentURL).deletingPathExtension().lastPathComponent
        let documentBackups = backupDirectory.appendingPathComponent(documentKey, isDirectory: true)
        try FileManager.default.createDirectory(at: documentBackups, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var changed = false
        for item in result.conversations {
            let backup = documentBackups.appendingPathComponent(item.value.id + ".json")
            if FileManager.default.fileExists(atPath: backup.path) {
                guard try Data(contentsOf: backup) == item.sourceArchive else {
                    throw CocoaError(.fileWriteFileExists)
                }
            } else {
                let temporary = documentBackups.appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try item.sourceArchive.write(to: temporary, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                // A hard link publishes the completed file exclusively, so a
                // competing importer cannot replace an existing backup.
                try FileManager.default.linkItem(at: temporary, to: backup)
            }
            guard existing.insert(item.value.id).inserted else { continue }
            history.conversations.append(item.value)
            changed = true
        }
        guard changed else { return history }
        // Only replace the disposable initial blank conversation; keep an
        // existing local active session and all of its unsent history intact.
        if history.conversations.count > 1, let first = history.conversations.first,
           first.title == "New conversation", first.messages.isEmpty,
           history.activeConversationID == first.id,
           let active = result.activeSessionID, existing.contains(active) {
            history.conversations.removeFirst()
            history.activeConversationID = active
        }
        try save(history, for: documentURL)
        return history
    }

    /// Merge an older PDFlight per-paper history into the independent store.
    /// Existing conversations win on ID collision; conflicting legacy IDs get
    /// a distinct ID, so neither side can overwrite the other.
    public func mergeLegacy(_ legacy: AIPaperChatHistory, for documentURL: URL) throws -> AIPaperChatHistory {
        if !FileManager.default.fileExists(atPath: fileURL(for: documentURL).path) {
            try save(legacy, for: documentURL)
            return try history(for: documentURL)
        }
        var current = try history(for: documentURL)
        var changed = false
        for old in legacy.conversations {
            if let present = current.conversations.first(where: { $0.id == old.id }) {
                if try encoder.encode(present) == encoder.encode(old) { continue }
                let duplicate = AIConversation(id: "legacy-" + old.id, title: old.title, promptPreset: old.promptPreset,
                    messages: old.messages, createdAt: old.createdAt, updatedAt: old.updatedAt, draft: old.draft,
                    modelRouteID: old.modelRouteID, webConversationKey: old.webConversationKey, webConversationURL: old.webConversationURL,
                    reasoningEffort: old.reasoningEffort)
                if let prior = current.conversations.first(where: { $0.id == duplicate.id }) {
                    guard try encoder.encode(prior) == encoder.encode(duplicate) else { throw CocoaError(.fileWriteFileExists) }
                    continue
                }
                current.conversations.append(duplicate)
            } else {
                current.conversations.append(old)
            }
            changed = true
        }
        if changed { try save(current, for: documentURL) }
        return current
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
        let fileURL = fileURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
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
