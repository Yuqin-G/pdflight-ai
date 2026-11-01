import AppKit
import PDFlightAI
import UniformTypeIdentifiers

/// Native paper conversation. The conversation engine, history, and draft
/// persistence are owned by PDFlight; no WebKit view is used here.
@MainActor
final class NativePaperChatSidebar: NSView, NSTextViewDelegate {
    static let customRouteID = "__pdflight_custom_model__"
    static func selfCheck() throws {
        guard AIChatRenderedContentView.harnessLinkHitTestForLayoutCheck() else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 10, userInfo: [NSLocalizedDescriptionKey: "主题链接必须保持可点击"])
        }
        let markdown = AIChatRenderedContentView(); markdown.useHarnessTypography()
        markdown.setContent("**论文中的描述**：\n在论文中提到。", renderMarkdown: true)
        guard markdown.renderedTextForLayoutCheck().contains("论文中的描述： 在论文中提到。") else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 19, userInfo: [NSLocalizedDescriptionKey: "Markdown 段落中的软换行必须与 Harness 一致"])
        }
        markdown.setContent("**具体数值**：\n在论文中给出：\n$$\nx=1\n$$", renderMarkdown: true)
        guard markdown.renderedTextForLayoutCheck().contains("具体数值： 在论文中给出："), markdown.renderedMathLatexForLayoutCheck().contains("x=1") else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 20, userInfo: [NSLocalizedDescriptionKey: "软换行不能影响独立公式"])
        }
        markdown.setContent("第一行  \n第二行", renderMarkdown: true)
        guard markdown.renderedTextForLayoutCheck().contains("第一行\n第二行") else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 21, userInfo: [NSLocalizedDescriptionKey: "Markdown 硬换行必须保留"])
        }
        let sidebar = NativePaperChatSidebar(frame: NSRect(x: 0, y: 0, width: 440, height: 700))
        var savedText = ""; var savedImages: [AIChatImageAttachment] = []; var savedPDF = false
        sidebar.onDraftChange = { text, images, pdf, _, _, _ in savedText = text; savedImages = images; savedPDF = pdf }
        sidebar.restoreDraft("existing draft", attachments: [], includePDF: false)
        sidebar.insertQuote("[Paper · p. 2]\nquoted text\n\n")
        guard savedText == "[Paper · p. 2]\nquoted text\n\nexisting draft" else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "引用必须保留原有草稿"])
        }
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("pdflight-native-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let png = Data([137, 80, 78, 71, 13, 10, 26, 10])
        pasteboard.declareTypes([.png], owner: nil); pasteboard.setData(png, forType: .png)
        sidebar.composer.onImages?(NativePaperComposer.readImages(pasteboard))
        guard savedImages.count == 1, savedImages[0].data == png, savedText.hasSuffix("existing draft") else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "粘贴图片必须进入草稿且保留文字"])
        }
        sidebar.setPaperTitle("缩放测试论文")
        guard sidebar.toolTip == nil else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 25, userInfo: [NSLocalizedDescriptionKey: "聊天正文悬停时不能显示论文标题提示"])
        }
        sidebar.togglePDF()
        guard sidebar.attachmentStack.arrangedSubviews.compactMap({ $0 as? NSStackView })
            .flatMap({ $0.arrangedSubviews.compactMap { $0 as? NSTextField } })
            .contains(where: { $0.stringValue.contains("缩放测试论文") }) else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 26, userInfo: [NSLocalizedDescriptionKey: "移除悬停提示后 PDF 附件仍须显示论文名称"])
        }
        guard savedPDF else { throw NSError(domain: "NativePaperChatSelfCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "附加 PDF 的选择必须进入草稿"]) }
        guard sidebar.attachmentStack.arrangedSubviews.count == 2, !sidebar.attachmentScroll.isHidden,
              sidebar.attachmentStack.frame.width > 0 else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 11, userInfo: [NSLocalizedDescriptionKey: "图片和 PDF 附件卡片必须可见"])
        }
        var submitted = false
        sidebar.onSend = { text, images, _, pdf, _, _ in submitted = text == savedText && images == savedImages && pdf }
        sidebar.sendOrStop()
        guard submitted else { throw NSError(domain: "NativePaperChatSelfCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "发送必须包含草稿和附件"]) }
        submitted = false
        sidebar.setStreaming(true)
        _ = sidebar.textView(sidebar.composer, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        guard submitted else { throw NSError(domain: "NativePaperChatSelfCheck", code: 7, userInfo: [NSLocalizedDescriptionKey: "回复期间按回车必须排队发送草稿"]) }
        submitted = false; sidebar.sendOrStop()
        guard submitted else { throw NSError(domain: "NativePaperChatSelfCheck", code: 8, userInfo: [NSLocalizedDescriptionKey: "回复期间有草稿时按钮必须发送草稿"]) }
        sidebar.clearComposer()
        var stopped = false; sidebar.onCancel = { stopped = true }; sidebar.sendOrStop()
        guard stopped else { throw NSError(domain: "NativePaperChatSelfCheck", code: 9, userInfo: [NSLocalizedDescriptionKey: "回复期间没有草稿时按钮必须停止回复"]) }
        sidebar.setStreaming(false)
        sidebar.restoreDraft("保留文字", attachments: [AIChatImageAttachment(fileName: "fixture.png", mimeType: "image/png", data: png)], includePDF: true)
        (sidebar.attachmentStack.arrangedSubviews.last as? AIChatImageChip)?.onRemove?()
        guard sidebar.attachments.isEmpty, sidebar.includePDF, sidebar.composer.string == "保留文字" else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 12, userInfo: [NSLocalizedDescriptionKey: "移除单张图片不能清除 PDF 或文字"])
        }
        let extraPath = "/tmp/pdflight-fixture-extra.pdf"
        sidebar.restoreDraft("附件草稿", attachments: [], includePDF: true, additionalPDFPaths: [extraPath])
        guard sidebar.additionalPDFPaths == [extraPath], sidebar.attachmentStack.arrangedSubviews.count == 2 else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 13, userInfo: [NSLocalizedDescriptionKey: "额外 PDF 必须随草稿恢复并显示"])
        }
        var sentExtra: [String] = []
        sidebar.onSend = { _, _, _, _, paths, _ in sentExtra = paths }
        sidebar.sendOrStop()
        guard sentExtra == [extraPath] else { throw NSError(domain: "NativePaperChatSelfCheck", code: 14, userInfo: [NSLocalizedDescriptionKey: "发送必须包含额外 PDF"]) }
        sidebar.composer.string = "保留文字 /mod 后文"
        sidebar.composer.setSelectedRange(NSRange(location: ("保留文字 /mod" as NSString).length, length: 0))
        guard sidebar.slashTrigger()?.query == "mod" else { throw NSError(domain: "NativePaperChatSelfCheck", code: 15, userInfo: [NSLocalizedDescriptionKey: "斜杠指令应识别光标前的候选"]) }
        sidebar.consumeSlashTrigger()
        guard sidebar.composer.string == "保留文字  后文" else { throw NSError(domain: "NativePaperChatSelfCheck", code: 16, userInfo: [NSLocalizedDescriptionKey: "执行指令必须保留其前后的草稿"]) }
        let reference = AIChatDraftReference(source: "reference", ref: "@paper.pdf", offset: 3, length: 10, label: "paper.pdf", appearance: "file", clipboardText: "@paper.pdf")
        sidebar.restoreDraft("草稿 @paper.pdf", attachments: [], includePDF: false, references: [reference])
        sidebar.insertQuote("引文\n")
        guard sidebar.draftReferences.first?.offset == 6 else { throw NSError(domain: "NativePaperChatSelfCheck", code: 17, userInfo: [NSLocalizedDescriptionKey: "插入引文必须调整引用位置"]) }
        _ = sidebar.textView(sidebar.composer, shouldChangeTextIn: NSRange(location: 7, length: 1), replacementString: "x")
        guard sidebar.draftReferences.isEmpty else { throw NSError(domain: "NativePaperChatSelfCheck", code: 18, userInfo: [NSLocalizedDescriptionKey: "编辑引用时不能保留错误引用"]) }
        let pdfMessage = AIChatMessage(role: .user, content: "阅读附件", pdfAttachmentName: "paper.pdf")
        sidebar.append(pdfMessage)
        let row = sidebar.messageRows[pdfMessage.id] as? NSStackView
        guard row?.arrangedSubviews.contains(where: { ($0 as? NSTextField)?.stringValue.contains("paper.pdf") == true }) == true else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 5, userInfo: [NSLocalizedDescriptionKey: "历史消息必须显示 PDF 附件"])
        }
        let answer = AIChatMessage(role: .assistant, content: "测试回答")
        var feedback: String?; sidebar.onFeedback = { id, value in if id == answer.id { feedback = value } }
        sidebar.append(answer)
        let timedAnswer = AIChatMessage(role: .assistant, content: "回答", reasoning: "过程", elapsedSeconds: 65)
        sidebar.append(timedAnswer)
        guard sidebar.reasoningButtons[timedAnswer.id]?.title.contains("1分5秒") == true else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 22, userInfo: [NSLocalizedDescriptionKey: "完成时间必须在历史中恢复"])
        }
        sidebar.feedbackButtons[answer.id]?.0.performClick(nil)
        guard feedback == "positive" else { throw NSError(domain: "NativePaperChatSelfCheck", code: 6, userInfo: [NSLocalizedDescriptionKey: "回答反馈必须能切换"]) }
        let savedZoom = UserDefaults.standard.object(forKey: "reader.nativePaperChatZoom")
        defer {
            if let savedZoom { UserDefaults.standard.set(savedZoom, forKey: "reader.nativePaperChatZoom") }
            else { UserDefaults.standard.removeObject(forKey: "reader.nativePaperChatZoom") }
        }
        let layoutWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        layoutWindow.contentView = sidebar
        defer { layoutWindow.contentView = nil }
        sidebar.setChatZoom(1)
        sidebar.layoutSubtreeIfNeeded()
        sidebar.previewChatZoomChange(40, phase: .changed)
        guard sidebar.chatZoom == 1, let preview = sidebar.previewChatZoom, preview > 1,
              abs(sidebar.messagesScroll.magnification - preview) < 0.01 else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 23, userInfo: [NSLocalizedDescriptionKey: "捏合时必须先预览，不逐次重建消息"])
        }
        sidebar.messagesScroll.layoutSubtreeIfNeeded()
        sidebar.messagesStack.layoutSubtreeIfNeeded()
        let visibleWidth = sidebar.messagesScroll.documentVisibleRect.width
        if visibleWidth <= 0 || sidebar.messagesStack.frame.width > visibleWidth + 1 {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 27, userInfo: [NSLocalizedDescriptionKey: "捏合时消息内容不能超出可见宽度"])
        }
        sidebar.previewChatZoomChange(0, phase: .ended)
        guard sidebar.previewChatZoom == nil, abs(sidebar.chatZoom - preview) < 0.001,
              abs(sidebar.messagesScroll.magnification - 1) < 0.001 else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 24, userInfo: [NSLocalizedDescriptionKey: "捏合结束后必须应用并保存最终缩放"])
        }
        if ProcessInfo.processInfo.environment["PDFLIGHT_BENCHMARK_ZOOM"] == "1" {
            let fixture = String(repeating: "**实验结果**：这是一段较长的论文分析，包含中文与 English text。\n\n", count: 12)
            for _ in 0..<20 { sidebar.append(AIChatMessage(role: .assistant, content: fixture)) }
            sidebar.layoutSubtreeIfNeeded()
            var start = Date()
            for index in 0..<20 { sidebar.setChatZoom(1 + CGFloat(index) * 0.005) }
            let rebuildDuration = Date().timeIntervalSince(start)
            sidebar.setChatZoom(1)
            start = Date()
            for _ in 0..<20 { sidebar.previewChatZoomChange(1.25, phase: .changed) }
            let previewDuration = Date().timeIntervalSince(start)
            start = Date()
            sidebar.previewChatZoomChange(0, phase: .ended)
            let commitDuration = Date().timeIntervalSince(start)
            print(String(format: "Zoom benchmark (20 messages, 20 events): rebuild %.3fs, preview %.3fs, final reflow %.3fs", rebuildDuration, previewDuration, commitDuration))
        }
    }
    var onSend: ((String, [AIChatImageAttachment], AIPromptPreset, Bool, [String], [AIChatDraftReference]) -> Void)?
    var onConfigure: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onSelectConversation: ((String) -> Void)?
    var onDeleteConversation: ((String) -> Void)?
    var onDeleteMessage: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onResizeBy: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onDraftChange: ((String, [AIChatImageAttachment], Bool, [String], [AIChatDraftReference], AIChatDraftCommand?) -> Void)?
    var onRevealCurrentHistory: (() -> Void)?
    var onPresetChange: ((AIPromptPreset) -> Void)?
    var onApplyPrompt: ((AIPromptPreset) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onSelectReasoning: ((String?) -> Void)?
    var onSelectAccessMode: ((AIChatAccessMode) -> Void)?
    var onFeedback: ((String, String?) -> Void)?
    var onBranchMessage: ((String) -> Void)?

    private let tabs = NSStackView()
    private let tabScroll = NSScrollView()
    private let addButton = NSButton(title: "+ 新建对话", target: nil, action: nil)
    private let zoomButton = NSButton(title: "100%", target: nil, action: nil)
    private var zoomWidth: NSLayoutConstraint?
    private let presetPopup = NativePaperPresetPopup()
    private let applyButton = NativePaperToolbarButton(title: "填入输入框", target: nil, action: nil)
    private let recordButton = NativePaperToolbarButton(title: "▤", target: nil, action: nil)
    private let webButton = NativePaperToolbarButton(title: "↗", target: nil, action: nil)
    private let messagesScroll = NativePaperChatScrollView()
    private let messagesStack = NativePaperMessageStack()
    private var messagesWidthConstraint: NSLayoutConstraint?
    private let composerCard = NSView()
    private let attachmentScroll = NSScrollView()
    private let attachmentStack = NSStackView()
    private var attachmentHeight: NSLayoutConstraint?
    private let composerScroll = NSScrollView()
    private let composer = NativePaperComposer()
    private var composerHeight: NSLayoutConstraint?
    private let attachButton = NSButton(title: "+", target: nil, action: nil)
    private let modelButton = NSButton(title: "选择模型 ▾", target: nil, action: nil)
    private let accessButton = NSButton(title: "仅可查看 ▾", target: nil, action: nil)
    private let sendButton = NSButton(title: "↑", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")
    private let resizeHandle = NativePaperChatResizeHandle()
    private var messages: [String: AIChatRenderedContentView] = [:]
    private var messageRows: [String: NSView] = [:]
    private var messageContents: [String: String] = [:]
    private var userBubbleWidths: [String: NSLayoutConstraint] = [:]
    private var userBubbleHasImages: Set<String> = []
    private var reasoningViews: [String: NSTextField] = [:]
    private var reasoningButtons: [String: NSButton] = [:]
    private var messageActivityStarted: [String: Date] = [:]
    private var messageActivityText: [String: String] = [:]
    private var assistantFooters: [String: NSStackView] = [:]
    private var footerButtonSizes: [NSLayoutConstraint] = []
    private var feedbackButtons: [String: (NSButton, NSButton)] = [:]
    private var attachments: [AIChatImageAttachment] = []
    private var includePDF = false
    private var additionalPDFPaths: [String] = []
    private var draftReferences: [AIChatDraftReference] = []
    private var draftCommand: AIChatDraftCommand?
    private var templates = NativePaperPrompts.templates
    private var selectedPreset = AIPromptPreset.reading
    private var busy = false
    private var suppressDraftCallback = false
    private var modelRoutes: [HarnessModelImport.Route] = []
    private var currentModelRouteID: String?
    private var currentReasoningEffort: String?
    private var accessMode: AIChatAccessMode = .readOnly
    private var customModelTitle = "自定义模型"
    private var paperTitle = "当前 PDF"
    private var webConversationURL: URL?
    private var modelPanel: NativeModelPanel?
    private var composerMenuPanel: NativeModelPanel?
    private var slashMenuOpen = false
    private var dismissedSlashLocation: Int?
    private var referenceMenuOpen = false
    private var dismissedReferenceLocation: Int?
    private var referenceSearchTask: Task<Void, Never>?
    private var referenceDirectory: URL?
    private var referenceConversations: [AIConversation] = []
    private var referenceConversationID: String?
    private var chatZoom: CGFloat = {
        let value = UserDefaults.standard.double(forKey: "reader.nativePaperChatZoom")
        return value >= 0.8 && value <= 2.4 ? value : 1
    }()
    // During a gesture, scale the existing view instead of rebuilding every
    // Markdown and formula view for every trackpad event. Reflow once at rest.
    private var previewChatZoom: CGFloat?
    private var zoomCommitWork: DispatchWorkItem?
    private static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 18/255, green: 17/255, blue: 16/255, alpha: 1)
            : NSColor(srgbRed: 247/255, green: 245/255, blue: 239/255, alpha: 1)
    }
    private static let accent = NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = Self.background.cgColor }
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Self.background.cgColor
        tabs.orientation = .horizontal; tabs.alignment = .centerY; tabs.spacing = 3
        tabScroll.hasHorizontalScroller = true; tabScroll.autohidesScrollers = true
        tabScroll.borderType = .noBorder; tabScroll.drawsBackground = false; tabScroll.scrollerStyle = .overlay
        tabs.translatesAutoresizingMaskIntoConstraints = false; tabScroll.documentView = tabs
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            tabs.bottomAnchor.constraint(equalTo: tabScroll.contentView.bottomAnchor),
            tabs.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor),
            tabs.widthAnchor.constraint(greaterThanOrEqualTo: tabScroll.contentView.widthAnchor)
        ])
        addButton.target = self; addButton.action = #selector(addConversation)
        addButton.isBordered = false; addButton.font = .systemFont(ofSize: 12)
        zoomButton.target = self; zoomButton.action = #selector(resetChatZoom); zoomButton.isBordered = false; zoomButton.font = .systemFont(ofSize: 11)
        zoomButton.title = "\(Int((chatZoom * 100).rounded()))%"; zoomButton.isHidden = abs(chatZoom - 1) < 0.005
        let top = NSView()
        tabScroll.translatesAutoresizingMaskIntoConstraints = false; addButton.translatesAutoresizingMaskIntoConstraints = false; zoomButton.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(tabScroll); top.addSubview(addButton); top.addSubview(zoomButton)
        let zoomWidth = zoomButton.widthAnchor.constraint(equalToConstant: zoomButton.isHidden ? 0 : 40); zoomWidth.isActive = true; self.zoomWidth = zoomWidth
        NSLayoutConstraint.activate([
            tabScroll.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 8),
            tabScroll.topAnchor.constraint(equalTo: top.topAnchor), tabScroll.bottomAnchor.constraint(equalTo: top.bottomAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: zoomButton.leadingAnchor, constant: -6),
            zoomButton.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -6), zoomButton.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -12), addButton.centerYAnchor.constraint(equalTo: top.centerYAnchor)
        ])
        top.heightAnchor.constraint(equalToConstant: 49).isActive = true
        let promptLabel = NSTextField(labelWithString: "阅读提示词")
        promptLabel.font = .systemFont(ofSize: 11); promptLabel.textColor = .secondaryLabelColor
        presetPopup.font = .systemFont(ofSize: 11); presetPopup.target = self; presetPopup.action = #selector(changePreset)
        presetPopup.isBordered = false; presetPopup.wantsLayer = true
        presetPopup.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        presetPopup.layer?.borderWidth = 0.5; presetPopup.layer?.borderColor = NSColor.separatorColor.cgColor
        presetPopup.layer?.cornerRadius = 5
        presetPopup.heightAnchor.constraint(equalToConstant: 26).isActive = true
        applyButton.isBordered = false; applyButton.font = .systemFont(ofSize: 11)
        applyButton.target = self; applyButton.action = #selector(applyPreset)
        recordButton.isBordered = false; recordButton.setAccessibilityLabel("打开会话记录目录")
        recordButton.target = self; recordButton.action = #selector(revealHistory)
        webButton.isBordered = false; webButton.setAccessibilityLabel("在网页继续对话")
        webButton.target = self; webButton.action = #selector(openWebConversation); webButton.isEnabled = false
        for button in [recordButton, webButton] {
            button.drawsOutline = true
            button.widthAnchor.constraint(equalToConstant: 26).isActive = true
            button.heightAnchor.constraint(equalToConstant: 25).isActive = true
            button.font = .systemFont(ofSize: 16)
        }
        let prompts = NSStackView(views: [promptLabel, presetPopup, applyButton, recordButton, webButton])
        prompts.orientation = .horizontal; prompts.alignment = .centerY; prompts.distribution = .fill; prompts.spacing = 7
        prompts.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for control in [promptLabel, applyButton, recordButton, webButton] {
            control.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        messagesStack.orientation = .vertical; messagesStack.alignment = .trailing; messagesStack.spacing = 18
        messagesStack.edgeInsets = NSEdgeInsets(top: 18, left: 16, bottom: 18, right: 16)
        messagesScroll.hasVerticalScroller = true; messagesScroll.autohidesScrollers = true
        messagesScroll.drawsBackground = false; messagesScroll.documentView = messagesStack
        messagesScroll.allowsMagnification = true
        messagesScroll.minMagnification = 1.0 / 3.0
        messagesScroll.maxMagnification = 3.0
        messagesScroll.onZoom = { [weak self] delta, phase in self?.previewChatZoomChange(delta, phase: phase) }
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        let messageWidth = messagesStack.widthAnchor.constraint(equalTo: messagesScroll.contentView.widthAnchor, constant: -16)
        messageWidth.isActive = true; messagesWidthConstraint = messageWidth
        composerCard.wantsLayer = true; composerCard.layer?.cornerRadius = 14
        composerCard.layer?.borderWidth = 0.5; composerCard.layer?.borderColor = NSColor.separatorColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { composerCard.layer?.backgroundColor = NativeHarnessStyle.input.cgColor }
        composerScroll.drawsBackground = false; composerScroll.hasVerticalScroller = true; composerScroll.autohidesScrollers = true
        composer.isRichText = false; composer.drawsBackground = false; composer.font = .systemFont(ofSize: 14 * chatZoom)
        composer.textContainerInset = NSSize(width: 7, height: 4); composer.delegate = self
        composer.isVerticallyResizable = true; composer.isHorizontallyResizable = false
        composer.textContainer?.widthTracksTextView = true
        composer.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        updateComposerTypography()
        composer.registerForDraggedTypes([.fileURL, .png, .tiff])
        composer.onImages = { [weak self] images in
            guard let self else { return }
            self.attachments.append(contentsOf: images.prefix(max(0, 4 - self.attachments.count)))
            self.updateAttachments(); self.draftChanged()
        }
        composerScroll.documentView = composer
        attachButton.isBordered = false; attachButton.target = self; attachButton.action = #selector(attach)
        attachButton.setAccessibilityLabel("添加图片或当前 PDF")
        attachButton.attributedTitle = NSAttributedString(string: "+", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NativeHarnessStyle.primary])
        modelButton.isBordered = false; modelButton.font = .systemFont(ofSize: 13); modelButton.lineBreakMode = .byTruncatingTail
        modelButton.target = self; modelButton.action = #selector(configureModel)
        accessButton.isBordered = false; accessButton.font = .systemFont(ofSize: 13)
        accessButton.image = NSImage(systemSymbolName: "exclamationmark.shield", accessibilityDescription: nil); accessButton.imagePosition = .imageLeading
        accessButton.target = self; accessButton.action = #selector(configureAccess)
        sendButton.isBordered = false; sendButton.target = self; sendButton.action = #selector(sendOrStop)
        updateSendButton()
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [attachButton, accessButton, spacer, modelButton, sendButton])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 6
        attachButton.widthAnchor.constraint(equalToConstant: 28).isActive = true
        sendButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        for button in [attachButton, accessButton, sendButton] { button.setContentCompressionResistancePriority(.required, for: .horizontal) }
        modelButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        attachmentStack.orientation = .horizontal; attachmentStack.alignment = .centerY; attachmentStack.spacing = 8
        attachmentScroll.drawsBackground = false; attachmentScroll.hasHorizontalScroller = true; attachmentScroll.autohidesScrollers = true
        attachmentScroll.documentView = attachmentStack; attachmentScroll.isHidden = true
        attachmentScroll.translatesAutoresizingMaskIntoConstraints = false
        composerScroll.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
        composerCard.addSubview(attachmentScroll); composerCard.addSubview(composerScroll); composerCard.addSubview(footer)
        let attachmentHeight = attachmentScroll.heightAnchor.constraint(equalToConstant: 0); attachmentHeight.isActive = true; self.attachmentHeight = attachmentHeight
        let height = composerScroll.heightAnchor.constraint(equalToConstant: 36); height.isActive = true; composerHeight = height
        NSLayoutConstraint.activate([
            attachmentScroll.topAnchor.constraint(equalTo: composerCard.topAnchor, constant: 6),
            attachmentScroll.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 12),
            attachmentScroll.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -12),
            composerScroll.topAnchor.constraint(equalTo: attachmentScroll.bottomAnchor),
            composerScroll.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 5),
            composerScroll.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -5),
            footer.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -8),
            footer.topAnchor.constraint(equalTo: composerScroll.bottomAnchor, constant: 8), footer.bottomAnchor.constraint(equalTo: composerCard.bottomAnchor, constant: -7),
            footer.heightAnchor.constraint(equalToConstant: 34)
        ])
        statusLabel.font = .systemFont(ofSize: 10); statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        let bottom = NSStackView(views: [composerCard, statusLabel]); bottom.orientation = .vertical
        bottom.alignment = .width; bottom.spacing = 5; bottom.edgeInsets = NSEdgeInsets(top: 5, left: 10, bottom: 8, right: 10)
        let stack = NSStackView(views: [top, divider(), prompts, divider(), messagesScroll, bottom])
        stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor), stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor)])
        for view in [top, prompts, messagesScroll, bottom] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        messagesScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false; addSubview(resizeHandle)
        NSLayoutConstraint.activate([resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor), resizeHandle.topAnchor.constraint(equalTo: topAnchor), resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor), resizeHandle.widthAnchor.constraint(equalToConstant: 5)])
        resizeHandle.onDrag = { [weak self] in self?.onResizeBy?($0) }; resizeHandle.onEnd = { [weak self] in self?.onResizeEnded?() }
        setPromptTemplates(NativePaperPrompts.templates, selectedPreset: .reading)
    }

    private func divider() -> NSView { let view = NSBox(); view.boxType = .separator; return view }
    func setPaperTitle(_ title: String) { paperTitle = title; if includePDF { updateAttachments() } }
    func setReferenceDirectory(_ directory: URL) { referenceDirectory = directory }
    func activate() { }
    func close() { modelPanel?.dismiss(); modelPanel = nil }
    func setModelTitle(_ title: String) {
        modelButton.attributedTitle = NSAttributedString(string: title.isEmpty ? "选择模型 ▾" : title + " ▾", attributes: [.font: NSFont.systemFont(ofSize: 13 * chatZoom), .foregroundColor: NativeHarnessStyle.primary])
    }
    func setAccessMode(_ mode: AIChatAccessMode) {
        accessMode = mode
        accessButton.attributedTitle = NSAttributedString(string: mode.title + " ▾", attributes: [.font: NSFont.systemFont(ofSize: 13 * chatZoom), .foregroundColor: NativeHarnessStyle.primary])
        accessButton.contentTintColor = NativeHarnessStyle.primary
    }
    private func previewChatZoomChange(_ delta: CGFloat, phase: NSEvent.Phase) {
        guard delta.isFinite else { return }
        if delta != 0 {
            let next = min(2.4, max(0.8, (previewChatZoom ?? chatZoom) * exp(delta * 0.004)))
            previewChatZoom = next
            let clip = messagesScroll.contentView
            let center = messagesStack.convert(NSPoint(x: clip.bounds.midX, y: clip.bounds.midY), from: clip)
            messagesScroll.setMagnification(next / chatZoom, centeredAt: center)
            // Reflow to the visible width while zooming and keep the left edge
            // pinned, so a magnified message cannot slide behind the gutter.
            messagesWidthConstraint?.constant = clip.bounds.width - clip.frame.width - 16
            clip.scroll(to: NSPoint(x: 0, y: clip.bounds.minY))
            messagesScroll.reflectScrolledClipView(clip)
            zoomButton.title = "\(Int((next * 100).rounded()))%"
            zoomButton.isHidden = abs(next - 1) < 0.005
            zoomWidth?.constant = zoomButton.isHidden ? 0 : 40
        }
        zoomCommitWork?.cancel()
        if phase == .ended || phase == .cancelled {
            commitPreviewChatZoom()
        } else {
            // Some mouse wheels do not report an end phase.
            let work = DispatchWorkItem { [weak self] in self?.commitPreviewChatZoom() }
            zoomCommitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
        }
    }

    private func commitPreviewChatZoom() {
        zoomCommitWork?.cancel()
        zoomCommitWork = nil
        guard let value = previewChatZoom else { return }
        previewChatZoom = nil
        let clip = messagesScroll.contentView
        let oldHeight = max(1, messagesStack.bounds.height)
        let centerFraction = min(1, max(0, messagesScroll.documentVisibleRect.midY / oldHeight))
        let wasAtBottom = messagesScroll.documentVisibleRect.maxY >= oldHeight - 2
        messagesScroll.setMagnification(1, centeredAt: .zero)
        messagesWidthConstraint?.constant = -16
        setChatZoom(value)
        messagesStack.layoutSubtreeIfNeeded()
        messagesScroll.layoutSubtreeIfNeeded()
        let height = messagesStack.bounds.height
        let maxY = max(0, height - clip.bounds.height)
        let y = wasAtBottom ? maxY : min(maxY, max(0, height * centerFraction - clip.bounds.height / 2))
        clip.scroll(to: NSPoint(x: 0, y: y))
        messagesScroll.reflectScrolledClipView(clip)
    }

    private func setChatZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        chatZoom = min(2.4, max(0.8, value))
        zoomButton.title = "\(Int((chatZoom * 100).rounded()))%"; zoomButton.isHidden = abs(chatZoom - 1) < 0.005
        zoomWidth?.constant = zoomButton.isHidden ? 0 : 40
        UserDefaults.standard.set(Double(chatZoom), forKey: "reader.nativePaperChatZoom")
        messages.values.forEach { $0.setFontSize(14 * chatZoom) }
        footerButtonSizes.forEach { $0.constant = 28 * chatZoom }
        for footer in assistantFooters.values {
            footer.spacing = 8 * chatZoom
            footer.arrangedSubviews.compactMap { $0 as? NSTextField }.forEach { $0.font = .systemFont(ofSize: 12 * chatZoom) }
            footer.arrangedSubviews.compactMap { $0 as? NSButton }.forEach { $0.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12 * chatZoom, weight: .regular) }
            if let row = footer.superview as? NSStackView, let rendered = row.arrangedSubviews.first(where: { $0 is AIChatRenderedContentView }) {
                row.setCustomSpacing(16 * chatZoom, after: rendered)
            }
        }
        for (id, constraint) in userBubbleWidths {
            constraint.constant = bubbleWidth(for: messageContents[id] ?? "", hasImages: userBubbleHasImages.contains(id))
        }
        updateComposerTypography(); resizeComposer(); setAccessMode(accessMode)
        if let route = modelRoutes.first(where: { $0.id == currentModelRouteID }) { setModelTitle(route.name) }
    }
    @objc private func resetChatZoom() { commitPreviewChatZoom(); setChatZoom(1) }
    func setWebConversationURL(_ value: String?) {
        let url = value.flatMap(URL.init(string:))
        webConversationURL = url.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        webButton.isEnabled = webConversationURL != nil
    }
    func setModelRoutes(_ routes: [HarnessModelImport.Route], selectedID: String?, reasoningEffort: String? = nil, customModel: String = "") {
        modelRoutes = routes; currentModelRouteID = selectedID; currentReasoningEffort = reasoningEffort
        customModelTitle = customModel.isEmpty ? "自定义模型" : customModel
        if let route = routes.first(where: { $0.id == selectedID }) { setModelTitle(route.name) }
        else if selectedID == Self.customRouteID { setModelTitle(customModelTitle) }
        else if selectedID != nil { setModelTitle("原模型不可用") }
    }
    func setReplyGestureZoomEnabled(_ enabled: Bool) { }
    func setConversations(_ conversations: [AIConversation], selectedID: String) {
        referenceConversations = conversations; referenceConversationID = selectedID
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        for conversation in conversations.sorted(by: { $0.createdAt < $1.createdAt }) {
            let button = NSButton(title: conversation.title, target: self, action: #selector(selectConversation(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(conversation.id); button.isBordered = false
            button.lineBreakMode = .byTruncatingTail
            button.font = .systemFont(ofSize: 12, weight: conversation.id == selectedID ? .semibold : .regular)
            button.isEnabled = !busy
            let close = NSButton(title: "×", target: self, action: #selector(deleteConversation(_:)))
            close.identifier = button.identifier; close.isBordered = false; close.isEnabled = !busy
            let row = NativePaperTab(views: [button, close]); row.orientation = .horizontal; row.spacing = 2
            row.selected = conversation.id == selectedID
            row.widthAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
            row.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
            row.setContentHuggingPriority(.required, for: .horizontal)
            tabs.addArrangedSubview(row)
        }
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal); tabs.addArrangedSubview(spacer)
    }
    func setPromptTemplates(_ values: [AIPromptTemplate], selectedPreset: AIPromptPreset) {
        templates = values.isEmpty ? NativePaperPrompts.templates : values; self.selectedPreset = selectedPreset
        presetPopup.removeAllItems(); for value in templates { presetPopup.addItem(withTitle: value.name); presetPopup.lastItem?.representedObject = value.id }
        if let index = templates.firstIndex(where: { $0.id == selectedPreset.rawValue }) { presetPopup.selectItem(at: index) }
    }
    func install(_ values: [AIChatMessage]) {
        messagesStack.arrangedSubviews.forEach { messagesStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        messages.removeAll(); messageRows.removeAll(); messageContents.removeAll(); userBubbleWidths.removeAll(); userBubbleHasImages.removeAll(); reasoningViews.removeAll(); reasoningButtons.removeAll(); messageActivityStarted.removeAll(); messageActivityText.removeAll(); assistantFooters.removeAll(); footerButtonSizes.removeAll(); feedbackButtons.removeAll(); values.forEach(append)
    }
    func append(_ message: AIChatMessage) {
        let rendered = AIChatRenderedContentView(); rendered.translatesAutoresizingMaskIntoConstraints = false; rendered.alignment = .width
        rendered.useHarnessTypography()
        rendered.setContent(message.content, renderMarkdown: message.role == .assistant)
        rendered.setFontSize(14 * chatZoom)
        rendered.setImageAttachments(message.imageAttachments)
        let row = NSStackView(); row.orientation = .vertical; row.alignment = .leading; row.spacing = 5
        for pdfName in ([message.pdfAttachmentName].compactMap { $0 } + (message.additionalPDFNames ?? [])) where !pdfName.isEmpty {
            let attachment = NSTextField(labelWithString: "▤  " + pdfName)
            attachment.font = .systemFont(ofSize: 11 * chatZoom, weight: .medium)
            attachment.textColor = .secondaryLabelColor
            attachment.lineBreakMode = .byTruncatingMiddle
            row.addArrangedSubview(attachment)
        }
        if message.role == .assistant {
            let toggle = NSButton(title: "▸ 思考过程", target: self, action: #selector(toggleReasoning(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(message.id); toggle.isBordered = false
            toggle.font = .systemFont(ofSize: 12 * chatZoom); toggle.contentTintColor = NativeHarnessStyle.secondary
            let reasoning = NSTextField(wrappingLabelWithString: message.reasoning ?? ""); reasoning.isSelectable = true
            reasoning.font = .systemFont(ofSize: 12); reasoning.textColor = .secondaryLabelColor; reasoning.isHidden = true
            toggle.isHidden = reasoning.stringValue.isEmpty
            row.addArrangedSubview(toggle); row.addArrangedSubview(reasoning)
            reasoning.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            reasoningViews[message.id] = reasoning; reasoningButtons[message.id] = toggle
            if let elapsed = message.elapsedSeconds {
                messageActivityText[message.id] = Self.completedActivity(elapsed)
                updateReasoningButton(id: message.id)
            }
        }
        if let tool = message.toolEvent {
            let toggle = NSButton(title: "▸ 工具 · " + tool.name, target: self, action: #selector(toggleReasoning(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(message.id); toggle.isBordered = false; toggle.font = .systemFont(ofSize: 11, weight: .medium)
            toggle.contentTintColor = .secondaryLabelColor
            let text = "输入\n" + tool.arguments + (tool.result.map { "\n\n结果\n" + $0 } ?? "")
            let detail = NSTextField(wrappingLabelWithString: text); detail.isSelectable = true; detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            detail.textColor = .secondaryLabelColor; detail.isHidden = true
            row.addArrangedSubview(toggle); row.addArrangedSubview(detail); detail.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            reasoningViews[message.id] = detail; reasoningButtons[message.id] = toggle
        }
        row.addArrangedSubview(rendered)
        if message.role == .assistant {
            let copy = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "复制回复") ?? NSImage(), target: self, action: #selector(copyMessage(_:)))
            copy.identifier = NSUserInterfaceItemIdentifier(message.id); copy.isBordered = false; copy.contentTintColor = .secondaryLabelColor
            func feedbackButton(_ symbol: String, label: String, value: Int) -> NSButton {
                let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: self, action: #selector(selectFeedback(_:)))
                button.identifier = NSUserInterfaceItemIdentifier(message.id); button.tag = value; button.isBordered = false; button.setButtonType(.toggle)
                button.contentTintColor = .secondaryLabelColor
                button.state = (message.feedback == (value == 1 ? "positive" : "negative")) ? .on : .off
                return button
            }
            let good = feedbackButton("hand.thumbsup", label: "好的回答", value: 1)
            let bad = feedbackButton("hand.thumbsdown", label: "有问题的回答", value: -1)
            feedbackButtons[message.id] = (good, bad)
            let branch = NSButton(image: NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "在新对话中分支") ?? NSImage(), target: self, action: #selector(branchMessage(_:)))
            branch.identifier = copy.identifier; branch.isBordered = false; branch.contentTintColor = .secondaryLabelColor
            let menu = NSMenu(); let delete = NSMenuItem(title: "删除消息", action: #selector(deleteMessageFromMenu(_:)), keyEquivalent: "")
            delete.target = self; delete.representedObject = message.id; menu.addItem(delete); row.menu = menu
            let formatter = DateFormatter(); formatter.dateFormat = "M月d日 HH:mm"
            let time = NSTextField(labelWithString: formatter.string(from: message.createdAt)); time.font = .systemFont(ofSize: 12 * chatZoom); time.textColor = NativeHarnessStyle.tertiary
            for button in [copy, good, bad, branch] {
                button.contentTintColor = NativeHarnessStyle.tertiary
                button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12 * chatZoom, weight: .regular)
                let width = button.widthAnchor.constraint(equalToConstant: 28 * chatZoom)
                let height = button.heightAnchor.constraint(equalToConstant: 28 * chatZoom)
                NSLayoutConstraint.activate([width, height]); footerButtonSizes.append(contentsOf: [width, height])
            }
            let footer = NSStackView(views: [copy, good, bad, branch, time]); footer.orientation = .horizontal; footer.spacing = 8 * chatZoom
            footer.isHidden = message.content.isEmpty; assistantFooters[message.id] = footer; row.addArrangedSubview(footer)
            row.setCustomSpacing(16 * chatZoom, after: rendered)
        }
        row.wantsLayer = true; row.layer?.cornerRadius = 20
        if message.role == .user {
            effectiveAppearance.performAsCurrentDrawingAppearance { row.layer?.backgroundColor = NativeHarnessStyle.userBubble.cgColor }
            row.edgeInsets = NSEdgeInsets(top: 10 * chatZoom, left: 16 * chatZoom, bottom: 10 * chatZoom, right: 16 * chatZoom)
        }
        messagesStack.addArrangedSubview(row)
        if message.role != .user {
            row.widthAnchor.constraint(equalTo: messagesStack.widthAnchor, constant: -32).isActive = true
            rendered.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
            rendered.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        } else {
            row.widthAnchor.constraint(lessThanOrEqualTo: messagesStack.widthAnchor, multiplier: 0.85).isActive = true
            row.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let hasAttachments = !message.imageAttachments.isEmpty || message.pdfAttachmentName != nil || !(message.additionalPDFNames ?? []).isEmpty
            let width = row.widthAnchor.constraint(equalToConstant: bubbleWidth(for: message.content, hasImages: hasAttachments))
            width.priority = .defaultHigh; width.isActive = true; userBubbleWidths[message.id] = width
            if hasAttachments { userBubbleHasImages.insert(message.id) }
        }
        messages[message.id] = rendered; messageRows[message.id] = row; messageContents[message.id] = message.content
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
    }
    func updateMessage(id: String, content: String, renderMarkdown: Bool = false) { messageContents[id] = content; messages[id]?.setContent(content, renderMarkdown: renderMarkdown); assistantFooters[id]?.isHidden = content.isEmpty }
    func updateReasoning(id: String, content: String) { reasoningViews[id]?.stringValue = content; updateReasoningButton(id: id) }
    func updateToolEvent(id: String, event: AIChatToolEvent) {
        reasoningViews[id]?.stringValue = "输入\n" + event.arguments + (event.result.map { "\n\n结果\n" + $0 } ?? "")
        reasoningButtons[id]?.title = (reasoningViews[id]?.isHidden == false ? "▾" : "▸") + " 工具 · " + event.name + (event.isError ? "（失败）" : "")
    }
    func setToolActivity(_ name: String) { statusLabel.stringValue = "正在调用 \(name)…" }
    private func bubbleWidth(for text: String, hasImages: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14 * chatZoom)
        let widest = text.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(hasImages ? 180 : 44, ceil(widest) + 32)
    }
    func removeMessage(id: String) { if let row = messageRows.removeValue(forKey: id) { messagesStack.removeArrangedSubview(row); row.removeFromSuperview() }; messages.removeValue(forKey: id); messageContents.removeValue(forKey: id); userBubbleWidths.removeValue(forKey: id); userBubbleHasImages.remove(id); reasoningViews.removeValue(forKey: id); reasoningButtons.removeValue(forKey: id); messageActivityStarted.removeValue(forKey: id); messageActivityText.removeValue(forKey: id) }
    func setActivity(_ phase: AIChatActivityPhase, detail: String) {
        switch phase {
        case .ready, .completed: statusLabel.stringValue = ""
        case .loading: statusLabel.stringValue = "正在打开对话…"
        case .preparing: statusLabel.stringValue = "正在准备…"
        case .uploading: statusLabel.stringValue = "正在上传 PDF…"
        case .waiting: statusLabel.stringValue = "等待模型回复…"
        case .thinking: statusLabel.stringValue = "思考中…"
        case .answering: statusLabel.stringValue = "正在回复…"
        case .stopped: statusLabel.stringValue = "已停止"
        case .failed: statusLabel.stringValue = detail
        }
    }
    private static func completedActivity(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return seconds >= 60 ? "已完成，用时 \(seconds / 60)分\(seconds % 60)秒" : "已完成，用时 \(seconds)秒"
    }
    private func updateReasoningButton(id: String) {
        guard let button = reasoningButtons[id], let view = reasoningViews[id] else { return }
        let hasReasoning = !view.stringValue.isEmpty
        let text = messageActivityText[id] ?? "思考过程"
        button.isHidden = !hasReasoning && messageActivityText[id] == nil
        button.isEnabled = true
        button.title = hasReasoning ? text + (view.isHidden ? "  ⌄" : "  ⌃") : text
    }
    func setMessageActivity(id: String, phase: AIChatActivityPhase, identity: String) {
        switch phase {
        case .preparing: messageActivityStarted[id] = Date(); messageActivityText[id] = "正在准备…"
        case .uploading: messageActivityText[id] = "正在上传…"
        case .waiting: messageActivityText[id] = "等待模型回复…"
        case .thinking: messageActivityText[id] = "思考中…"
        case .answering: messageActivityText[id] = "正在回复…"
        case .completed: messageActivityText[id] = Self.completedActivity(Date().timeIntervalSince(messageActivityStarted[id] ?? Date()))
        case .stopped: messageActivityText[id] = "已停止"
        case .failed: messageActivityText[id] = "请求失败"
        case .ready, .loading: break
        }
        updateReasoningButton(id: id)
    }
    func setStreaming(_ streaming: Bool) {
        busy = streaming; updateSendButton(); addButton.isEnabled = !streaming
        accessButton.isEnabled = !streaming
        for row in tabs.arrangedSubviews { for button in row.subviews.compactMap({ $0 as? NSButton }) { button.isEnabled = !streaming } }
        webButton.isEnabled = !streaming
    }
    func setQueuedSubmissions(_ submissions: [AIChatSubmission]) {
        if !submissions.isEmpty { statusLabel.stringValue = "排队中：\(submissions.count)" }
        else if statusLabel.stringValue.hasPrefix("排队中：") { statusLabel.stringValue = "" }
    }
    func prefill(_ text: String, attachments: [AIChatImageAttachment] = [], includeCurrentPDF: Bool = false, additionalPDFPaths: [String] = [], references: [AIChatDraftReference] = []) {
        guard composer.string.isEmpty && self.attachments.isEmpty && !includePDF && self.additionalPDFPaths.isEmpty else { return }
        composer.string = text; self.attachments = attachments; includePDF = includeCurrentPDF; self.additionalPDFPaths = additionalPDFPaths; draftReferences = references; updateAttachments(); draftChanged()
    }
    func restoreDraft(_ text: String, attachments: [AIChatImageAttachment], includePDF: Bool, additionalPDFPaths: [String] = [], references: [AIChatDraftReference] = [], command: AIChatDraftCommand? = nil) {
        referenceSearchTask?.cancel(); composerMenuPanel?.dismiss(); dismissedSlashLocation = nil; dismissedReferenceLocation = nil
        suppressDraftCallback = true; composer.string = text; self.attachments = attachments; self.includePDF = includePDF; self.additionalPDFPaths = additionalPDFPaths; draftReferences = references; draftCommand = command; updateAttachments(); refreshReferenceStyling(); resizeComposer(); updateSendButton(); suppressDraftCallback = false
    }
    func insertPrompt(_ text: String) {
        guard !text.isEmpty else { return }
        let prefix = text + (composer.string.isEmpty ? "" : "\n\n")
        draftReferences = draftReferences.map { value in var result = value; result.offset += (prefix as NSString).length; return result }
        draftCommand = nil; composer.string = prefix + composer.string; draftChanged(); focusComposer()
    }
    func insertQuote(_ text: String) {
        guard !text.isEmpty else { return }
        draftReferences = draftReferences.map { value in var result = value; result.offset += (text as NSString).length; return result }
        draftCommand = nil; composer.string = text + composer.string; draftChanged(); focusComposer()
    }
    func focusComposer() { window?.makeFirstResponder(composer) }
    func clearComposer() { referenceSearchTask?.cancel(); composerMenuPanel?.dismiss(); dismissedSlashLocation = nil; dismissedReferenceLocation = nil; composer.string = ""; attachments = []; includePDF = false; additionalPDFPaths = []; draftReferences = []; draftCommand = nil; updateAttachments(); draftChanged() }
    func presentHistoryMenu(_ menu: NSMenu) { menu.popUp(positioning: nil, at: .zero, in: recordButton) }
    func textDidChange(_ notification: Notification) {
        if let command = draftCommand, !composer.string.hasPrefix(command.token.trimmingCharacters(in: .whitespacesAndNewlines)) { draftCommand = nil }
        composer.needsDisplay = true; resizeComposer(); draftChanged(); updateSlashMenu(); updateReferenceMenu()
    }
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let insertedLength = ((replacementString ?? "") as NSString).length
        let delta = insertedLength - affectedCharRange.length
        draftReferences = draftReferences.compactMap { original in
            var reference = original
            let end = reference.offset + reference.length
            if affectedCharRange.location + affectedCharRange.length <= reference.offset {
                reference.offset += delta; return reference
            }
            if affectedCharRange.location >= end { return reference }
            // An edited reference becomes ordinary text, so it cannot point to the wrong source.
            return nil
        }
        if affectedCharRange.location == 0 { draftCommand = nil }
        return true
    }
    private func updateComposerTypography() {
        let font = NSFont.systemFont(ofSize: 14 * chatZoom)
        let style = NSMutableParagraphStyle(); style.minimumLineHeight = 24 * chatZoom
        composer.font = font; composer.defaultParagraphStyle = style
        composer.typingAttributes = [.font: font, .paragraphStyle: style, .foregroundColor: NativeHarnessStyle.primary]
        composer.placeholderFont = font
    }
    private func resizeComposer() {
        guard let container = composer.textContainer, let layout = composer.layoutManager else { return }
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + composer.textContainerInset.height * 2
        composerHeight?.constant = min(336 * chatZoom, max(36 * chatZoom, ceil(height)))
    }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if (slashMenuOpen || referenceMenuOpen), let event = NSApp.currentEvent, let menu = composerMenuPanel?.contentViewController as? NativeComposerMenu {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                if slashMenuOpen { dismissedSlashLocation = slashTrigger()?.range.location }
                if referenceMenuOpen { dismissedReferenceLocation = referenceTrigger()?.range.location }
                composerMenuPanel?.dismiss(); return true
            }
            if !(event.modifierFlags.contains(.shift) && (event.keyCode == 36 || event.keyCode == 76)), menu.handleKey(event) { return true }
        }
        if selector == #selector(NSResponder.insertNewline(_:)),
           !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) {
            submitDraft(); return true
        }
        return false
    }
    private func refreshReferenceStyling() {
        guard let layout = composer.layoutManager else { return }
        let text = composer.string as NSString, all = NSRange(location: 0, length: text.length)
        layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
        for reference in draftReferences where reference.offset >= 0 && reference.length > 0 && reference.offset <= text.length && reference.length <= text.length - reference.offset {
            let range = NSRange(location: reference.offset, length: reference.length)
            guard text.substring(with: range) == reference.clipboardText else { continue }
            layout.addTemporaryAttributes([.backgroundColor: NativeHarnessStyle.code, .foregroundColor: NativeHarnessStyle.link], forCharacterRange: range)
        }
    }
    private func draftChanged() { refreshReferenceStyling(); resizeComposer(); updateSendButton(); if !suppressDraftCallback { onDraftChange?(composer.string, attachments, includePDF, additionalPDFPaths, draftReferences, draftCommand) } }
    private func updateSendButton() {
        let hasContent = !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || includePDF || !additionalPDFPaths.isEmpty
        let showsStop = busy && !hasContent
        sendButton.isEnabled = busy || hasContent
        sendButton.attributedTitle = NSAttributedString(string: showsStop ? "■" : "↑", attributes: [.font: NSFont.systemFont(ofSize: showsStop ? 13 : 19, weight: .medium), .foregroundColor: hasContent || busy ? NativeHarnessStyle.primary : NativeHarnessStyle.caption])
    }
    private func updateAttachments() {
        attachmentStack.arrangedSubviews.forEach { attachmentStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        if includePDF {
            let name = NSTextField(labelWithString: "▤  " + paperTitle); name.font = .systemFont(ofSize: 12)
            name.lineBreakMode = .byTruncatingMiddle; name.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            let remove = NSButton(title: "×", target: self, action: #selector(togglePDF)); remove.isBordered = false; remove.setAccessibilityLabel("移除当前 PDF")
            let chip = NSStackView(views: [name, remove]); chip.orientation = .horizontal; chip.spacing = 5
            chip.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 5)
            chip.wantsLayer = true; chip.layer?.cornerRadius = 6; chip.layer?.borderWidth = 0.5; chip.layer?.borderColor = NSColor.separatorColor.cgColor
            attachmentStack.addArrangedSubview(chip)
        }
        for path in additionalPDFPaths {
            let name = NSTextField(labelWithString: "▤  " + URL(fileURLWithPath: path).lastPathComponent); name.font = .systemFont(ofSize: 12)
            name.lineBreakMode = .byTruncatingMiddle; name.widthAnchor.constraint(lessThanOrEqualToConstant: 180).isActive = true
            let remove = NSButton(title: "×", target: self, action: #selector(removeAdditionalPDF(_:))); remove.isBordered = false; remove.setAccessibilityLabel("移除 PDF")
            remove.identifier = NSUserInterfaceItemIdentifier(path)
            let chip = NSStackView(views: [name, remove]); chip.orientation = .horizontal; chip.spacing = 5
            chip.edgeInsets = NSEdgeInsets(top: 7, left: 8, bottom: 7, right: 5)
            chip.wantsLayer = true; chip.layer?.cornerRadius = 6; chip.layer?.borderWidth = 0.5; chip.layer?.borderColor = NSColor.separatorColor.cgColor
            attachmentStack.addArrangedSubview(chip)
        }
        for image in attachments {
            let chip = AIChatImageChip(attachment: image, removable: true, removeTitle: "移除图片", showsToolTips: false)
            chip.onRemove = { [weak self] in
                self?.attachments.removeAll { $0.id == image.id }; self?.updateAttachments(); self?.draftChanged()
            }
            attachmentStack.addArrangedSubview(chip)
        }
        let hasAttachments = includePDF || !attachments.isEmpty || !additionalPDFPaths.isEmpty
        attachmentScroll.isHidden = !hasAttachments; attachmentHeight?.constant = hasAttachments ? 62 : 0
        attachmentStack.layoutSubtreeIfNeeded()
        let size = attachmentStack.fittingSize
        attachmentStack.frame = NSRect(x: 0, y: 0, width: max(size.width, attachmentScroll.contentSize.width), height: 62)
    }
    private func scrollToBottom() { let clip = messagesScroll.contentView; let h = messagesStack.frame.height; clip.scroll(to: NSPoint(x: 0, y: max(0, h - clip.bounds.height))); messagesScroll.reflectScrolledClipView(clip) }
    @objc private func addConversation() { onNewConversation?() }
    @objc private func selectConversation(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onSelectConversation?(id) } }
    @objc private func deleteConversation(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onDeleteConversation?(id) } }
    @objc private func copyMessage(_ sender: NSButton) { guard let id = sender.identifier?.rawValue, let content = messageContents[id] else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
    @objc private func toggleReasoning(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let view = reasoningViews[id] else { return }
        guard !view.stringValue.isEmpty else { return }
        view.isHidden.toggle()
        if messageActivityText[id] != nil || assistantFooters[id] != nil { updateReasoningButton(id: id); return }
        let base = sender.title.dropFirst(2)
        sender.title = (view.isHidden ? "▸ " : "▾ ") + base
    }
    @objc private func deleteMessageFromMenu(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onDeleteMessage?(id) } }
    @objc private func selectFeedback(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let pair = feedbackButtons[id] else { return }
        let value: String? = sender.state == .on ? (sender.tag == 1 ? "positive" : "negative") : nil
        pair.0.state = value == "positive" ? .on : .off; pair.1.state = value == "negative" ? .on : .off
        onFeedback?(id, value)
    }
    @objc private func branchMessage(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onBranchMessage?(id) } }
    @objc private func changePreset() { guard let id = presetPopup.selectedItem?.representedObject as? String else { return }; selectedPreset = AIPromptPreset(rawValue: id); onPresetChange?(selectedPreset) }
    @objc private func applyPreset() { onApplyPrompt?(selectedPreset) }
    @objc private func revealHistory() { onRevealCurrentHistory?() }
    @objc private func configureAccess() {
        let menu = NSMenu()
        for mode in AIChatAccessMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectAccess(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = mode.rawValue; item.state = mode == accessMode ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: .zero, in: accessButton)
    }
    @objc private func selectAccess(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let mode = AIChatAccessMode(rawValue: value), mode != accessMode else { return }
        if mode == .fullAccess {
            let alert = NSAlert(); alert.messageText = "确认启用完全权限？"
            alert.informativeText = "启用后，助手可以执行命令、修改文件并访问工作区以外的内容。"
            alert.addButton(withTitle: "启用完全权限"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        setAccessMode(mode); onSelectAccessMode?(mode)
    }
    @objc private func openWebConversation() { if let webConversationURL { NSWorkspace.shared.open(webConversationURL) } }
    @objc private func configureModel() {
        guard !modelRoutes.isEmpty else { onConfigure?(); return }
        if modelPanel != nil { modelPanel?.dismiss(); modelPanel = nil; return }
        let controller = NativeModelPopover(routes: modelRoutes, selectedID: currentModelRouteID, effort: currentReasoningEffort,
            customTitle: customModelTitle, chooseModel: { [weak self] in self?.onSelectModel?($0); self?.focusComposer() },
            chooseEffort: { [weak self] in self?.onSelectReasoning?($0); self?.focusComposer() }, dismiss: { [weak self] in self?.modelPanel?.dismiss() })
        guard let parent = window else { return }
        let panel = NativeModelPanel(controller: controller, parent: parent, anchor: modelButton)
        panel.onDismiss = { [weak self] in self?.modelPanel = nil }
        modelPanel = panel; panel.present()
    }
    @objc private func sendOrStop() {
        let hasContent = !composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || includePDF || !additionalPDFPaths.isEmpty
        if busy && !hasContent { onCancel?(); return }
        submitDraft()
    }
    private func submitDraft() { let text = composer.string; guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || includePDF || !additionalPDFPaths.isEmpty else { return }; onSend?(text, attachments, selectedPreset, includePDF, additionalPDFPaths, draftReferences) }
    @objc private func attach() { presentComposerMenu(query: nil) }
    private func slashTrigger() -> (range: NSRange, query: String)? {
        let selection = composer.selectedRange()
        let value = composer.string as NSString
        guard selection.length == 0, selection.location <= value.length else { return nil }
        let prefix = value.substring(to: selection.location)
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)/([\\p{L}\\p{N}_-]*)$"),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { return nil }
        let query = (prefix as NSString).substring(with: match.range(at: 1))
        return (NSRange(location: match.range(at: 1).location - 1, length: match.range(at: 1).length + 1), query)
    }
    private func updateSlashMenu() {
        guard let trigger = slashTrigger() else {
            dismissedSlashLocation = nil
            if slashMenuOpen { composerMenuPanel?.dismiss() }
            return
        }
        guard dismissedSlashLocation != trigger.range.location else { return }
        if slashMenuOpen { composerMenuPanel?.dismiss() }
        presentComposerMenu(query: trigger.query)
    }
    private func consumeSlashTrigger() {
        guard let trigger = slashTrigger(), composer.shouldChangeText(in: trigger.range, replacementString: "") else { return }
        composer.textStorage?.replaceCharacters(in: trigger.range, with: "")
        composer.setSelectedRange(NSRange(location: trigger.range.location, length: 0))
        composer.didChangeText()
    }
    private func referenceTrigger() -> (range: NSRange, query: String)? {
        let selection = composer.selectedRange(), value = composer.string as NSString
        guard selection.length == 0, selection.location <= value.length else { return nil }
        let prefix = value.substring(to: selection.location)
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)@([^\\s@]*)$"),
              let match = regex.firstMatch(in: prefix, range: NSRange(location: 0, length: (prefix as NSString).length)) else { return nil }
        let query = (prefix as NSString).substring(with: match.range(at: 1))
        return (NSRange(location: match.range(at: 1).location - 1, length: match.range(at: 1).length + 1), query)
    }
    private nonisolated static func referenceFiles(in directory: URL, query: String) -> [String] {
        guard !query.contains("/"), let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return files.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  !url.lastPathComponent.contains("\""), !url.lastPathComponent.contains("\n") else { return false }
            let type = UTType(filenameExtension: url.pathExtension)
            return (url.pathExtension.lowercased() == "pdf" || type?.conforms(to: .plainText) == true) && (query.isEmpty || url.lastPathComponent.localizedCaseInsensitiveContains(query))
        }.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }.prefix(5).map { $0 }
    }
    private func updateReferenceMenu() {
        referenceSearchTask?.cancel()
        guard let trigger = referenceTrigger(), let directory = referenceDirectory else {
            dismissedReferenceLocation = nil
            if referenceMenuOpen { composerMenuPanel?.dismiss() }
            return
        }
        guard dismissedReferenceLocation != trigger.range.location else { return }
        let conversations = referenceConversations.filter { $0.id != referenceConversationID && (trigger.query.isEmpty || $0.title.localizedCaseInsensitiveContains(trigger.query)) }.prefix(5)
        referenceSearchTask = Task { [weak self] in
            let files = await Task.detached { Self.referenceFiles(in: directory, query: trigger.query) }.value
            guard !Task.isCancelled, let self, self.referenceTrigger()?.range == trigger.range, self.referenceTrigger()?.query == trigger.query else { return }
            if self.referenceMenuOpen { self.composerMenuPanel?.dismiss() }
            guard self.composerMenuPanel == nil, let parent = self.window else { return }
            let fileItems: [NativeComposerMenu.Item] = files.map { name in
                let mention = name.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? "@" + name : "@\"" + name + "\""
                return .init(title: name, token: "", detail: "文件", symbol: "doc", action: { [weak self] in
                    self?.insertReference(mention: mention, label: name, appearance: "file")
                })
            }
            let sessionItems: [NativeComposerMenu.Item] = conversations.map { conversation in
                let encoded = ((try? JSONEncoder().encode(conversation.id)) ?? Data()).base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                let label = conversation.title.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "]", with: "\\]")
                let mention = "@[\(label)](dsh-session:\(encoded))"
                return .init(title: conversation.title, token: "", detail: "对话", symbol: "bubble.left", action: { [weak self] in
                    self?.insertReference(mention: mention, label: conversation.title, appearance: "session", display: "@" + conversation.title)
                })
            }
            guard !fileItems.isEmpty || !sessionItems.isEmpty else { return }
            let menu = NativeComposerMenu(width: max(280, self.composerCard.bounds.width), groups: [("文件", fileItems), ("对话", sessionItems)], dismiss: { [weak self] in self?.composerMenuPanel?.dismiss() })
            let panel = NativeModelPanel(controller: menu, parent: parent, anchor: self.composerCard)
            panel.onDismiss = { [weak self] in self?.composerMenuPanel = nil; self?.slashMenuOpen = false; self?.referenceMenuOpen = false }
            self.composerMenuPanel = panel; self.referenceMenuOpen = true; panel.present(activate: false)
        }
    }
    private func insertReference(mention: String, label: String, appearance: String, display: String? = nil) {
        guard let trigger = referenceTrigger() else { return }
        let visible = display ?? mention
        let text = visible + " "
        composer.insertText(text, replacementRange: trigger.range)
        draftReferences.append(AIChatDraftReference(source: "reference", ref: mention, offset: trigger.range.location,
            length: (visible as NSString).length, label: label, appearance: appearance, clipboardText: visible))
        draftReferences.sort { $0.offset < $1.offset }
        draftChanged(); focusComposer()
    }
    private func presentComposerMenu(query: String?) {
        if composerMenuPanel != nil { composerMenuPanel?.dismiss(); return }
        guard let parent = window else { return }
        let fromSlash = query != nil
        let prepare: (@escaping @MainActor () -> Void) -> @MainActor () -> Void = { [weak self] action in
            { [weak self] in if fromSlash { self?.consumeSlashTrigger() }; action() }
        }
        var add: [NativeComposerMenu.Item] = [
            .init(title: "文件", token: "file", detail: "添加图片或 PDF", symbol: "paperclip", action: prepare { [weak self] in self?.addFile(); self?.focusComposer() }),
            .init(title: includePDF ? "移除当前 PDF" : "当前 PDF", token: "", detail: "", symbol: "doc", action: prepare { [weak self] in self?.togglePDF(); self?.focusComposer() })
        ]
        var commands: [NativeComposerMenu.Item] = [
            .init(title: "权限", token: "permission", detail: "切换权限预设", symbol: "exclamationmark.shield", action: prepare { [weak self] in self?.configureAccess() }),
            .init(title: "模型", token: "model", detail: "选择本会话使用的模型", symbol: "server.rack", action: prepare { [weak self] in self?.configureModel() })
        ]
        if let query {
            let needle = query.lowercased()
            add = add.filter { !$0.token.isEmpty && (needle.isEmpty || $0.token.lowercased().contains(needle) || $0.title.lowercased().contains(needle)) }
            commands = commands.filter { needle.isEmpty || $0.token.lowercased().contains(needle) || $0.title.lowercased().contains(needle) }
            guard !add.isEmpty || !commands.isEmpty else { return }
        }
        let controller = NativeComposerMenu(width: max(280, composerCard.bounds.width), groups: [("添加", add), ("指令", commands)], dismiss: { [weak self] in self?.composerMenuPanel?.dismiss() })
        let panel = NativeModelPanel(controller: controller, parent: parent, anchor: composerCard)
        panel.onDismiss = { [weak self] in self?.composerMenuPanel = nil; self?.slashMenuOpen = false; self?.referenceMenuOpen = false }
        composerMenuPanel = panel; slashMenuOpen = fromSlash; panel.present(activate: !fromSlash)
    }
    @objc private func togglePDF() {
        guard includePDF || additionalPDFPaths.count < 4 else { showAttachmentError("最多可附加 4 个 PDF。"); return }
        includePDF.toggle(); updateAttachments(); draftChanged()
    }
    @objc private func removeAdditionalPDF(_ sender: NSButton) {
        additionalPDFPaths.removeAll { $0 == sender.identifier?.rawValue }; updateAttachments(); draftChanged()
    }
    @objc private func removeImages() { attachments = []; updateAttachments(); draftChanged() }
    private func showAttachmentError(_ text: String) { let alert = NSAlert(); alert.messageText = text; alert.runModal() }
    @objc private func addFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .pdf]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var problems: [String] = []
        for url in panel.urls {
            if url.pathExtension.lowercased() == "pdf" {
                let path = url.standardizedFileURL.path
                if additionalPDFPaths.contains(path) { continue }
                guard additionalPDFPaths.count + (includePDF ? 1 : 0) < 4 else { problems.append("最多可附加 4 个 PDF"); continue }
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 100 * 1_024 * 1_024,
                      let handle = try? FileHandle(forReadingFrom: url) else { problems.append("无法读取或文件超过 100 MB：\(url.lastPathComponent)"); continue }
                let header = try? handle.read(upToCount: 5); try? handle.close()
                guard header == Data("%PDF-".utf8) else { problems.append("不是有效的 PDF：\(url.lastPathComponent)"); continue }
                additionalPDFPaths.append(path)
            } else {
                guard attachments.count < 4 else { problems.append("最多可附加 4 张图片"); continue }
                guard let data = try? Data(contentsOf: url), let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else { problems.append("无法读取图片：\(url.lastPathComponent)"); continue }
                attachments.append(AIChatImageAttachment(fileName: url.lastPathComponent, mimeType: type, data: data))
            }
        }
        updateAttachments(); draftChanged()
        if !problems.isEmpty { showAttachmentError(Array(Set(problems)).sorted().joined(separator: "\n")) }
    }
}

private final class NativePaperTab: NSStackView {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selected else { return }
        NSColor.labelColor.withAlphaComponent(0.04).setFill(); bounds.fill()
        NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1.5).fill()
    }
}

private final class NativePaperComposer: NSTextView {
    var onImages: (([AIChatImageAttachment]) -> Void)?
    var placeholderFont = NSFont.systemFont(ofSize: 14)

    override func paste(_ sender: Any?) {
        let images = Self.readImages(NSPasteboard.general)
        if images.isEmpty { super.paste(sender) } else { onImages?(images) }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let images = Self.readImages(sender.draggingPasteboard)
        guard !images.isEmpty else { return super.performDragOperation(sender) }
        onImages?(images)
        return true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.availableType(from: [.fileURL, .png, .tiff]) != nil { return .copy }
        return super.draggingEntered(sender)
    }

    fileprivate static func readImages(_ pasteboard: NSPasteboard) -> [AIChatImageAttachment] {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let images = urls.compactMap { url -> AIChatImageAttachment? in
            guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                  let mime = type.preferredMIMEType, let data = try? Data(contentsOf: url) else { return nil }
            return AIChatImageAttachment(fileName: url.lastPathComponent, mimeType: mime, data: data)
        }
        if !images.isEmpty { return images }
        if let data = pasteboard.data(forType: .png) {
            return [AIChatImageAttachment(fileName: "粘贴的图片.png", mimeType: "image/png", data: data)]
        }
        if let data = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: data),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return [AIChatImageAttachment(fileName: "粘贴的图片.png", mimeType: "image/png", data: png)]
        }
        return []
    }

    override var string: String { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: placeholderFont, .foregroundColor: NativeHarnessStyle.caption, .paragraphStyle: paragraph]
        let placeholder = "发消息或创建任务, / 调用指令, @ 文件或对话" as NSString
        placeholder.draw(in: NSRect(x: textContainerInset.width + 5, y: textContainerInset.height, width: max(0, bounds.width - 28), height: 24), withAttributes: attributes)
    }
}

private final class NativePaperMessageStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// Matches the reading-mode controls without adding hover tooltips.
private final class NativePaperToolbarButton: NSButton {
    var drawsOutline = false { didSet { needsDisplay = true } }
    private var hovered = false
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        if hovered { NSColor.labelColor.withAlphaComponent(isEnabled ? 0.07 : 0.035).setFill(); path.fill() }
        if drawsOutline { NSColor.separatorColor.withAlphaComponent(0.65).setStroke(); path.lineWidth = 0.5; path.stroke() }
        super.draw(dirtyRect)
    }
}

private final class NativePaperPresetPopup: NSPopUpButton {
    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let font = self.font ?? .systemFont(ofSize: 11)
        let text = selectedItem?.title ?? ""
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor,
            .paragraphStyle: paragraph
        ]
        let textHeight = ceil(font.ascender - font.descender + font.leading)
        (text as NSString).draw(in: NSRect(x: 8, y: (bounds.height - textHeight) / 2, width: max(0, bounds.width - 30), height: textHeight), withAttributes: attributes)
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let symbol = image.withSymbolConfiguration(.init(pointSize: 10, weight: .regular)) ?? image
            symbol.draw(in: NSRect(x: bounds.width - 18, y: (bounds.height - 11) / 2, width: 10, height: 11))
        }
    }
}

private final class NativePaperChatScrollView: NSScrollView {
    var onZoom: ((CGFloat, NSEvent.Phase) -> Void)?
    override func magnify(with event: NSEvent) { onZoom?(event.magnification * 250, event.phase) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { onZoom?(event.scrollingDeltaY, event.phase); return }
        super.scrollWheel(with: event)
    }
}

private final class NativePaperChatResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?; var onEnd: (() -> Void)?; private var previous: CGFloat?
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func mouseDown(with event: NSEvent) { previous = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) { let x = event.locationInWindow.x; if let previous { onDrag?(x - previous) }; previous = x }
    override func mouseUp(with event: NSEvent) { previous = nil; onEnd?() }
}
