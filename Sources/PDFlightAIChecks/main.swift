import Foundation
import PDFlightAI
import PDFlightCore

@main
enum PDFlightAIChecks {
    static func main() async throws {
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
        let message = AIChatMessage(role: .user, content: "Explain this diagram", imageAttachments: [image])
        let roundTrip = try JSONDecoder().decode(
            AIChatMessage.self,
            from: JSONEncoder().encode(message)
        )
        try check(roundTrip == message, "expected image data to survive portable JSON history")

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
        let localConfiguration = AIProviderConfiguration(
            baseURL: "http://127.0.0.1:8199/v1",
            model: "qwen"
        )
        let client = OpenAICompatibleClient()
        let request = try client.makeRequest(
            messages: [AIChatMessage(role: .user, content: "Read this paper")],
            configuration: localConfiguration,
            apiKey: "",
            currentPDFURL: pdfURL
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
        try check(PDFs.count == 1, "expected exactly one current PDF")
        try check(PDFs[0]["path"] as? String == pdfURL.path, "expected the local PDF path")
        try check(PDFs[0]["mime_type"] as? String == "application/pdf", "expected PDF MIME type")

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
