import Foundation
import PDFlightAI
import PDFlightCore

@main
enum PDFlightAIChecks {
    static func main() async throws {
        if let index = CommandLine.arguments.firstIndex(of: "--inspect-staged-history"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
            let histories = try await AIChatHistoryStore(directoryURL: directory).allHistories()
            guard files.count == histories.count else { throw CheckFailure(message: "some staged history files cannot be decoded") }
            let messages = histories.flatMap(\.conversations).flatMap(\.messages)
            print("decoded histories: \(histories.count); messages with reasoning: \(messages.filter { $0.reasoning != nil }.count); tool cards: \(messages.filter { $0.toolEvent != nil }.count)")
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--stage-harness-import"), CommandLine.arguments.count > index + 1 {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let data = home.appendingPathComponent("Documents/deepseek-harness/default-workspace/pdf-reading-mode/data")
            let support = home.appendingPathComponent("Library/Application Support/dev.pdflight.reader")
            let destination = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            let result = try HarnessLibraryMigration.prepare(dataDirectory: data, sourceMappingsURL: support.appendingPathComponent("harness-bridge/paper-paths.json"), destination: destination)
            let store = AIChatHistoryStore(directoryURL: destination.appendingPathComponent("ai-chats"))
            var sessions = 0, messages = 0, drafts = 0
            for target in result.targets {
                let history = try await store.importHarnessIfNeeded(for: target.documentURL, dataDirectory: data, pathMappingsURL: result.mappingsURL,
                    draftDirectory: support.appendingPathComponent("harness-draft-import"), recoveredArchivesDirectory: support.appendingPathComponent("harness-recovery"),
                    projectionDirectory: home.appendingPathComponent(".dsh/storages/session_projcache/sessions"))
                sessions += history.conversations.count
                messages += history.conversations.reduce(0) { $0 + $1.messages.count }
                drafts += history.conversations.filter { !($0.draft?.text.isEmpty ?? true) }.count
            }
            let legacyDirectory = support.appendingPathComponent("ai-chats", isDirectory: true)
            let legacyBackup = destination.appendingPathComponent("legacy-originals", isDirectory: true)
            try FileManager.default.createDirectory(at: legacyBackup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if FileManager.default.fileExists(atPath: legacyDirectory.path) {
                for file in try FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
                    let copy = legacyBackup.appendingPathComponent(file.lastPathComponent)
                    let raw = try Data(contentsOf: file)
                    if FileManager.default.fileExists(atPath: copy.path) {
                        guard try Data(contentsOf: copy) == raw else { throw CocoaError(.fileWriteFileExists) }
                    } else {
                        try raw.write(to: copy, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
                    }
                }
            }
            let legacy = try await AIChatHistoryStore(directoryURL: legacyDirectory).allHistories()
            for history in legacy {
                _ = try await store.mergeLegacy(history, for: URL(fileURLWithPath: history.documentPath))
            }
            let nativeRoot = home.appendingPathComponent(".dsh/sessions", isDirectory: true)
            let nativeBackup = destination.appendingPathComponent("harness-native-originals", isDirectory: true)
            try FileManager.default.createDirectory(at: nativeBackup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let groupsData = try Data(contentsOf: data.appendingPathComponent("conversations.json"))
            let groupsObject = try JSONSerialization.jsonObject(with: groupsData) as? [String: Any]
            let groups = groupsObject?["groups"] as? [[String: Any]] ?? []
            let sessionIDs = Set(groups.flatMap { ($0["conversations"] as? [[String: Any]] ?? []).compactMap { $0["sessionId"] as? String } })
            let workspaces = try FileManager.default.contentsOfDirectory(at: nativeRoot, includingPropertiesForKeys: nil)
            var nativeCopies = 0
            for id in sessionIDs {
                guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { continue }
                let sources = workspaces.map { $0.appendingPathComponent(id).appendingPathComponent("session.v4.jsonl.zstd") }.filter { FileManager.default.fileExists(atPath: $0.path) }
                guard sources.count == 1, let source = sources.first else { continue }
                let before = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let raw = try Data(contentsOf: source)
                let after = try source.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                guard before.contentModificationDate == after.contentModificationDate && before.fileSize == after.fileSize else {
                    throw CocoaError(.fileReadUnknown)
                }
                let copy = nativeBackup.appendingPathComponent(id + ".jsonl.zstd")
                if FileManager.default.fileExists(atPath: copy.path) {
                    guard try Data(contentsOf: copy) == raw else { throw CocoaError(.fileWriteFileExists) }
                } else {
                    try raw.write(to: copy, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: copy.path)
                }
                nativeCopies += 1
            }
            let manifest: [String: Any] = ["version": 1, "targets": result.targets.map { ["paperID": $0.paperID, "path": $0.documentURL.path, "copied": $0.copied] }, "unavailablePaperIDs": result.unavailablePaperIDs]
            let manifestURL = destination.appendingPathComponent("manifest.json")
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: manifestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
            print("Harness paper targets: \(result.targets.count); copied PDFs: \(result.targets.filter(\.copied).count); sessions: \(sessions); messages: \(messages); drafts: \(drafts); original native sessions backed up: \(nativeCopies); missing paper associations: \(result.unavailablePaperIDs.count); legacy PDFlight histories merged: \(legacy.count)")
            return
        }
        if CommandLine.arguments.contains("--inspect-harness-import") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let data = home.appendingPathComponent("Documents/deepseek-harness/default-workspace/pdf-reading-mode/data")
            let map = home.appendingPathComponent("Library/Application Support/dev.pdflight.reader/harness-bridge/paper-paths.json")
            let mappings = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: map))
            var prepared = 0, messages = 0, skipped = 0, missing = 0, failed = 0
            for path in mappings.keys {
                guard FileManager.default.fileExists(atPath: path) else { missing += 1; continue }
                do {
                    let result = try HarnessChatImport.prepare(documentURL: URL(fileURLWithPath: path), dataDirectory: data, pathMappingsURL: map)
                    prepared += result.conversations.count
                    messages += result.conversations.reduce(0) { $0 + $1.value.messages.count }
                    skipped += result.skippedSessionIDs.count
                } catch { failed += 1 }
            }
            print("papers: \(mappings.count), archives prepared: \(prepared), messages: \(messages), skipped: \(skipped), missing PDFs: \(missing), failures: \(failed)")
            let settings = try HarnessModelImport.read(profile: home.appendingPathComponent(".dsh/profiles/desktop/cordis.patch.yml"), credentials: home.appendingPathComponent(".dsh/.credentials.yaml"))
            print("selected provider: \(settings.provider); model: \(settings.configuration.model); endpoint: \(settings.configuration.baseURL); credential present: \(!settings.apiKey.isEmpty)")
            return
        }
        if CommandLine.arguments.contains("--validate-renderable-content") {
            try validateRenderableContentFromStandardInput()
            print("PASS: every detected formula is safe for native math rendering")
            return
        }
        try await paperContextCarriesPageBoundariesAndStopsAtItsBudget()
        print("PASS: paper context carries page boundaries and respects its budget")
        try openAIStreamDecoderReadsContentAndCompletion()
        print("PASS: OpenAI stream decoder reads content and completion")
        try openAIStreamDecoderSeparatesReasoningFromFinalContent()
        print("PASS: streamed reasoning and answer text stay buffered until completion")
        try await chatHistorySupportsPortablePerPaperConversations()
        print("PASS: AI chat history is portable, grouped by paper, and supports multiple conversations")
        try await harnessArchivesCanBePreparedWithoutChangingTheSource()
        print("PASS: Harness archives are matched and prepared without losing their original data")
        try harnessModelSettingsCanBeReadWithoutChangingTheSource()
        print("PASS: Harness model selection and credential are read without changing the source")
        try alternateModelProtocolsEncodeAndStream()
        print("PASS: Responses and Anthropic routes send and decode their own streaming protocols")
        try streamedToolCallsAreReassembledAcrossProviders()
        print("PASS: streamed tool calls preserve IDs, interleaving and arguments across providers")
        try toolRequestsPreserveProviderProtocol()
        print("PASS: tool schemas, calls and results use the correct provider protocol")
        try await nativePaperToolsReadAndSearchSafely()
        print("PASS: native PDF and workspace tools return grounded results and reject traversal")
        try await nativeAgentRunsToolRoundTrips()
        print("PASS: native agent executes tool calls and feeds their results back to the model")
        try await nativeShellToolHandlesExitAndTimeout()
        print("PASS: approved native shell commands preserve output, exit status and timeout")
        let displayEvents = [AIChatMessage(role: .user, content: "question"), AIChatMessage(role: .tool, content: "private tool event"), AIChatMessage(role: .assistant, content: "", reasoning: "thinking"), AIChatMessage(role: .assistant, content: "answer")]
        let requestEvents = AIChatRequestBuilder.messages(instruction: nil, paperContext: nil, conversation: displayEvents)
        try check(requestEvents.map(\.role) == [.user, .assistant], "display-only tool and thinking events must not become fake model turns")
        try promptPresetsStartNewConversationsInReadingMode()
        print("PASS: new AI conversations start with no preset prompt")
        try await promptTemplatesAreEditableAndPortable()
        print("PASS: prompt modes are editable, extensible, and portable")
        try requestsContainNoHiddenPaperContext()
        print("PASS: neither prompt mode sends hidden PDF page context")
        try universalWebAPIRequestsCarryTheLocalConversationIdentity()
        print("PASS: Universal Web API requests bind one local conversation to one web conversation")
        try localPDFsUseTheUniversalWebAPIAttachmentExtension()
        print("PASS: current PDFs are attached only to localhost Universal Web API requests")
        try attachmentOnlySubmissionsKeepTheSelectedPromptMode()
        print("PASS: PDF attachments keep Reading and custom prompt modes independent")
        try imageAttachmentsStayPortableAndUseMultimodalRequestContent()
        print("PASS: chat images stay portable and use OpenAI-compatible multimodal content")
        try queuedChatSubmissionsRemainFIFOAndKeepImages()
        print("PASS: chat submissions queue in FIFO order and keep pasted images")
        try onlyLocalQwenUsesBoundWebConversations()
        print("PASS: only local Universal Web API Qwen requests use web conversation binding")
        try messageContentSeparatesMarkdownAndLatex()
        print("PASS: chat content separates Markdown from inline and display LaTeX")
        try markdownParserRecognizesReplyBlocks()
        print("PASS: assistant replies recognize block Markdown")
        try await localWebBridgeEndpointsAndReadiness()
        print("PASS: local web bridge resolves loopback endpoints and skips remote providers")
    }

    private static func harnessArchivesCanBePreparedWithoutChangingTheSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data")
        let chats = data.appendingPathComponent("chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        let originalPDF = root.appendingPathComponent("Paper.pdf")
        let copyPDF = root.appendingPathComponent("library-copy.pdf")
        try Data("first PDF".utf8).write(to: originalPDF)
        try Data("first PDF".utf8).write(to: copyPDF)
        func write(_ object: Any, _ url: URL) throws {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url)
        }
        try write(["papers": [["id": "paper-1", "title": "Paper.pdf", "path": copyPDF.path]]], data.appendingPathComponent("index.json"))
        try write(["groups": [["paperId": "paper-1", "lastSessionId": "session-a", "conversations": [
            ["sessionId": "session-a", "title": "Reading"], ["sessionId": "session-image"],
            ["sessionId": "missing"], ["sessionId": "../escape"]
        ]]]], data.appendingPathComponent("conversations.json"))
        let archive: [String: Any] = ["sessionId": "session-a", "paperId": "paper-1", "title": "Reading", "provider": "test", "model": "sample", "status": "active", "createdAt": "2026-01-01T00:00:00.000Z", "entries": [
            ["id": "m1", "role": "user", "time": 1_767_225_600_000, "text": "question", "content": [["type": "text", "text": "question"]]],
            ["id": "m2", "role": "assistant", "time": 1_767_225_601_000, "text": "answer", "content": [["type": "text", "text": "answer"]]]
        ], "web": ["conversationId": "preserve-this"]]
        let archiveURL = chats.appendingPathComponent("session-a.json")
        try write(archive, archiveURL)
        try write(["sessionId": "session-image", "paperId": "paper-1", "entries": [["id": "x", "role": "user", "content": [["type": "image"]]]]], chats.appendingPathComponent("session-image.json"))
        let raw = try Data(contentsOf: archiveURL)
        let result = try HarnessChatImport.prepare(documentURL: originalPDF, dataDirectory: data, pathMappingsURL: nil)
        try check(result.paperID == "paper-1" && result.activeSessionID == "session-a", "expected the exact PDF and selected session")
        try check(result.conversations.count == 1 && result.conversations[0].value.messages.map(\.content) == ["question", "answer"], "expected complete text turns")
        try check(result.conversations[0].sourceArchive == raw && result.conversations[0].provider == "test", "expected original archive and provider to be retained")
        try check(Set(result.skippedSessionIDs) == Set(["session-image", "missing", "../escape"]), "expected unsupported, absent and unsafe sessions to be reported")
        let unchanged = try Data(contentsOf: archiveURL)
        try check(unchanged == raw, "import preparation must not modify Harness data")
        let store = AIChatHistoryStore(directoryURL: root.appendingPathComponent("native-history"))
        let firstImport = try await store.importHarness(result, for: originalPDF)
        try check(firstImport.conversations.count == 1 && firstImport.activeConversationID == "session-a", "expected selected imported session without a blank duplicate")
        let secondImport = try await store.importHarness(result, for: originalPDF)
        try check(secondImport == firstImport, "repeat import must not duplicate or overwrite conversations")
        let backup = store.storageDirectoryURL.appendingPathComponent("harness-originals")
            .appendingPathComponent(store.fileURL(for: originalPDF).deletingPathExtension().lastPathComponent)
            .appendingPathComponent("session-a.json")
        let backupData = try Data(contentsOf: backup)
        try check(backupData == raw, "expected the full original archive to be retained privately")
        let drafts = root.appendingPathComponent("drafts")
        try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
        try write(["version": 1, "drafts": [["sessionId": "session-a", "draft": ["text": "unfinished draft", "references": []]]]], drafts.appendingPathComponent("capture.json"))
        let draftStore = AIChatHistoryStore(directoryURL: root.appendingPathComponent("draft-history"))
        var withDraft = try await draftStore.importHarnessIfNeeded(for: originalPDF, dataDirectory: data, pathMappingsURL: nil, draftDirectory: drafts)
        try check(withDraft.conversations.first?.draft?.text == "unfinished draft", "expected captured desktop draft to migrate with its session")
        withDraft.conversations[0].draft = AIChatDraft(text: "edited in native")
        try await draftStore.save(withDraft, for: originalPDF)
        let afterRestart = try await draftStore.importHarnessIfNeeded(for: originalPDF, dataDirectory: data, pathMappingsURL: nil, draftDirectory: drafts)
        try check(afterRestart.conversations.first?.draft?.text == "edited in native", "old captured draft must never overwrite a newer native draft")
        let latest = AIChatDraft(text: "line one\nline two")
        try draftStore.saveDraft(latest, sessionID: "session-a", for: originalPDF)
        let restoredDraft = try draftStore.readDraft(sessionID: "session-a", for: originalPDF)
        try check(restoredDraft == latest, "native draft sidecar must preserve exact text and newlines")
        do {
            try draftStore.saveDraft(latest, sessionID: "../escape", for: originalPDF)
            throw CheckFailure(message: "draft session ID must not allow directory traversal")
        } catch let error as CocoaError where error.code == .fileReadInvalidFileName { }
        var legacy = withDraft
        legacy.conversations[0].messages.append(AIChatMessage(role: .user, content: "legacy-only turn"))
        let mergedLegacy = try await draftStore.mergeLegacy(legacy, for: originalPDF)
        let repeatedLegacy = try await draftStore.mergeLegacy(legacy, for: originalPDF)
        try check(mergedLegacy.conversations.count == 2 && repeatedLegacy.conversations.count == 2, "conflicting legacy IDs must be preserved without duplication")
        let mappings = root.appendingPathComponent("paths.json")
        try write([originalPDF.path: "paper-1"], mappings)
        try Data("modified PDF".utf8).write(to: originalPDF)
        let mapped = try HarnessChatImport.prepare(documentURL: originalPDF, dataDirectory: data, pathMappingsURL: mappings)
        try check(mapped.paperID == "paper-1", "expected the saved bridge mapping to survive PDF edits")
        let unmatched = try HarnessChatImport.prepare(documentURL: originalPDF, dataDirectory: data, pathMappingsURL: nil)
        try check(unmatched.paperID == nil, "different PDF bytes must not match by title alone")
        let direct = try HarnessChatImport.prepare(documentURL: copyPDF, dataDirectory: data, pathMappingsURL: nil)
        try check(direct.paperID == "paper-1", "the Harness library copy must match by path even when its filename is an ID")
        let portable = root.appendingPathComponent("portable")
        let prepared = try HarnessLibraryMigration.prepare(dataDirectory: data, sourceMappingsURL: nil, destination: portable)
        try check(prepared.targets.count == 1 && prepared.targets[0].copied, "an unmapped Harness paper must get an independent PDF copy")
        let copied = try Data(contentsOf: prepared.targets[0].documentURL)
        try check(copied == Data("first PDF".utf8), "portable PDF bytes must match the original")
        let second = try HarnessLibraryMigration.prepare(dataDirectory: data, sourceMappingsURL: nil, destination: portable)
        try check(second.targets[0].documentURL == prepared.targets[0].documentURL, "portable paper copy must be idempotent")
        let copiedHistory = try HarnessChatImport.prepare(documentURL: prepared.targets[0].documentURL, dataDirectory: data, pathMappingsURL: prepared.mappingsURL)
        try check(copiedHistory.conversations.count == 1, "portable PDF must retain its Harness conversation mapping")
        let recovered = root.appendingPathComponent("recovered")
        try FileManager.default.createDirectory(at: recovered.appendingPathComponent("chats"), withIntermediateDirectories: true)
        try write(["sessionId": "missing", "paperId": "paper-1", "entries": [["id": "recovered-message", "role": "user", "text": "recovered turn", "content": [["type": "text", "text": "recovered turn"]]]]], recovered.appendingPathComponent("chats/missing.json"))
        let withRecovery = try HarnessChatImport.prepare(documentURL: copyPDF, dataDirectory: data, pathMappingsURL: nil, recoveredArchivesDirectory: recovered)
        try check(withRecovery.conversations.contains { $0.value.id == "missing" && $0.value.messages.first?.content == "recovered turn" }, "a recovered native-session archive must be imported when the original archive is missing")
        let projections = root.appendingPathComponent("projections")
        try FileManager.default.createDirectory(at: projections, withIntermediateDirectories: true)
        try write(["record": ["rows": ["modelSelection": ["val": ["lastUsed": ["provider": "new-provider", "model": "new-model", "reasoningEffort": "high"]]]]]], projections.appendingPathComponent("session-a.json"))
        let selectedModel = try HarnessChatImport.prepare(documentURL: copyPDF, dataDirectory: data, pathMappingsURL: nil, projectionDirectory: projections)
        try check(selectedModel.conversations.first?.value.modelRouteID == "new-provider/new-model" && selectedModel.conversations.first?.value.reasoningEffort == "high", "latest per-session model and reasoning setting must survive migration")
    }

    private static func harnessModelSettingsCanBeReadWithoutChangingTheSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let profile = root.appendingPathComponent("profile.yml"), credentials = root.appendingPathComponent("credentials.yml")
        let yaml = """
        - id: agent-default-model
          config:
            provider: test-provider
            model: test-model
        - id: llm-pi-ai
          config:
            providers:
              test-provider:
                api: openai-completions
                baseURL: http://127.0.0.1:3425/v1
                apiKeyEnv: PDFLIGHT_FIXTURE_MISSING_KEY
                models:
                  - id: test-model
                    name: Test model
              responses-provider:
                api: openai-responses
                baseURL: http://127.0.0.1:3425/v1
                models:
                  - id: responses-model
                    name: Responses model
              anthropic-provider:
                api: anthropic-messages
                baseURL: http://127.0.0.1:3425
                models:
                  - id: anthropic-model
                    name: Anthropic model
                    maxTokens: 65500
        - id: permission
          name: "@deepseek-ai/dsh-permission-presets"
          config:
            defaultPreset: danger-full-access
            presets:
              danger-full-access:
                sandbox: danger-full-access
                approval: never
        """
        try yaml.write(to: profile, atomically: true, encoding: .utf8)
        try "refs:\n  PDFLIGHT_FIXTURE_MISSING_KEY: fixture-secret\n".write(to: credentials, atomically: true, encoding: .utf8)
        let selected = try HarnessModelImport.read(profile: profile, credentials: credentials)
        try check(selected.provider == "test-provider" && selected.configuration.model == "test-model", "expected configured default model")
        try check(selected.configuration.baseURL == "http://127.0.0.1:3425/v1" && selected.apiKey == "fixture-secret", "expected selected gateway and credential")
        let catalog = try HarnessModelImport.readCatalog(profile: profile, credentials: credentials)
        try check(catalog.defaultAccessMode == .fullAccess, "explicit Harness full-access configuration should be imported")
        try check(catalog.routes.count == 3 && catalog.selectedID == "test-provider/test-model", "expected all model routes and the selected model")
        try check(catalog.routes.allSatisfy(\.isSupported) && catalog.secrets["test-provider"] == "fixture-secret", "expected supported protocols and private provider credential")
        try check(catalog.routes.first(where: { $0.model == "anthropic-model" })?.maxTokens == 65500, "model output limit must be imported")
        let unsupported = yaml.replacingOccurrences(of: "openai-completions", with: "anthropic-messages")
        try unsupported.write(to: profile, atomically: true, encoding: .utf8)
        do {
            _ = try HarnessModelImport.read(profile: profile, credentials: credentials)
            throw CheckFailure(message: "unsupported protocols must not silently use OpenAI requests")
        } catch HarnessModelImport.ImportError.unsupportedAPI("anthropic-messages") { }
    }

    private static func streamedToolCallsAreReassembledAcrossProviders() throws {
        var decoder = OpenAIStreamDecoder()
        var accumulator = OpenAIStreamAccumulator()
        let lines = [
            #"data: {"choices":[{"delta":{"content":"checking ","tool_calls":[{"index":0,"id":"call_a","function":{"name":"read","arguments":"{\"path\":"}},{"index":1,"id":"call_b","function":{"name":"grep","arguments":"{\"pattern\":"}}]}}]}"#,
            #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"needle\"}"}},{"index":0,"function":{"arguments":"\"paper.txt\"}"}}]}}]}"#
        ]
        for line in lines { if let event = try decoder.decode(line: line) { _ = accumulator.consume(event) } }
        try check(accumulator.content == "checking " && accumulator.toolCalls == [
            .init(id: "call_a", name: "read", arguments: #"{"path":"paper.txt"}"#),
            .init(id: "call_b", name: "grep", arguments: #"{"pattern":"needle"}"#)
        ], "interleaved OpenAI tool calls and simultaneous text must survive")
        var responses = OpenAIStreamDecoder(api: "openai-responses")
        var responseResult = OpenAIStreamAccumulator()
        for line in [
            #"data: {"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","call_id":"response_1","name":"read","arguments":""}}"#,
            #"data: {"type":"response.function_call_arguments.delta","output_index":2,"delta":"{\"page\":2}"}"#,
            #"data: {"type":"response.function_call_arguments.done","output_index":2,"arguments":"{\"page\":2}"}"#
        ] { if let event = try responses.decode(line: line) { _ = responseResult.consume(event) } }
        try check(responseResult.toolCalls == [.init(id: "response_1", name: "read", arguments: #"{"page":2}"#)], "Responses tool call must not duplicate final arguments")
        var anthropic = OpenAIStreamDecoder(api: "anthropic-messages")
        var anthropicResult = OpenAIStreamAccumulator()
        for line in [
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"tool_1","name":"grep","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"q\":\"x\"}"}}"#
        ] { if let event = try anthropic.decode(line: line) { _ = anthropicResult.consume(event) } }
        try check(anthropicResult.toolCalls == [.init(id: "tool_1", name: "grep", arguments: #"{"q":"x"}"#)], "Anthropic tool-use blocks must preserve arguments")
    }

    private static func nativeShellToolHandlesExitAndTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pdflight-shell-check-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let result = await AIChatShellTool.run(command: "printf stdout-ok; printf stderr-ok >&2; exit 7", workingDirectory: directory)
        try check(result.isError && result.content.contains("stdout-ok") && result.content.contains("stderr-ok") && result.content.contains("退出码 7"), "shell must preserve output and nonzero exit")
        let started = Date()
        let timeout = await AIChatShellTool.run(command: "sleep 10", workingDirectory: directory, timeout: 0.15)
        try check(timeout.isError && timeout.content.contains("超时") && Date().timeIntervalSince(started) < 4, "timed-out commands must stop promptly")
        let flood = await AIChatShellTool.run(command: "yes x | head -c 200000", workingDirectory: directory)
        try check(!flood.isError && flood.content.contains("输出已截断") && flood.content.utf8.count < 65_000, "large output must be drained without unbounded memory or disk use")
        let task = Task { await AIChatShellTool.run(command: "sleep 10", workingDirectory: directory) }
        try await Task.sleep(for: .milliseconds(150)); task.cancel()
        let cancelled = await task.value
        try check(cancelled.isError && cancelled.content.contains("取消"), "cancelling chat must terminate its shell process")
        let children = Task { await AIChatShellTool.run(command: "trap '' TERM; (trap '' TERM; sleep 1; printf surviving > marker) & wait", workingDirectory: directory) }
        try await Task.sleep(for: .milliseconds(150)); children.cancel()
        _ = await children.value
        try await Task.sleep(for: .milliseconds(1200))
        try check(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("marker").path), "cancellation must terminate TERM-resistant child processes")
    }

    private static func nativeAgentRunsToolRoundTrips() async throws {
        let context = AIPaperToolContext(documentURL: URL(fileURLWithPath: "/tmp/paper.pdf"), workspaceURL: URL(fileURLWithPath: "/tmp"), pageCount: 1) { _ in "Evidence from page one" }
        let model: AIChatAgentRunner.Model = { messages, round in
            AsyncThrowingStream { continuation in
                if round == 0 {
                    continuation.yield(.toolCallDeltas([.init(index: 0, id: "c1", name: "pdf_reading", arguments: #"{"action":"read_page","page":1}"#)], content: nil, reasoning: nil))
                } else if messages.last?.toolEvent?.result?.contains("Evidence from page one") == true {
                    continuation.yield(.contentDelta("Grounded answer, page 1"))
                } else { continuation.finish(throwing: CheckFailure(message: "tool result was not returned to model")); return }
                continuation.yield(.finished); continuation.finish()
            }
        }
        let stream = AIChatAgentRunner.run(messages: [AIChatMessage(role: .user, content: "Read the paper")], model: model) { call in
            await AIPaperToolRuntime.execute(call, context: context)
        }
        var assistant: [AIChatMessage] = []; var results: [AIChatMessage] = []; var started = 0
        for try await event in stream {
            switch event {
            case .assistantCompleted(let message): assistant.append(message)
            case .toolStarted: started += 1
            case .toolCompleted(let message): results.append(message)
            case .modelDelta: break
            }
        }
        try check(started == 1 && assistant.count == 2 && assistant[0].toolCalls?.first?.id == "c1", "agent must preserve the model's structured tool call")
        try check(results.first?.toolEvent?.callID == "c1" && results.first?.toolEvent?.isError == false && assistant.last?.content == "Grounded answer, page 1", "agent must pass the result into the next model round")
    }

    private static func nativePaperToolsReadAndSearchSafely() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pdflight-tool-check-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "alpha\nneedle line\nomega".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let context = AIPaperToolContext(documentURL: root.appendingPathComponent("paper.pdf"), workspaceURL: root, pageCount: 2,
                                         listLibrary: { "library fixture" }, listPrompts: { "prompt fixture" },
                                         runSubagent: { description, prompt in "delegated: \(description) / \(prompt)" },
                                         runShell: { command, description, timeout in .init(content: "\(description): \(command), timeout \(timeout ?? 0)", isError: true) }) { page in
            page == 0 ? "introduction" : "key method on page two"
        }
        func call(_ name: String, _ arguments: String) async -> AIChatToolResult {
            await AIPaperToolRuntime.execute(.init(id: "test", name: name, arguments: arguments), context: context)
        }
        let page = await call("pdf_reading", #"{"action":"read_page","page":2}"#)
        try check(!page.isError && page.content.contains("第 2 页") && page.content.contains("key method"), "PDF tool must use the real page callback and preserve page numbering")
        let search = await call("pdf_reading", #"{"action":"search","pattern":"method"}"#)
        try check(!search.isError && search.content.contains("第 2 页"), "PDF search must identify matching pages")
        let read = await call("read", #"{"file_path":"notes.txt","offset":2,"limit":1}"#)
        try check(!read.isError && read.content == "2: needle line", "read must respect line range")
        let grep = await call("grep", #"{"pattern":"needle","path":"."}"#)
        try check(!grep.isError && grep.content.contains("notes.txt:2: needle line"), "grep must find text in the workspace")
        let traversal = await call("read", #"{"file_path":"../outside.txt"}"#)
        try check(traversal.isError, "workspace tools must reject directory traversal")
        let invalid = await call("read", "not JSON")
        try check(invalid.isError, "invalid tool arguments must return an error result")
        let shell = await call("bash", #"{"command":"printf fixture","description":"check","timeout":3}"#)
        try check(shell.isError && shell.content == "check: printf fixture, timeout 3", "shell executor and its errors must be passed through")
        let library = await call("pdf_reading", #"{"action":"library"}"#)
        let prompts = await call("pdf_reading", #"{"action":"prompts"}"#)
        let child = await call("subagent", #"{"description":"verify","prompt":"check the method"}"#)
        try check(library.content == "library fixture" && prompts.content == "prompt fixture", "library and prompt actions must use the supplied native stores")
        try check(child.content == "delegated: verify / check the method" && !child.isError, "subagent must dispatch the requested task")
    }

    private static func toolRequestsPreserveProviderProtocol() throws {
        let definition = AIChatToolDefinition(name: "read", description: "Read a page", parameters: .object([
            "type": .string("object"), "properties": .object(["page": .object(["type": .string("integer")])]), "required": .array([.string("page")])
        ]))
        let call = AIChatToolCall(id: "call_1", name: "read", arguments: #"{"page":2}"#)
        let exchange = [AIChatMessage(role: .user, content: "read page 2"),
                        AIChatMessage(role: .assistant, content: "", toolCalls: [call]),
                        AIChatMessage(role: .tool, content: "", toolEvent: .init(name: "read", arguments: call.arguments, result: "page content", callID: call.id))]
        let preserved = AIChatRequestBuilder.messages(instruction: nil, paperContext: nil, conversation: exchange)
        try check(preserved.count == 3, "structured tool exchanges must survive request preparation")
        let repaired = AIChatRequestBuilder.messages(instruction: nil, paperContext: nil, conversation: Array(exchange.prefix(2)))
        try check(repaired.count == 3 && repaired.last?.toolEvent?.callID == call.id && repaired.last?.toolEvent?.isError == true, "interrupted tool calls must have a matching error result when resumed")
        let orphan = AIChatRequestBuilder.messages(instruction: nil, paperContext: nil, conversation: [exchange[2]])
        try check(orphan.isEmpty, "orphaned results must not become invalid provider turns")
        let client = OpenAICompatibleClient()
        func body(_ api: String) throws -> [String: Any] {
            let request = try client.makeRequest(messages: preserved, configuration: .init(baseURL: "http://127.0.0.1:3425/v1", model: "mock", api: api), apiKey: "", tools: [definition])
            return try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        }
        let chat = try body("openai-completions")
        let chatTurns = chat["messages"] as! [[String: Any]]
        try check((chat["tools"] as? [[String: Any]])?.first?["type"] as? String == "function", "chat tools must use function envelopes")
        try check((chatTurns[1]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String == call.id && chatTurns[2]["tool_call_id"] as? String == call.id, "chat tool call and result IDs must match")
        let responses = try body("openai-responses")
        let responseTurns = responses["input"] as! [[String: Any]]
        try check(responseTurns[1]["type"] as? String == "function_call" && responseTurns[2]["type"] as? String == "function_call_output" && responseTurns[2]["call_id"] as? String == call.id, "Responses tool calls must use input items")
        let anthropic = try body("anthropic-messages")
        let anthropicTurns = anthropic["messages"] as! [[String: Any]]
        let use = (anthropicTurns[1]["content"] as? [[String: Any]])?.first
        let result = (anthropicTurns[2]["content"] as? [[String: Any]])?.first
        try check(use?["type"] as? String == "tool_use" && result?["type"] as? String == "tool_result" && result?["tool_use_id"] as? String == call.id, "Anthropic tool-use blocks must preserve matching IDs")
        let restored = try JSONDecoder().decode(AIChatMessage.self, from: JSONEncoder().encode(exchange[1]))
        try check(restored == exchange[1], "tool-call messages must survive history serialization")
    }

    private static func alternateModelProtocolsEncodeAndStream() throws {
        let client = OpenAICompatibleClient()
        let messages = [AIChatMessage(role: .system, content: "system"), AIChatMessage(role: .user, content: "hello")]
        let completion = try client.makeRequest(messages: messages, configuration: .init(baseURL: "http://127.0.0.1:3425/v1", model: "mock", maxTokens: 48000), apiKey: "test")
        let completionBody = try JSONSerialization.jsonObject(with: completion.httpBody!) as! [String: Any]
        try check(completionBody["max_tokens"] as? Int == 48000, "completion output limit must survive")
        let response = try client.makeRequest(messages: messages, configuration: .init(baseURL: "http://127.0.0.1:3425/v1", model: "mock", api: "openai-responses", reasoningEffort: "high", maxTokens: 64000), apiKey: "test")
        try check(response.url?.path == "/v1/responses" && response.value(forHTTPHeaderField: "Authorization") == "Bearer test", "Responses route must use its own endpoint and auth")
        let responseBody = try JSONSerialization.jsonObject(with: response.httpBody!) as! [String: Any]
        try check(responseBody["max_output_tokens"] as? Int == 64000, "Responses output limit must survive")
        try check(responseBody["input"] != nil && responseBody["messages"] == nil, "Responses input must use the right schema")
        try check((responseBody["reasoning"] as? [String: String])?["effort"] == "high", "Responses reasoning effort must survive")
        var decoder = OpenAIStreamDecoder(api: "openai-responses")
        let responseDelta = try decoder.decode(line: "data: {\"type\":\"response.output_text.delta\",\"delta\":\"one\"}")
        try check(responseDelta == .contentDelta("one"), "Responses text deltas must stream")
        let anthropic = try client.makeRequest(messages: messages, configuration: .init(baseURL: "http://127.0.0.1:3425", model: "mock", api: "anthropic-messages", reasoningEffort: "max", forceAdaptiveThinking: true, maxTokens: 65500), apiKey: "test")
        try check(anthropic.url?.path == "/v1/messages" && anthropic.value(forHTTPHeaderField: "x-api-key") == "test", "Anthropic route must use its own endpoint and auth")
        let anthropicBody = try JSONSerialization.jsonObject(with: anthropic.httpBody!) as! [String: Any]
        try check(anthropicBody["system"] as? String == "system" && anthropicBody["max_tokens"] as? Int == 65500, "Anthropic system prompt and configured output limit must be supplied")
        try check((anthropicBody["output_config"] as? [String: String])?["effort"] == "max" && (anthropicBody["thinking"] as? [String: String])?["type"] == "adaptive", "Anthropic reasoning effort and adaptive thinking must survive")
        var other = OpenAIStreamDecoder(api: "anthropic-messages")
        let anthropicDelta = try other.decode(line: "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"two\"}}")
        try check(anthropicDelta == .contentDelta("two"), "Anthropic text deltas must stream")
        let pdf = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let secondPDF = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: pdf) }
        defer { try? FileManager.default.removeItem(at: secondPDF) }
        try Data("pdf fixture".utf8).write(to: pdf)
        try Data("another pdf fixture".utf8).write(to: secondPDF)
        let withFile = try client.makeRequest(messages: messages, configuration: .init(baseURL: "http://127.0.0.1:3425/v1", model: "mock", api: "openai-responses"), apiKey: "test", currentPDFURL: pdf, additionalPDFURLs: [secondPDF, pdf])
        let fileBody = try JSONSerialization.jsonObject(with: withFile.httpBody!) as! [String: Any]
        let input = fileBody["input"] as! [[String: Any]]; let content = input.last!["content"] as! [[String: Any]]
        try check(content.filter { $0["type"] as? String == "input_file" }.count == 2, "Responses must carry both PDFs and deduplicate repeated files")
        let anthropicFile = try client.makeRequest(messages: messages, configuration: .init(baseURL: "http://127.0.0.1:3425", model: "mock", api: "anthropic-messages"), apiKey: "test", currentPDFURL: pdf, additionalPDFURLs: [secondPDF])
        let aBody = try JSONSerialization.jsonObject(with: anthropicFile.httpBody!) as! [String: Any]
        let turns = aBody["messages"] as! [[String: Any]]; let blocks = turns.last!["content"] as! [[String: Any]]
        try check(blocks.filter { $0["type"] as? String == "document" }.count == 2, "Anthropic must carry both explicitly attached PDFs")
    }

    private static func validateRenderableContentFromStandardInput() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let content = String(data: data, encoding: .utf8) else {
            throw CheckFailure(message: "expected UTF-8 chat content on standard input")
        }
        let unsafe = AIMessageContentParser.segments(in: content).compactMap { segment -> String? in
            guard case let .math(latex, _) = segment else { return nil }
            let isASCII = latex.unicodeScalars.allSatisfy { $0.value < 128 }
            return isASCII && !latex.contains("\n") && latex.count <= 512 ? nil : latex
        }
        try check(
            unsafe.isEmpty,
            "found \(unsafe.count) formula segment(s) that would render as visible iosMath errors"
        )
    }

    private static func messageContentSeparatesMarkdownAndLatex() throws {
        let segments = AIMessageContentParser.segments(
            in: "Loss is $L = \\sum_i x_i$ here.\n\n$$\\alpha + \\beta$$"
        )
        try check(
            segments == [
                .text("Loss is "),
                .math(latex: "L = \\sum_i x_i", display: false),
                .text(" here.\n\n"),
                .math(latex: "\\alpha + \\beta", display: true)
            ],
            "expected both inline and display math delimiters to be parsed"
        )
        try check(
            AIMessageContentParser.segments(in: "An unmatched $ stays text") == [
                .text("An unmatched $ stays text")
            ],
            "expected unmatched delimiters to stay visible"
        )

        let multilineCasesLatex = #"""
        r = \begin{cases}
        1, & \left| \hat{d} - d \right| < \epsilon \\
        0, & \text{otherwise}
        \end{cases}
        """#
        try check(
            AIMessageContentParser.segments(in: """
            $$
            \(multilineCasesLatex)
            $$
            """) == [
                .math(
                    latex: multilineCasesLatex
                        .components(separatedBy: "\n")
                        .joined(separator: " "),
                    display: true
                )
            ],
            "expected a multiline cases environment between standalone $$ delimiters to render as one display formula"
        )
        try check(
            AIMessageContentParser.segments(in: "Broken $x 中文。 $ then $y_i = x_i^2$") == [
                .text("Broken $x 中文。 $ then "),
                .math(latex: "y_i = x_i^2", display: false)
            ],
            "expected malformed cross-prose math to stay text while later valid math recovers"
        )
        try check(
            AIMessageContentParser.segments(
                in: "融合：$r_n^{\\text{final}} =波平滑后。下一式 $W_{ij} = \\exp(-d^2/2\\，直到收敛。"
            ) == [
                .text("融合："),
                .math(latex: "r_n^{\\text{final}} =", display: false),
                .text("波平滑后。下一式 "),
                .math(latex: "W_{ij} = \\exp(-d^2/2", display: false),
                .text("，直到收敛。")
            ],
            "expected useful LaTeX prefixes in truncated Qwen output to render without swallowing prose"
        )

        let labeledGRPO = """
        \\mathcal{J}_{GRPO}(\\theta) = \\mathbb{E} \\left[ \\frac{1}{G} \\sum_{i=1}^G \\frac{1}{|o_i|} \\sum_{t=1}^{|o_i|} \\left( \\underbrace{\\min \\left( \\rho_{i,t} \\hat{A}_i, \\text{clip}(\\rho_{i,t}, 1-\\epsilon, 1+\\epsilon) \\hat{A}_i \\right)}_{\\text{策略优化部分 (类似 PPO)}} - \\underbrace{\\beta \\mathbb{D}_{KL}(\\pi_\\theta || \\pi_{ref})}_{\\text{KL 散度惩罚}} \\right) \\right]
        """
        try check(
            AIMessageContentParser.segments(in: "$$ \(labeledGRPO) $$") == [
                .math(latex: labeledGRPO, display: true)
            ],
            "expected display math with Chinese text labels to reach iosMath"
        )
        let overEscapedSets = #"$\\\\{ \\\hat{y}\_1, \\\hat{y}\_2, \\\dots, \\\hat{y}\_N \\\\}$ 和 $\\\mathcal{U} = \\\\{ \\\tilde{y}\_1, \\\dots, \\\tilde{y}\_M \\\\}$"#
        let overEscapedSegments = AIMessageContentParser.segments(in: overEscapedSets)
        try check(
            overEscapedSegments == [
                .math(latex: #"\{ \hat{y}_1, \hat{y}_2, \dots, \hat{y}_N \}"#, display: false),
                .text(" 和 "),
                .math(latex: #"\mathcal{U} = \{ \tilde{y}_1, \dots, \tilde{y}_M \}"#, display: false)
            ],
            "expected repeatedly escaped set notation and subscripts to normalize before math rendering; got \(overEscapedSegments)"
        )
        let rowBreakBeforeCommand = #"$$\begin{aligned}x &= 1\\\text{next}\end{aligned}$$"#
        try check(
            AIMessageContentParser.segments(in: rowBreakBeforeCommand) == [
                .math(
                    latex: #"\begin{aligned}x &= 1\\\text{next}\end{aligned}"#,
                    display: true
                )
            ],
            "expected a valid row break immediately followed by a command to remain unchanged"
        )
        let overEscapedReward = #"""
        $$
        R^{S}(V) =
        \\\begin{cases}
        \\\delta(Q)\\\frac{1}{|\\\tilde{Q}|}\\\sum_{m\\\in\\\tilde{Q}} r^{S}_{m}
        - \\\eta \\\frac{D}{1+D}, & |\\\tilde{Q}| > 0 \\\\
        -\\\eta, & |\\\tilde{Q}| = 0
        \\\end{cases}
        $$
        """#
        let expectedReward = #"R^{S}(V) = \begin{cases} \delta(Q)\frac{1}{|\tilde{Q}|}\sum_{m\in\tilde{Q}} r^{S}_{m} - \eta \frac{D}{1+D}, & |\tilde{Q}| > 0 \\ -\eta, & |\tilde{Q}| = 0 \end{cases}"#
        try check(
            AIMessageContentParser.segments(in: overEscapedReward) == [
                .math(latex: expectedReward, display: true)
            ],
            "expected a repeatedly escaped cases formula to normalize before rendering"
        )
        let overEscapedLoss = #"""
        $$
        \\\mathcal{L} =
        \\\mathcal{L}^{L}
        + \\\alpha \\\mathcal{L}^{S}
        + \\\beta \\\mathcal{L}^{KL}
        $$
        """#
        try check(
            AIMessageContentParser.segments(in: overEscapedLoss) == [
                .math(
                    latex: #"\mathcal{L} = \mathcal{L}^{L} + \alpha \mathcal{L}^{S} + \beta \mathcal{L}^{KL}"#,
                    display: true
                )
            ],
            "expected repeatedly escaped display commands to normalize before rendering"
        )
        try check(
            !AIMessageContentParser.isPlausibleLatex("x + 普通中文"),
            "expected Unicode prose outside a LaTeX text group to remain ordinary text"
        )
    }

    private static func markdownParserRecognizesReplyBlocks() throws {
        let blocks = AIChatMarkdownParser.blocks(in: """
        # Method

        - Encode frames
        - Rank evidence

        1. Train
        2. Evaluate

        > Important result

        | Metric | Score |
        | --- | ---: |
        | Accuracy | 91.2 |

        ```swift
        let score = 91.2
        ```
        """)
        try check(
            blocks.contains(.heading(level: 1, text: "Method")),
            "expected a Markdown heading"
        )
        try check(
            blocks.contains(.unorderedList(["Encode frames", "Rank evidence"])),
            "expected an unordered list"
        )
        try check(
            blocks.contains(.orderedList(start: 1, items: ["Train", "Evaluate"])),
            "expected an ordered list"
        )
        try check(
            blocks.contains(.blockquote("Important result")),
            "expected a block quote"
        )
        let nested = AIChatMarkdownParser.blocks(in: "- Parent\n  1. First\n     - Detail\n  2. Second\n- Sibling")
        try check(nested == [.structuredList([
            AIChatListItem(marker: "•", text: "Parent", depth: 0),
            AIChatListItem(marker: "1.", text: "First", depth: 1),
            AIChatListItem(marker: "▪", text: "Detail", depth: 2),
            AIChatListItem(marker: "2.", text: "Second", depth: 1),
            AIChatListItem(marker: "•", text: "Sibling", depth: 0)
        ])], "mixed nested lists must retain their markers, order and indentation")
        try check(
            blocks.contains(.table(
                headers: ["Metric", "Score"],
                rows: [["Accuracy", "91.2"]]
            )),
            "expected a table"
        )
        try check(
            blocks.contains(.code(language: "swift", content: "let score = 91.2")),
            "expected a fenced code block"
        )

        let displayWithListMarker = #"""
        $$
        R = \begin{cases}
        1, & x > 0 \\
        - \eta, & x \le 0
        \end{cases}
        $$
        """#
        try check(
            AIChatMarkdownParser.blocks(in: displayWithListMarker) == [
                .paragraph(displayWithListMarker)
            ],
            "expected list-like lines inside standalone display math to remain in one Markdown block"
        )
    }

    private static func openAIStreamDecoderReadsContentAndCompletion() throws {
        var decoder = OpenAIStreamDecoder()

        let delta = try decoder.decode(
            line: #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        )
        let done = try decoder.decode(line: "data: [DONE]")

        try check(delta == .contentDelta("Hello"), "expected the streamed content delta")
        try check(done == .finished, "expected the stream completion marker")
    }

    private static func universalWebAPIRequestsCarryTheLocalConversationIdentity() throws {
        let client = OpenAICompatibleClient()
        let configuration = AIProviderConfiguration(
            baseURL: "http://127.0.0.1:8199/url/chat.qwen.ai/v1",
            model: "qwen"
        )
        let request = try client.makeRequest(
            messages: [AIChatMessage(role: .user, content: "Explain the objective.")],
            configuration: configuration,
            apiKey: "test-key",
            conversationKey: "pdflight:conversation:local-a",
            conversationTitle: "Spatial-Agent · Method analysis"
        )
        let body = try checkNotNil(request.httpBody, "expected a JSON request body")
        let JSON = try checkNotNil(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
            "expected a JSON object"
        )

        try check(
            JSON["conversation_key"] as? String == "pdflight:conversation:local-a",
            "expected the local conversation UUID in conversation_key"
        )
        try check(
            JSON["conversation_title"] as? String == "Spatial-Agent · Method analysis",
            "expected the paper and local conversation names in conversation_title"
        )
        try check(
            (JSON["messages"] as? [[String: Any]])?.count == 1,
            "expected the visible request messages to remain intact"
        )
    }

    private static func imageAttachmentsStayPortableAndUseMultimodalRequestContent() throws {
        let legacy = #"{"id":"legacy","role":"user","content":"old chat","createdAt":0}"#.data(using: .utf8)!
        let decodedLegacy = try JSONDecoder().decode(AIChatMessage.self, from: legacy)
        try check(decodedLegacy.imageAttachments.isEmpty, "expected legacy text-only history to remain readable")

        let image = AIChatImageAttachment(
            id: "image-a",
            fileName: "diagram.png",
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47])
        )
        let message = AIChatMessage(role: .user, content: "Explain this diagram", imageAttachments: [image], pdfAttachmentName: "paper.pdf")
        let roundTrip = try JSONDecoder().decode(
            AIChatMessage.self,
            from: JSONEncoder().encode(message)
        )
        try check(roundTrip == message, "expected image data and PDF attachment name to survive portable JSON history")

        let client = OpenAICompatibleClient()
        let configuration = AIProviderConfiguration(baseURL: "https://example.com/v1", model: "vision-model")
        let request = try client.makeRequest(
            messages: [message],
            configuration: configuration,
            apiKey: "test"
        )
        let body = try checkNotNil(request.httpBody, "expected a multimodal request body")
        let json = try checkNotNil(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
            "expected a multimodal JSON object"
        )
        let messages = try checkNotNil(json["messages"] as? [[String: Any]], "expected request messages")
        let content = try checkNotNil(messages.first?["content"] as? [[String: Any]], "expected array content for images")
        try check(content.first?["type"] as? String == "text", "expected text before image content")
        let imageURL = (content.last?["image_url"] as? [String: Any])?["url"] as? String
        try check(
            imageURL == "data:image/png;base64,iVBORw==",
            "expected an inline data URL for the attached image"
        )

        let textRequest = try client.makeRequest(
            messages: [AIChatMessage(role: .user, content: "text only")],
            configuration: configuration,
            apiKey: "test"
        )
        let textBody = try checkNotNil(textRequest.httpBody, "expected a text request body")
        let textJSON = try checkNotNil(JSONSerialization.jsonObject(with: textBody) as? [String: Any], "expected text JSON")
        let textMessages = try checkNotNil(textJSON["messages"] as? [[String: Any]], "expected text messages")
        try check(textMessages.first?["content"] as? String == "text only", "expected text-only content to stay a string")
    }

    private static func localPDFsUseTheUniversalWebAPIAttachmentExtension() throws {
        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFlight-current-paper.pdf")
        let secondPDFURL = FileManager.default.temporaryDirectory.appendingPathComponent("PDFlight-second-paper.pdf")
        let localConfiguration = AIProviderConfiguration(
            baseURL: "http://127.0.0.1:8199/v1",
            model: "qwen"
        )
        let client = OpenAICompatibleClient()
        let request = try client.makeRequest(
            messages: [AIChatMessage(role: .user, content: "Read this paper")],
            configuration: localConfiguration,
            apiKey: "",
            currentPDFURL: pdfURL,
            additionalPDFURLs: [secondPDFURL, pdfURL]
        )
        let body = try checkNotNil(request.httpBody, "expected a PDF request body")
        let JSON = try checkNotNil(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
            "expected a PDF JSON request"
        )
        let PDFs = try checkNotNil(
            JSON["pdf_attachments"] as? [[String: Any]],
            "expected the Universal Web API PDF extension"
        )
        try check(PDFs.count == 2, "expected two distinct PDFs")
        try check(PDFs[0]["path"] as? String == pdfURL.path, "expected the local PDF path")
        try check(PDFs[0]["mime_type"] as? String == "application/pdf", "expected PDF MIME type")
        try check(PDFs[1]["path"] as? String == secondPDFURL.path, "expected second PDF path")

        do {
            let five = (0..<5).map { FileManager.default.temporaryDirectory.appendingPathComponent("fixture-\($0).pdf") }
            _ = try client.makeRequest(messages: [AIChatMessage(role: .user, content: "test")], configuration: localConfiguration, apiKey: "", additionalPDFURLs: five)
            throw CheckFailure(message: "expected the four-PDF limit to be enforced")
        } catch let error as OpenAICompatibleError {
            guard case .invalidConfiguration = error else { throw error }
        }

        do {
            _ = try client.makeRequest(
                messages: [AIChatMessage(role: .user, content: "Read this paper")],
                configuration: AIProviderConfiguration(
                    baseURL: "https://example.com/v1",
                    model: "remote"
                ),
                apiKey: "",
                currentPDFURL: pdfURL
            )
            throw CheckFailure(message: "expected local file paths to be rejected for remote APIs")
        } catch let error as OpenAICompatibleError {
            guard case .invalidConfiguration = error else { throw error }
        }
    }

    private static func attachmentOnlySubmissionsKeepTheSelectedPromptMode() throws {
        let reading = try checkNotNil(
            AIPromptTemplate.defaults.first { $0.id == AIPromptPreset.reading.rawValue },
            "expected the Reading prompt template"
        )
        let readingQuestion = AIChatRequestBuilder.displayQuestion(
            question: "",
            template: reading,
            hasImageAttachments: false,
            includeCurrentPDF: true
        )
        try check(
            readingQuestion == "Reading",
            "expected an attached PDF to use the selected Reading mode instead of an English fallback prompt"
        )
        let readingMessages = AIChatRequestBuilder.messages(
            instruction: reading.instruction(title: "Example Paper"),
            paperContext: nil,
            conversation: [AIChatMessage(role: .user, content: readingQuestion ?? "")]
        )
        try check(
            readingMessages.first?.role == .system
                && readingMessages.first?.content.contains("Example Paper") == true
                && readingMessages.last?.content == "Reading",
            "expected the Reading instruction and attached-PDF user turn to be sent together"
        )

        let custom = AIPromptTemplate(id: "methods", name: "Methods", prompt: "Analyze {{title}}")
        try check(
            AIChatRequestBuilder.displayQuestion(
                question: "",
                template: custom,
                hasImageAttachments: false,
                includeCurrentPDF: true
            ) == "Methods",
            "expected PDF upload to preserve a custom prompt mode"
        )
        try check(
            AIChatRequestBuilder.displayQuestion(
                question: "",
                template: AIPromptTemplate.defaults[0],
                hasImageAttachments: false,
                includeCurrentPDF: true
            ) == "Attached PDF",
            "expected No prompt PDF upload to use a neutral attachment label"
        )
        try check(
            AIChatRequestBuilder.displayQuestion(
                question: "Compare the ablation results",
                template: reading,
                hasImageAttachments: false,
                includeCurrentPDF: true
            ) == "Compare the ablation results",
            "expected typed text to remain the visible question when a PDF is attached"
        )
    }

    private static func queuedChatSubmissionsRemainFIFOAndKeepImages() throws {
        let image = AIChatImageAttachment(
            id: "queued-image",
            fileName: "figure.png",
            mimeType: "image/png",
            data: Data([1, 2, 3])
        )
        var queue = AIChatSubmissionQueue()
        let first = AIChatSubmission(
            question: "first",
            imageAttachments: [image],
            promptPreset: .none,
            includeCurrentPDF: true
        )
        let second = AIChatSubmission(question: "second", promptPreset: .reading)
        queue.enqueue(first)
        queue.enqueue(second)
        try check(queue.count == 2, "expected both submissions to be visible in the queue")
        try check(queue.dequeue() == first, "expected FIFO dequeue with image attachment intact")
        try check(first.includeCurrentPDF, "expected queued PDF attachment intent to remain intact")
        try check(queue.dequeue() == second, "expected the second submission after the first")
        try check(queue.isEmpty, "expected no queued work after both submissions")
    }

    private static func onlyLocalQwenUsesBoundWebConversations() throws {
        let localQwen = AIProviderConfiguration(
            baseURL: "http://127.0.0.1:8199/url/chat.qwen.ai/v1",
            model: "qwen"
        )
        let directOpenAI = AIProviderConfiguration(
            baseURL: "https://api.openai.com/v1",
            model: "gpt-5"
        )

        try check(
            AIConversationRouting.conversationKey(
                for: "local-a",
                configuration: localQwen
            ) == "pdflight:conversation:local-a",
            "expected local Qwen to bind the selected PDFlight conversation"
        )
        try check(
            AIConversationRouting.conversationKey(
                for: "local-a",
                configuration: directOpenAI
            ) == nil,
            "expected standard providers to receive no Universal Web API extension"
        )
        let gatewayQwen = AIProviderConfiguration(baseURL: "http://127.0.0.1:3425/v1", model: "uwa-lite-local/qwen")
        try check(AIConversationRouting.conversationKey(for: "local-a", configuration: gatewayQwen) == "pdflight:conversation:local-a", "the migrated Magpie Qwen route must retain a per-conversation web binding")
        let unrelated = AIProviderConfiguration(baseURL: "http://127.0.0.1:3425/v1", model: "other/qwen")
        try check(AIConversationRouting.conversationKey(for: "local-a", configuration: unrelated) == nil, "unrelated gateway models must not receive the Qwen-only binding")
    }

    private static func openAIStreamDecoderSeparatesReasoningFromFinalContent() throws {
        var decoder = OpenAIStreamDecoder()
        let reasoning = try decoder.decode(
            line: #"data: {"choices":[{"delta":{"reasoning_content":"checking the paper"}}]}"#
        )
        let answer = try decoder.decode(
            line: #"data: {"choices":[{"delta":{"content":"FINAL_OK"}}]}"#
        )

        try check(
            reasoning == .reasoningDelta("checking the paper"),
            "expected reasoning_content to be a distinct activity event"
        )
        try check(
            answer == .contentDelta("FINAL_OK"),
            "expected the final answer to remain a content event"
        )

        var accumulator = OpenAIStreamAccumulator()
        let thinkingProgress = accumulator.consume(try checkNotNil(
            reasoning,
            "expected a reasoning event"
        ))
        try check(
            thinkingProgress == .thinking(reasoningCharacters: 18),
            "expected reasoning to update activity without becoming answer text"
        )
        do {
            _ = try accumulator.finalAnswer()
            throw CheckFailure(message: "expected reasoning-only output to reject completion")
        } catch OpenAICompatibleError.missingFinalContent {
            // Expected: thinking is activity, not a persisted assistant reply.
        }

        let answeringProgress = accumulator.consume(try checkNotNil(
            answer,
            "expected a content event"
        ))
        try check(
            answeringProgress == .answering(receivedCharacters: 8),
            "expected answer progress to expose only a buffered character count"
        )
        let finalAnswer = try accumulator.finalAnswer()
        try check(
            finalAnswer == "FINAL_OK",
            "expected only final content to be persisted"
        )
    }

    private static func chatHistorySupportsPortablePerPaperConversations() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-ai-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstPDF = URL(fileURLWithPath: "/Users/reader/Papers/first.pdf")
        let secondPDF = URL(fileURLWithPath: "/Users/reader/Papers/second.pdf")
        let expectedMessages = [
            AIChatMessage(
                id: "question",
                role: .user,
                content: "What is the main contribution?",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            AIChatMessage(
                id: "answer",
                role: .assistant,
                content: "A lightweight testable reader.",
                createdAt: Date(timeIntervalSince1970: 1_700_000_001)
            )
        ]

        let firstConversation = AIConversation(
            id: "method-overview",
            title: "Method overview",
            promptPreset: .reading,
            messages: expectedMessages,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let followUp = AIConversation(
            id: "follow-up",
            title: "Ablation details",
            promptPreset: .none,
            messages: [
                AIChatMessage(
                    id: "ablation-question",
                    role: .user,
                    content: "Explain the ablations.",
                    createdAt: Date(timeIntervalSince1970: 1_700_000_002)
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_002),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_002)
        )
        let firstHistory = AIPaperChatHistory(
            documentTitle: firstPDF.lastPathComponent,
            documentPath: firstPDF.standardizedFileURL.path,
            activeConversationID: followUp.id,
            conversations: [firstConversation, followUp]
        )

        let writer = AIChatHistoryStore(directoryURL: directory)
        try await writer.save(firstHistory, for: firstPDF)

        let firstHistoryURL = writer.fileURL(for: firstPDF)
        try check(
            firstHistoryURL.deletingLastPathComponent() == directory
                && firstHistoryURL.pathExtension == "json"
                && FileManager.default.fileExists(atPath: firstHistoryURL.path),
            "expected the current paper's portable history URL to identify its saved JSON file"
        )

        var secondHistory = AIPaperChatHistory.new(for: secondPDF)
        secondHistory.conversations[0].title = "Second paper"
        try await writer.save(secondHistory, for: secondPDF)

        let reader = AIChatHistoryStore(directoryURL: directory)
        let restored = try await reader.history(for: firstPDF)
        let unrelated = try await reader.history(for: secondPDF)
        let library = try await reader.allHistories()

        try check(restored == firstHistory, "expected all conversations to survive reload")
        try check(restored.conversations.count == 2, "expected multiple conversations for one paper")
        try check(
            unrelated.conversations.allSatisfy(\.messages.isEmpty),
            "expected another PDF to have independent conversations"
        )
        try check(
            Set(library.map(\.documentTitle)) == Set(["first.pdf", "second.pdf"]),
            "expected the history library to group saved chats by paper"
        )

        let JSONFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
        let portableData = try Data(contentsOf: try checkNotNil(JSONFiles.first, "expected a JSON history file"))
        let portableText = try checkNotNil(
            String(data: portableData, encoding: .utf8),
            "expected UTF-8 JSON"
        )
        try check(portableText.contains("\n"), "expected pretty-printed JSON")
        try check(portableText.contains("\"formatVersion\""), "expected a versioned migration format")
        try check(portableText.contains("\"documentPath\""), "expected the paper path in the portable file")
        try check(portableText.contains("\"conversations\""), "expected conversations in the portable file")
    }

    private static func paperContextCarriesPageBoundariesAndStopsAtItsBudget() async throws {
        let engine = StubDocumentEngine(textByPage: [
            "First page text.",
            "Second page text.",
            "Third page must not be included."
        ])

        let context = try await PaperContextBuilder.build(
            engine: engine,
            title: "Example Paper.pdf",
            maximumCharacters: 40
        )

        try check(context.text.contains("Title: Example Paper.pdf"), "expected the PDF title")
        try check(context.text.contains("[Page 1]"), "expected a page-one marker")
        try check(context.text.contains("First page text."), "expected page-one text")
        try check(context.text.contains("[Page 2]"), "expected a page-two marker")
        try check(!context.text.contains("Third page must not be included."), "expected the budget to stop before page three")
        try check(context.includedPageCount == 2, "expected exactly two included pages")
        try check(context.totalPageCount == 3, "expected the source page count")
        try check(context.wasTruncated, "expected truncation to be reported")

        let contextWithBlankPage = try await PaperContextBuilder.build(
            engine: StubDocumentEngine(textByPage: ["Only text page.", ""]),
            title: "Blank trailing page.pdf",
            maximumCharacters: 40
        )
        try check(
            !contextWithBlankPage.wasTruncated,
            "expected a blank page not to be reported as budget truncation"
        )
    }

    private static func promptPresetsStartNewConversationsInReadingMode() throws {
        try check(
            AIPromptPreset.defaultForNewConversation == .none,
            "expected No prompt to be the default for a new conversation"
        )
        try check(
            AIPromptPreset.none.instruction(title: "Paper.pdf") == nil,
            "expected the default option not to add an instruction prompt"
        )
        try check(
            AIPromptPreset.none.displayQuestion(for: "") == nil,
            "expected an empty question without a preset not to send"
        )

        let reading = try checkNotNil(
            AIPromptPreset.reading.instruction(title: "Actual Paper Title"),
            "expected Reading to provide an instruction prompt"
        )
        try check(
            reading.hasPrefix("Title: Actual Paper Title\n去arxiv/openreview/acl/ 等学术网站上找一下这篇论文。"),
            "expected Reading to substitute the active PDF title"
        )
        try check(reading.contains("0. 翻译摘要原文"), "expected the requested abstract translation section")
        try check(reading.contains("方法设计"), "expected the requested methodology section")
        try check(reading.contains("学习与应用"), "expected the requested application section")
        try check(reading.contains("不要出现markdown的标题格式"), "expected the requested output rule")
        try check(
            AIPromptPreset.reading.displayQuestion(for: "") == "Reading",
            "expected Reading to be sendable without an extra question"
        )
    }

    private static func promptTemplatesAreEditableAndPortable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-prompt-modes-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("prompt-templates.json")
        let store = AIPromptTemplateStore(fileURL: fileURL)

        var templates = try await store.templates()
        try check(
            templates.map(\.id).prefix(2) == ["none", "reading"],
            "expected editable No prompt and Reading defaults"
        )
        let readingIndex = try checkNotNil(
            templates.firstIndex { $0.id == AIPromptPreset.reading.rawValue },
            "expected a Reading template"
        )
        templates[readingIndex].prompt = "Study {{title}} closely."
        let custom = AIPromptTemplate(
            id: "methods-only",
            name: "Methods only",
            prompt: "Explain the method in {{title}}."
        )
        templates.append(custom)
        try await store.save(templates)

        let restored = try await store.templates()
        try check(
            restored.first { $0.id == "reading" }?.instruction(title: "Paper")
                == "Study Paper closely.",
            "expected edited built-in prompts to survive reload"
        )
        try check(
            restored.first { $0.id == custom.id }?.instruction(title: "Paper")
                == "Explain the method in Paper.",
            "expected a custom prompt mode to survive reload"
        )
        let encodedPreset = try JSONEncoder().encode(custom.preset)
        let decodedPreset = try JSONDecoder().decode(AIPromptPreset.self, from: encodedPreset)
        try check(
            decodedPreset == custom.preset,
            "expected custom prompt IDs to remain portable string values"
        )
    }

    private static func requestsContainNoHiddenPaperContext() throws {
        let question = AIChatMessage(
            id: "question-only",
            role: .user,
            content: "Explain the result.",
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let context = PaperContext(
            text: "Title: Test Paper\n\n[Page 12]\nHIDDEN_PDF_TEXT",
            includedPageCount: 12,
            totalPageCount: 30,
            wasTruncated: true
        )

        let plain = AIChatRequestBuilder.messages(
            preset: .none,
            title: "Test Paper",
            paperContext: context,
            conversation: [question]
        )
        try check(plain == [question], "expected No prompt to send only the visible conversation")
        try check(
            plain.allSatisfy { !$0.content.contains("HIDDEN_PDF_TEXT") },
            "expected no extracted PDF pages in a No prompt request"
        )

        let reading = AIChatRequestBuilder.messages(
            preset: .reading,
            title: "Test Paper",
            paperContext: context,
            conversation: [question]
        )
        try check(
            reading.allSatisfy { !$0.content.contains("HIDDEN_PDF_TEXT") },
            "expected Reading to exclude automatic PDF page context"
        )
        try check(
            reading.contains { $0.content.contains("方法设计") },
            "expected Reading to include its selected analysis instruction"
        )
        try check(
            !AIChatRequestBuilder.needsPaperContext(for: .none)
                && !AIChatRequestBuilder.needsPaperContext(for: .reading),
            "expected every current prompt mode to skip PDF extraction"
        )
    }

    private static func localWebBridgeEndpointsAndReadiness() async throws {
        let bridge = LocalWebBridge()
        try check(
            bridge.bridgeEndpoint(from: "https://api.openai.com/v1") == nil,
            "expected remote provider URLs to skip the local bridge"
        )
        let endpoint = try checkNotNil(
            bridge.bridgeEndpoint(from: "http://127.0.0.1:8199/v1"),
            "expected a loopback base URL to resolve to a bridge endpoint"
        )
        try check(endpoint.port == 8199, "expected the bridge endpoint to keep the configured port")
        let remoteReady = await bridge.ensureReady(for: "https://api.openai.com/v1")
        try check(
            remoteReady,
            "expected remote providers to count as ready without spawning"
        )
        let deadPortReady = await bridge.probe(
            LocalWebBridge.Endpoint(scheme: "http", host: "127.0.0.1", port: 59999)
        )
        try check(
            deadPortReady == false,
            "expected probing an unused port to report not-ready"
        )
        if let value = ProcessInfo.processInfo.environment["PDFLIGHT_TEST_HTTP_PORT"], let port = Int(value) {
            let otherService = LocalWebBridge.Endpoint(scheme: "http", host: "127.0.0.1", port: port)
            let healthy = await bridge.probe(otherService)
            let listening = await bridge.responds(otherService)
            let ready = await bridge.ensureReady(for: "http://127.0.0.1:\(port)/v1")
            try check(!healthy && listening && ready, "a local API returning 404 for /health must not cause uwa-lite to start")
        }
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(message: message) }
    }

    private static func checkNotNil<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw CheckFailure(message: message) }
        return value
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

private actor StubDocumentEngine: DocumentEngine {
    nonisolated let pageCount: Int
    private let textByPage: [String]

    init(textByPage: [String]) {
        self.textByPage = textByPage
        self.pageCount = textByPage.count
    }

    func outline() throws -> [DocumentOutlineEntry] { [] }

    func page(at index: Int) throws -> DocumentPage {
        DocumentPage(index: index, width: 600, height: 800, links: [])
    }

    func text(on pageIndex: Int) throws -> DocumentTextPage {
        DocumentTextPage(pageIndex: pageIndex, glyphs: [], plainText: textByPage[pageIndex])
    }

    func search(_ query: String) throws -> [DocumentSearchHit] { [] }

    func render(_ request: PageRenderRequest) throws -> RenderedPage {
        RenderedPage(width: 1, height: 1, bytesPerRow: 4, pixels: Data(repeating: 0, count: 4))
    }

    func add(_ annotation: DocumentAnnotationDraft) throws {}
    func undoLastAnnotation() throws -> Int? { nil }
    func save(to url: URL) throws {}
    func releaseMemory() {}
}
