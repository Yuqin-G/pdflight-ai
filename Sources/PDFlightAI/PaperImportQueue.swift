import Foundation
import Darwin

public struct PaperImportRequest: Codable, Sendable {
    public var version: Int
    public var requestID: String
    public var action: String
    public var groupID: String
    public var pdfPath: String
    public var title: String
    public var prompt: String

    public init(requestID: String = UUID().uuidString, pdfPath: String, title: String, prompt: String) {
        version = 1; self.requestID = requestID; action = "deep-read"; groupID = "default"
        self.pdfPath = pdfPath; self.title = title; self.prompt = prompt
    }

    public var documentURL: URL { URL(fileURLWithPath: pdfPath).standardizedFileURL }
}

public struct PaperImportStatus: Codable, Sendable {
    public var version = 1
    public var requestID: String
    public var state: String
    public var stage: String
    public var updatedAt = Date()
    public var conversationID: String?
    public var historyPath: String?
    public var error: String?
}

public struct PaperImportInput: Sendable {
    public var context: String
    public var scope: String
    public var modelRouteID: String?
    public var reasoningEffort: String?
    public init(context: String, scope: String, modelRouteID: String? = nil, reasoningEffort: String? = nil) {
        self.context = context; self.scope = scope; self.modelRouteID = modelRouteID; self.reasoningEffort = reasoningEffort
    }
}

public struct PaperImportFailure: Error, LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// One lifetime flock elects a single consumer across installed/debug app copies.
/// Atomic renames claim requests; only explicit re-enqueue retries interrupted work.
public actor PaperImportQueue {
    public nonisolated static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/dev.pdflight.reader/paper-import", isDirectory: true)
    }

    public typealias Prepare = @Sendable (PaperImportRequest) async throws -> PaperImportInput
    public typealias Model = @Sendable (PaperImportRequest, String, PaperImportInput) async throws -> AsyncThrowingStream<OpenAIStreamEvent, Error>
    public typealias Update = @Sendable (PaperImportRequest, String, Bool) async -> Void
    private let directory: URL
    private let histories: AIChatHistoryStore
    private let timeout: TimeInterval
    private var ownerFD: Int32 = -1
    private var busy = false
    private var recovered = false

    public init(directory: URL = PaperImportQueue.defaultDirectory, histories: AIChatHistoryStore, timeout: TimeInterval = 600) {
        self.directory = directory; self.histories = histories; self.timeout = timeout
    }

    deinit { if ownerFD >= 0 { Darwin.close(ownerFD) } }

    @discardableResult
    public func poll(prepare: @escaping Prepare, model: @escaping Model, update: @escaping Update = { _, _, _ in }) async throws -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        for folder in ["requests", "processing", "status", "archive"] {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
        if ownerFD < 0 {
            let fd = Darwin.open(directory.appendingPathComponent("consumer.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw PaperImportFailure("无法打开导入队列锁。") }
            guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); return false }
            ownerFD = fd
        }
        if !recovered { try await recoverInterrupted(); recovered = true }
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("requests"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            try Task.checkCancellation()
            let id = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: id) != nil else { continue }
            // The owner lock prevents a competing app from replacing a claim.
            // rename also keeps a retry of the same ID atomic on the same volume.
            let claim = directory.appendingPathComponent("processing/\(id).json")
            guard Darwin.rename(file.path, claim.path) == 0 else { continue }
            do {
                let request = try JSONDecoder().decode(PaperImportRequest.self, from: Data(contentsOf: claim))
                guard request.requestID.lowercased() == id.lowercased(), request.version == 1,
                      request.action == "deep-read", request.groupID == "default",
                      request.pdfPath.hasPrefix("/"), request.documentURL.pathExtension.lowercased() == "pdf",
                      !request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw PaperImportFailure("导入请求格式、requestID、PDF 路径或提示词无效。")
                }
                if let completed = try await completedConversation(request) {
                    try await histories.upsertConversation(completed, for: request.documentURL)
                    try writeStatus(request, state: "succeeded", stage: "已持久化；重复请求未再次调用模型。", conversationID: completed.id)
                    await update(request, completed.id, false)
                    archiveClaim(claim)
                    continue
                }
                if let deleted = try await histories.deletedCompletedPaperImport(requestID: request.requestID, for: request.documentURL) {
                    try writeStatus(request, state: "succeeded", stage: "此请求已完成后被用户删除；未恢复会话，也未再次调用模型。", conversationID: deleted)
                    archiveClaim(claim)
                    continue
                }
                try writeStatus(request, state: "queued", stage: "已接收，等待深度阅读。")
                if await process(request, prepare: prepare, model: model, update: update) { archiveClaim(claim) }
            } catch {
                try write(PaperImportStatus(requestID: id, state: "failed", stage: "请求处理失败，可修正后使用相同 requestID 重试。", error: error.localizedDescription))
                archiveClaim(claim)
            }
        }
        return true
    }

    private func completedConversation(_ request: PaperImportRequest) async throws -> AIConversation? {
        let history = try await histories.history(for: request.documentURL)
        return history.conversations.first {
            $0.paperImport?.requestID.lowercased() == request.requestID.lowercased()
                && $0.paperImport?.state == "succeeded"
                && $0.messages.contains { $0.role == .assistant && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
    }

    private func recoverInterrupted() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("processing"), includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            guard UUID(uuidString: id) != nil else { continue }
            guard let request = try? JSONDecoder().decode(PaperImportRequest.self, from: Data(contentsOf: file)),
                  request.requestID.lowercased() == id.lowercased(), request.pdfPath.hasPrefix("/") else {
                try write(PaperImportStatus(requestID: id, state: "failed", stage: "恢复到无效请求，已归档，可修正后按相同 ID 重试。", error: "请求格式无效。"))
                archiveClaim(file)
                continue
            }
            if let completed = try? await completedConversation(request) {
                try await histories.upsertConversation(completed, for: request.documentURL)
                try writeStatus(request, state: "succeeded", stage: "已恢复已落盘的最终回答。", conversationID: completed.id)
                archiveClaim(file)
                continue
            }
            let statusURL = directory.appendingPathComponent("status/\(request.requestID).json")
            let prior = (try? Data(contentsOf: statusURL)).flatMap { try? Self.decoder().decode(PaperImportStatus.self, from: $0) }
            if prior?.state != "failed" {
                try writeStatus(request, state: "failed", stage: "上次进程中断；已保留聊天记录，重新入队同一 requestID 可重试。",
                                conversationID: prior?.conversationID, error: "消费进程已退出，未确认最终回答持久化。")
            }
            archiveClaim(file)
        }
    }

    /// Called only after a terminal status was durably written and the structured
    /// generation task group (including cancellation cleanup) has fully returned.
    private func archiveClaim(_ claim: URL) {
        do {
            let folder = directory.appendingPathComponent("archive/" + claim.deletingPathExtension().lastPathComponent)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let destination = folder.appendingPathComponent(UUID().uuidString + ".json")
            guard Darwin.rename(claim.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        } catch {
            // Archiving failed: retain the original claim for startup recovery.
            NSLog("Paper import claim could not be archived: %@", claim.lastPathComponent)
        }
    }

    private func process(_ request: PaperImportRequest, prepare: @escaping Prepare, model: @escaping Model, update: @escaping Update) async -> Bool {
        let conversationID = "paper-import-" + request.requestID.lowercased() + "-" + UUID().uuidString.lowercased()
        let conversation = AIConversation(id: conversationID, title: "深度阅读 · " + request.title,
            promptPreset: .reading,
            messages: [AIChatMessage(role: .user, content: request.prompt, pdfAttachmentName: request.documentURL.lastPathComponent)],
            paperImport: .init(requestID: request.requestID, state: "running"))
        var hasHistory = false
        var terminalStatusWritten = false
        do {
            try await histories.upsertConversation(conversation, for: request.documentURL, select: true)
            hasHistory = true
            try writeStatus(request, state: "running", stage: "打开 Default，准备论文全文和模型路由。", conversationID: conversationID)
            await update(request, conversationID, true)
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await self.generate(request, conversation: conversation, prepare: prepare, model: model) }
                let timeout = self.timeout
                group.addTask {
                    try await Task.sleep(for: .seconds(timeout))
                    throw PaperImportFailure("深度阅读超时（\(Int(timeout)) 秒），未标记成功。")
                }
                defer { group.cancelAll() }
                try await group.next()
            }
            // Verify the serialized record, not a UI placeholder or a draft.
            guard let persisted = try await completedConversation(request) else {
                throw PaperImportFailure("未找到已持久化的非空最终回答。")
            }
            try writeStatus(request, state: "succeeded", stage: "最终回答已保存到此 PDF 的独立深度阅读会话。", conversationID: persisted.id)
            terminalStatusWritten = true
        } catch {
            let failure = error.localizedDescription
            do {
                var failed = try await histories.history(for: request.documentURL).conversations.first { $0.id == conversationID } ?? conversation
                // A completed record survives a crash/status-write failure and is
                // recovered idempotently on the next poll/re-enqueue.
                if failed.paperImport?.state != "succeeded" {
                    failed.paperImport?.state = "failed"
                    failed.updatedAt = Date()
                    failed.messages.append(AIChatMessage(role: .assistant, content: "深度阅读未完成：\(error.localizedDescription)\n可使用同一 requestID 重试；已有内容已保留。"))
                    try await histories.upsertConversation(failed, for: request.documentURL)
                    hasHistory = true
                }
            } catch {
                NSLog("Paper import persistence failed for %@", request.requestID)
            }
            do {
                try writeStatus(request, state: "failed", stage: hasHistory ? "深度阅读未完成；聊天与原请求记录已保留供重试。" : "聊天无法落盘；原请求记录保留供重试。",
                                conversationID: hasHistory ? conversationID : nil, error: failure)
                terminalStatusWritten = true
            } catch { NSLog("Paper import status unavailable for %@", request.requestID) }
        }
        await update(request, conversationID, false)
        return terminalStatusWritten
    }

    private func generate(_ request: PaperImportRequest, conversation source: AIConversation, prepare: @escaping Prepare, model: @escaping Model) async throws {
        var conversation = source
        let input = try await prepare(request)
        try Task.checkCancellation()
        guard !input.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PaperImportFailure("PDF 未提取到正文，不能仅依据标题生成深度阅读。") }
        conversation.paperImport?.scope = input.scope
        conversation.modelRouteID = input.modelRouteID
        conversation.reasoningEffort = input.reasoningEffort
        conversation.messages.insert(AIChatMessage(role: .system, content: "阅读范围：" + input.scope), at: 0)
        let assistantID = UUID().uuidString
        var accumulator = OpenAIStreamAccumulator()
        var checkpoint = Date.distantPast
        var sawFinished = false
        try await histories.upsertConversation(conversation, for: request.documentURL)
        try writeStatus(request, state: "running", stage: "正在生成；" + input.scope, conversationID: conversation.id)
        do {
        let stream = try await model(request, conversation.id, input)
        for try await event in stream {
            try Task.checkCancellation()
            _ = accumulator.consume(event)
            if event == .finished { sawFinished = true }
            if Date().timeIntervalSince(checkpoint) >= 1 {
                conversation.messages.removeAll { $0.id == assistantID }
                conversation.messages.append(AIChatMessage(id: assistantID, role: .assistant, content: accumulator.content,
                    reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning))
                conversation.updatedAt = Date()
                try await histories.upsertConversation(conversation, for: request.documentURL)
                checkpoint = Date()
            }
        }
        try Task.checkCancellation()
        guard sawFinished else { throw PaperImportFailure("模型流缺少完成标记，不能确认最终回答。") }
        guard accumulator.toolCalls.isEmpty else { throw PaperImportFailure("模型返回了工具请求而非最终回答；深度阅读未完成。") }
        let final = try accumulator.finalAnswer()
        conversation.messages.removeAll { $0.id == assistantID }
        conversation.messages.append(AIChatMessage(id: assistantID, role: .assistant, content: "> 阅读范围：\(input.scope)\n\n\(final)",
            reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning))
        conversation.paperImport?.state = "succeeded"
        conversation.updatedAt = Date()
        try await histories.upsertConversation(conversation, for: request.documentURL)
        } catch {
            if !accumulator.content.isEmpty || !accumulator.reasoning.isEmpty {
                conversation.paperImport?.state = "running"
                conversation.messages.removeAll { $0.id == assistantID }
                conversation.messages.append(AIChatMessage(id: assistantID, role: .assistant, content: accumulator.content,
                    reasoning: accumulator.reasoning.isEmpty ? nil : accumulator.reasoning))
                conversation.updatedAt = Date()
                try await histories.upsertConversation(conversation, for: request.documentURL)
            }
            throw error
        }
    }

    private func writeStatus(_ request: PaperImportRequest, state: String, stage: String, conversationID: String? = nil, error: String? = nil) throws {
        try write(PaperImportStatus(requestID: request.requestID, state: state, stage: stage,
            conversationID: conversationID, historyPath: conversationID == nil ? nil : histories.fileURL(for: request.documentURL).path, error: error))
    }

    private func write(_ status: PaperImportStatus) throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(status).write(to: directory.appendingPathComponent("status/\(status.requestID).json"), options: .atomic)
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder
    }
}
