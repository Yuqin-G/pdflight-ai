import CryptoKit
import Foundation
import Darwin

public actor AIChatHistoryStore {
    private struct ImportRecovery: Codable {
        var version = 1
        var documentPath: String
        var conversation: AIConversation
    }
    private struct ImportDeletion: Codable {
        var version = 1
        var documentPath: String
        var conversationID: String
        var requestID: String?
        var wasSucceeded: Bool
        var deletedAt = Date()
    }
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
        var history = try readMainHistory(for: documentURL)
        let deleted = try importDeletions(for: documentURL)
        let deletedIDs = Set(deleted.map(\.conversationID))
        history.conversations.removeAll { deletedIDs.contains($0.id) }
        var recovered: [AIConversation] = []
        let folder = importRecoveryDirectory(for: documentURL)
        if FileManager.default.fileExists(atPath: folder.path) {
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                let record = try decoder.decode(ImportRecovery.self, from: Data(contentsOf: file))
                guard record.version == 1, record.documentPath == documentURL.standardizedFileURL.path,
                      record.conversation.paperImport?.state == "succeeded",
                      record.conversation.messages.contains(where: { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                    throw PaperImportFailure("自动深读恢复记录格式不兼容或不完整，已保留原文件：\(file.lastPathComponent)")
                }
                let conversation = record.conversation
                guard !deletedIDs.contains(conversation.id) else { continue }
                if let index = history.conversations.firstIndex(where: { $0.id == conversation.id }) {
                    // An old window can also overwrite the same ID with its earlier
                    // running/partial snapshot. Restore the completed answer then.
                    if history.conversations[index].paperImport?.state != "succeeded" {
                        var restored = conversation
                        let ids = Set(restored.messages.map(\.id))
                        restored.messages += history.conversations[index].messages.filter { !ids.contains($0.id) }
                        history.conversations[index] = restored
                        recovered.append(restored)
                    }
                } else {
                    history.conversations.append(conversation)
                    recovered.append(conversation)
                }
            }
        }
        // A recovered reading should be directly visible on reopening this PDF.
        if let latest = recovered.max(by: { $0.updatedAt < $1.updatedAt }) { history.activeConversationID = latest.id }
        return normalized(history, for: documentURL)
    }

    private func readMainHistory(for documentURL: URL) throws -> AIPaperChatHistory {
        let fileURL = fileURL(for: documentURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .new(for: documentURL)
        }
        let data = try Data(contentsOf: fileURL)
        if var history = try? decoder.decode(AIPaperChatHistory.self, from: data) {
            guard (1...AIPaperChatHistory.currentFormatVersion).contains(history.formatVersion) else {
                throw PaperImportFailure("聊天记录格式暂不支持，已保留主聊天文件，未用恢复记录覆盖它。")
            }
            history.documentTitle = documentURL.lastPathComponent
            history.documentPath = documentURL.standardizedFileURL.path
            return normalized(history, for: documentURL)
        }

        // Version 0 stored one bare message array per PDF. Reading it here keeps
        // existing chats intact while the next save upgrades them to version 1.
        guard let legacyMessages = try? JSONDecoder().decode([AIChatMessage].self, from: data) else {
            throw PaperImportFailure("主聊天文件无法读取或格式不兼容，原文件与恢复记录均已保留，未自动覆盖。")
        }
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
        return migrated
    }

    public func save(_ history: AIPaperChatHistory, for documentURL: URL, removingConversationIDs: Set<String> = []) throws {
        try withHistoryLock(for: documentURL) {
            var merged = history
            // Older reader windows may not have seen newly appended sessions.
            // Preserve them, while still honoring explicit user deletion.
            if FileManager.default.fileExists(atPath: fileURL(for: documentURL).path)
                || FileManager.default.fileExists(atPath: importRecoveryDirectory(for: documentURL).path) {
                let current = try self.history(for: documentURL)
                for id in removingConversationIDs {
                    if let conversation = current.conversations.first(where: { $0.id == id }), conversation.paperImport != nil {
                        try deleteImportRecovery(conversation, for: documentURL)
                    }
                }
                for conversation in current.conversations where !removingConversationIDs.contains(conversation.id) {
                    if let index = merged.conversations.firstIndex(where: { $0.id == conversation.id }) {
                        if conversation.paperImport == nil {
                            if conversation.updatedAt > merged.conversations[index].updatedAt { merged.conversations[index] = conversation }
                            continue
                        }
                        var incoming = merged.conversations[index]
                        let ids = Set(incoming.messages.map(\.id))
                        incoming.messages += conversation.messages.filter { !ids.contains($0.id) }
                        if conversation.paperImport?.state == "succeeded" && incoming.paperImport?.state != "succeeded" {
                            incoming.paperImport = conversation.paperImport
                            for messageIndex in incoming.messages.indices where incoming.messages[messageIndex].role == .assistant {
                                if let final = conversation.messages.first(where: { $0.id == incoming.messages[messageIndex].id }) {
                                    incoming.messages[messageIndex] = final
                                }
                            }
                        }
                        incoming.updatedAt = max(incoming.updatedAt, conversation.updatedAt)
                        merged.conversations[index] = incoming
                    } else { merged.conversations.append(conversation) }
                }
            }
            try writeHistory(merged, for: documentURL)
        }
    }

    /// Read the latest file under an interprocess lock and change only this session.
    @discardableResult
    public func upsertConversation(_ conversation: AIConversation, for documentURL: URL, select: Bool = false) throws -> AIPaperChatHistory {
        try withHistoryLock(for: documentURL) {
            if try importDeletions(for: documentURL).contains(where: { $0.conversationID == conversation.id }) {
                throw PaperImportFailure("此自动深读会话已被用户删除，不会重新保存或恢复。")
            }
            var current = try history(for: documentURL)
            if let index = current.conversations.firstIndex(where: { $0.id == conversation.id }) {
                var updated = conversation
                let incomingIDs = Set(updated.messages.map(\.id))
                updated.messages += current.conversations[index].messages.filter { !incomingIDs.contains($0.id) }
                current.conversations[index] = updated
            } else { current.conversations.append(conversation) }
            if select { current.activeConversationID = conversation.id }
            try writeHistory(current, for: documentURL)
            return current
        }
    }

    private func withHistoryLock<T>(for documentURL: URL, _ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let lockURL = fileURL(for: documentURL).appendingPathExtension("lock")
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func writeHistory(_ history: AIPaperChatHistory, for documentURL: URL) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var safe = history
        let deletedIDs = Set(try importDeletions(for: documentURL).map(\.conversationID))
        safe.conversations.removeAll { deletedIDs.contains($0.id) }
        // Sidecars are independent of the legacy main JSON and published first.
        // If either write fails, the caller must not report a successful import.
        for conversation in safe.conversations where conversation.paperImport?.state == "succeeded" {
            guard conversation.messages.contains(where: { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw PaperImportFailure("成功的自动深读会话缺少最终回答，未写入恢复记录。")
            }
            let folder = importRecoveryDirectory(for: documentURL)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = importRecoveryURL(conversation.id, for: documentURL)
            try encoder.encode(ImportRecovery(documentPath: documentURL.standardizedFileURL.path, conversation: conversation)).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let data = try encoder.encode(normalized(safe, for: documentURL))
        try data.write(to: fileURL(for: documentURL), options: .atomic)
    }

    private func importRecoveryDirectory(for documentURL: URL) -> URL {
        directoryURL.appendingPathComponent("paper-import-recovery", isDirectory: true)
            .appendingPathComponent(fileURL(for: documentURL).deletingPathExtension().lastPathComponent, isDirectory: true)
    }

    private func importRecoveryURL(_ conversationID: String, for documentURL: URL) -> URL {
        let key = SHA256.hash(data: Data(conversationID.utf8)).map { String(format: "%02x", $0) }.joined()
        return importRecoveryDirectory(for: documentURL).appendingPathComponent(key + ".json")
    }

    private func importDeletions(for documentURL: URL) throws -> [ImportDeletion] {
        let folder = importRecoveryDirectory(for: documentURL)
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "deleted" }.map { file in
                let deletion = try decoder.decode(ImportDeletion.self, from: Data(contentsOf: file))
                guard deletion.version == 1, deletion.documentPath == documentURL.standardizedFileURL.path else {
                    throw PaperImportFailure("自动深读删除记录无法读取，已保留原文件，未恢复会话。")
                }
                return deletion
            }
    }

    private func deleteImportRecovery(_ conversation: AIConversation, for documentURL: URL) throws {
        let folder = importRecoveryDirectory(for: documentURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = importRecoveryURL(conversation.id, for: documentURL)
        let deletion = ImportDeletion(documentPath: documentURL.standardizedFileURL.path, conversationID: conversation.id,
                                      requestID: conversation.paperImport?.requestID, wasSucceeded: conversation.paperImport?.state == "succeeded")
        // Publish the tombstone before removing the backup or writing the main
        // file, so neither a crash nor a stale window can resurrect this session.
        try encoder.encode(deletion).write(to: url.deletingPathExtension().appendingPathExtension("deleted"), options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// A success receipt survives intentional deletion, without restoring content
    /// or issuing a second paid request when the same requestID is re-enqueued.
    public func deletedCompletedPaperImport(requestID: String, for documentURL: URL) throws -> String? {
        try importDeletions(for: documentURL).first {
            $0.wasSucceeded && $0.requestID?.lowercased() == requestID.lowercased()
        }?.conversationID
    }

    public func importHarnessIfNeeded(for documentURL: URL, dataDirectory: URL, pathMappingsURL: URL?, draftDirectory: URL? = nil, recoveredArchivesDirectory: URL? = nil, projectionDirectory: URL? = nil) throws -> AIPaperChatHistory {
        let documentKey = fileURL(for: documentURL).deletingPathExtension().lastPathComponent
        let marker = directoryURL.appendingPathComponent("harness-originals", isDirectory: true)
            .appendingPathComponent(documentKey, isDirectory: true).appendingPathComponent(".migration-complete")
        if FileManager.default.fileExists(atPath: marker.path) { return try history(for: documentURL) }
        let prepared = try HarnessChatImport.prepare(documentURL: documentURL, dataDirectory: dataDirectory, pathMappingsURL: pathMappingsURL, recoveredArchivesDirectory: recoveredArchivesDirectory, projectionDirectory: projectionDirectory)
        guard prepared.paperID != nil else { return try history(for: documentURL) }
        var merged = try importHarness(prepared, for: documentURL)
        var incompleteDraftImport = false
        if let draftDirectory, FileManager.default.fileExists(atPath: draftDirectory.path) {
            var candidates: [String: Set<Data>] = [:]
            let relevantIDs = Set(merged.conversations.map(\.id))
            let files = try FileManager.default.contentsOfDirectory(at: draftDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                guard let raw = try? Data(contentsOf: file),
                      let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
                      let drafts = object["drafts"] as? [[String: Any]] else { continue }
                for entry in drafts {
                    guard let id = entry["sessionId"] as? String, relevantIDs.contains(id),
                          let draft = entry["draft"] as? [String: Any],
                          let text = draft["text"] as? String, !text.isEmpty else { continue }
                    let referenceData = try JSONSerialization.data(withJSONObject: draft["references"] as? [Any] ?? [])
                    guard let references = try? JSONDecoder().decode([AIChatDraftReference].self, from: referenceData) else { incompleteDraftImport = true; continue }
                    let source = text as NSString
                    var lastEnd = 0
                    guard references.allSatisfy({ reference in
                        guard reference.offset >= lastEnd, reference.length > 0,
                              reference.offset <= source.length, reference.length <= source.length - reference.offset,
                              source.substring(with: NSRange(location: reference.offset, length: reference.length)) == reference.clipboardText else { return false }
                        lastEnd = reference.offset + reference.length
                        return true
                    }) else { incompleteDraftImport = true; continue }
                    let command = (draft["command"] as? [String: Any]).flatMap { $0["token"] as? String }.map(AIChatDraftCommand.init(token:))
                    let converted = AIChatDraft(text: text, references: references.isEmpty ? nil : references, command: command)
                    let draftEncoder = JSONEncoder(); draftEncoder.outputFormatting = [.sortedKeys]
                    candidates[id, default: []].insert(try draftEncoder.encode(converted))
                }
            }
            var changed = false
            for index in merged.conversations.indices {
                let conversation = merged.conversations[index]
                if conversation.draft == nil, let values = candidates[conversation.id], values.count > 1 { incompleteDraftImport = true }
                guard conversation.draft == nil, let values = candidates[conversation.id], values.count == 1,
                      let data = values.first, let draft = try? JSONDecoder().decode(AIChatDraft.self, from: data) else { continue }
                merged.conversations[index].draft = draft
                changed = true
            }
            if changed { try save(merged, for: documentURL) }
        }
        // Keep retrying any sessions whose source files were incomplete or
        // unsupported; their originals remain in Harness untouched.
        if prepared.skippedSessionIDs.isEmpty && !incompleteDraftImport {
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
                let document = Foundation.URL(fileURLWithPath: history.documentPath)
                if FileManager.default.fileExists(atPath: importRecoveryDirectory(for: document).path) {
                    return try? self.history(for: document)
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
        try withHistoryLock(for: documentURL) {
            let current = try history(for: documentURL)
            for conversation in current.conversations where conversation.paperImport != nil {
                try deleteImportRecovery(conversation, for: documentURL)
            }
            let fileURL = fileURL(for: documentURL)
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
        }
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
