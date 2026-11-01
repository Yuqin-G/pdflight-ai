import AppKit
import PDFlightAI
import UniformTypeIdentifiers

/// Native paper conversation. The conversation engine, history, and draft
/// persistence are owned by PDFlight; no WebKit view is used here.
@MainActor
final class NativePaperChatSidebar: NSView, NSTextViewDelegate {
    static let customRouteID = "__pdflight_custom_model__"
    static func selfCheck() throws {
        let sidebar = NativePaperChatSidebar(frame: NSRect(x: 0, y: 0, width: 440, height: 700))
        var savedText = ""; var savedImages: [AIChatImageAttachment] = []; var savedPDF = false
        sidebar.onDraftChange = { text, images, pdf in savedText = text; savedImages = images; savedPDF = pdf }
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
        sidebar.togglePDF()
        guard savedPDF else { throw NSError(domain: "NativePaperChatSelfCheck", code: 4, userInfo: [NSLocalizedDescriptionKey: "附加 PDF 的选择必须进入草稿"]) }
        var submitted = false
        sidebar.onSend = { text, images, _, pdf in submitted = text == savedText && images == savedImages && pdf }
        sidebar.sendOrStop()
        guard submitted else { throw NSError(domain: "NativePaperChatSelfCheck", code: 3, userInfo: [NSLocalizedDescriptionKey: "发送必须包含草稿和附件"]) }
        let pdfMessage = AIChatMessage(role: .user, content: "阅读附件", pdfAttachmentName: "paper.pdf")
        sidebar.append(pdfMessage)
        let row = sidebar.messageRows[pdfMessage.id] as? NSStackView
        guard row?.arrangedSubviews.contains(where: { ($0 as? NSTextField)?.stringValue.contains("paper.pdf") == true }) == true else {
            throw NSError(domain: "NativePaperChatSelfCheck", code: 5, userInfo: [NSLocalizedDescriptionKey: "历史消息必须显示 PDF 附件"])
        }
    }
    var onSend: ((String, [AIChatImageAttachment], AIPromptPreset, Bool) -> Void)?
    var onConfigure: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onSelectConversation: ((String) -> Void)?
    var onDeleteConversation: ((String) -> Void)?
    var onDeleteMessage: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onResizeBy: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onDraftChange: ((String, [AIChatImageAttachment], Bool) -> Void)?
    var onRevealCurrentHistory: (() -> Void)?
    var onPresetChange: ((AIPromptPreset) -> Void)?
    var onApplyPrompt: ((AIPromptPreset) -> Void)?
    var onSelectModel: ((String) -> Void)?
    var onSelectReasoning: ((String?) -> Void)?

    private let tabs = NSStackView()
    private let tabScroll = NSScrollView()
    private let addButton = NSButton(title: "+ 新建对话", target: nil, action: nil)
    private let presetPopup = NSPopUpButton()
    private let applyButton = NSButton(title: "填入输入框", target: nil, action: nil)
    private let recordButton = NSButton(title: "▤", target: nil, action: nil)
    private let webButton = NSButton(title: "↗", target: nil, action: nil)
    private let messagesScroll = NativePaperChatScrollView()
    private let messagesStack = NativePaperMessageStack()
    private let composerCard = NSView()
    private let composerScroll = NSScrollView()
    private let composer = NativePaperComposer()
    private let attachButton = NSButton(title: "+", target: nil, action: nil)
    private let attachmentLabel = NSTextField(labelWithString: "")
    private let modelButton = NSButton(title: "选择模型 ▾", target: nil, action: nil)
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
    private var attachments: [AIChatImageAttachment] = []
    private var includePDF = false
    private var templates = NativePaperPrompts.templates
    private var selectedPreset = AIPromptPreset.reading
    private var busy = false
    private var suppressDraftCallback = false
    private var modelRoutes: [HarnessModelImport.Route] = []
    private var currentModelRouteID: String?
    private var currentReasoningEffort: String?
    private var customModelTitle = "自定义模型"
    private var webConversationURL: URL?
    private var chatZoom: CGFloat = {
        let value = UserDefaults.standard.double(forKey: "reader.nativePaperChatZoom")
        return value >= 0.8 && value <= 2.4 ? value : 1
    }()
    private static let background = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 30/255, green: 28/255, blue: 26/255, alpha: 1)
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
        let top = NSView()
        tabScroll.translatesAutoresizingMaskIntoConstraints = false; addButton.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(tabScroll); top.addSubview(addButton)
        NSLayoutConstraint.activate([
            tabScroll.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 8),
            tabScroll.topAnchor.constraint(equalTo: top.topAnchor), tabScroll.bottomAnchor.constraint(equalTo: top.bottomAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: addButton.leadingAnchor, constant: -6),
            addButton.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -12), addButton.centerYAnchor.constraint(equalTo: top.centerYAnchor)
        ])
        top.heightAnchor.constraint(equalToConstant: 49).isActive = true
        let promptLabel = NSTextField(labelWithString: "阅读提示词")
        promptLabel.font = .systemFont(ofSize: 11); promptLabel.textColor = .secondaryLabelColor
        presetPopup.font = .systemFont(ofSize: 11); presetPopup.target = self; presetPopup.action = #selector(changePreset)
        applyButton.isBordered = false; applyButton.font = .systemFont(ofSize: 11)
        applyButton.target = self; applyButton.action = #selector(applyPreset)
        recordButton.isBordered = false; recordButton.toolTip = "打开会话记录目录"
        recordButton.target = self; recordButton.action = #selector(revealHistory)
        webButton.isBordered = false; webButton.toolTip = "在网页继续对话"
        webButton.target = self; webButton.action = #selector(openWebConversation); webButton.isHidden = true
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
        messagesScroll.onZoom = { [weak self] delta in self?.setChatZoom((self?.chatZoom ?? 1) * exp(delta * 0.004)) }
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        messagesStack.widthAnchor.constraint(equalTo: messagesScroll.contentView.widthAnchor, constant: -16).isActive = true
        composerCard.wantsLayer = true; composerCard.layer?.cornerRadius = 14
        composerCard.layer?.borderWidth = 1; composerCard.layer?.borderColor = NSColor.separatorColor.cgColor
        composerCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        composerScroll.drawsBackground = false; composerScroll.hasVerticalScroller = true
        composer.isRichText = false; composer.drawsBackground = false; composer.font = .systemFont(ofSize: 13)
        composer.textContainerInset = NSSize(width: 7, height: 6); composer.delegate = self
        composer.registerForDraggedTypes([.fileURL, .png, .tiff])
        composer.onImages = { [weak self] images in
            guard let self else { return }
            self.attachments.append(contentsOf: images.prefix(max(0, 4 - self.attachments.count)))
            self.updateAttachments(); self.draftChanged()
        }
        composerScroll.documentView = composer
        attachButton.isBordered = false; attachButton.target = self; attachButton.action = #selector(attach)
        attachButton.toolTip = "添加图片或当前 PDF"
        attachmentLabel.font = .systemFont(ofSize: 10); attachmentLabel.textColor = .secondaryLabelColor
        modelButton.isBordered = false; modelButton.font = .systemFont(ofSize: 11)
        modelButton.target = self; modelButton.action = #selector(configureModel)
        sendButton.isBordered = false; sendButton.target = self; sendButton.action = #selector(sendOrStop)
        let footer = NSStackView(views: [attachButton, attachmentLabel, NSView(), modelButton, sendButton])
        footer.orientation = .horizontal; footer.alignment = .centerY; footer.spacing = 6
        composerScroll.translatesAutoresizingMaskIntoConstraints = false; footer.translatesAutoresizingMaskIntoConstraints = false
        composerCard.addSubview(composerScroll); composerCard.addSubview(footer)
        NSLayoutConstraint.activate([
            composerScroll.topAnchor.constraint(equalTo: composerCard.topAnchor, constant: 6),
            composerScroll.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 5),
            composerScroll.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -5),
            composerScroll.heightAnchor.constraint(equalToConstant: 56),
            footer.leadingAnchor.constraint(equalTo: composerCard.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: composerCard.trailingAnchor, constant: -8),
            footer.topAnchor.constraint(equalTo: composerScroll.bottomAnchor), footer.bottomAnchor.constraint(equalTo: composerCard.bottomAnchor, constant: -7)
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
    func setPaperTitle(_ title: String) { toolTip = title }
    func activate() { }
    func close() { }
    func setModelTitle(_ title: String) { modelButton.title = title.isEmpty ? "选择模型 ▾" : title + " ▾" }
    private func setChatZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        chatZoom = min(2.4, max(0.8, value))
        UserDefaults.standard.set(Double(chatZoom), forKey: "reader.nativePaperChatZoom")
        messages.values.forEach { $0.setFontSize(14 * chatZoom) }
        for (id, constraint) in userBubbleWidths {
            constraint.constant = bubbleWidth(for: messageContents[id] ?? "", hasImages: userBubbleHasImages.contains(id))
        }
        composer.font = .systemFont(ofSize: 13 * chatZoom)
    }
    func setWebConversationURL(_ value: String?) {
        let url = value.flatMap(URL.init(string:))
        webConversationURL = url.flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        webButton.isHidden = webConversationURL == nil
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
        tabs.arrangedSubviews.forEach { tabs.removeArrangedSubview($0); $0.removeFromSuperview() }
        for conversation in conversations.sorted(by: { $0.createdAt < $1.createdAt }) {
            let button = NSButton(title: conversation.title, target: self, action: #selector(selectConversation(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(conversation.id); button.isBordered = false
            button.font = .systemFont(ofSize: 12, weight: conversation.id == selectedID ? .semibold : .regular)
            button.isEnabled = !busy; button.toolTip = conversation.title
            let close = NSButton(title: "×", target: self, action: #selector(deleteConversation(_:)))
            close.identifier = button.identifier; close.isBordered = false; close.isEnabled = !busy
            let row = NativePaperTab(views: [button, close]); row.orientation = .horizontal; row.spacing = 2
            row.selected = conversation.id == selectedID
            tabs.addArrangedSubview(row)
        }
    }
    func setPromptTemplates(_ values: [AIPromptTemplate], selectedPreset: AIPromptPreset) {
        templates = values.isEmpty ? NativePaperPrompts.templates : values; self.selectedPreset = selectedPreset
        presetPopup.removeAllItems(); for value in templates { presetPopup.addItem(withTitle: value.name); presetPopup.lastItem?.representedObject = value.id }
        if let index = templates.firstIndex(where: { $0.id == selectedPreset.rawValue }) { presetPopup.selectItem(at: index) }
    }
    func install(_ values: [AIChatMessage]) {
        messagesStack.arrangedSubviews.forEach { messagesStack.removeArrangedSubview($0); $0.removeFromSuperview() }
        messages.removeAll(); messageRows.removeAll(); messageContents.removeAll(); userBubbleWidths.removeAll(); userBubbleHasImages.removeAll(); reasoningViews.removeAll(); reasoningButtons.removeAll(); values.forEach(append)
    }
    func append(_ message: AIChatMessage) {
        let rendered = AIChatRenderedContentView(); rendered.translatesAutoresizingMaskIntoConstraints = false; rendered.alignment = .width
        rendered.setContent(message.content, renderMarkdown: message.role == .assistant)
        rendered.setFontSize(14 * chatZoom)
        rendered.setImageAttachments(message.imageAttachments)
        let row = NSStackView(); row.orientation = .vertical; row.alignment = .leading; row.spacing = 5
        if let pdfName = message.pdfAttachmentName, !pdfName.isEmpty {
            let attachment = NSTextField(labelWithString: "▤  " + pdfName)
            attachment.font = .systemFont(ofSize: 11 * chatZoom, weight: .medium)
            attachment.textColor = .secondaryLabelColor
            attachment.lineBreakMode = .byTruncatingMiddle
            row.addArrangedSubview(attachment)
        }
        if message.role == .assistant {
            let toggle = NSButton(title: "▸ 思考过程", target: self, action: #selector(toggleReasoning(_:)))
            toggle.identifier = NSUserInterfaceItemIdentifier(message.id); toggle.isBordered = false
            toggle.font = .systemFont(ofSize: 11); toggle.contentTintColor = .secondaryLabelColor
            let reasoning = NSTextField(wrappingLabelWithString: message.reasoning ?? ""); reasoning.isSelectable = true
            reasoning.font = .systemFont(ofSize: 12); reasoning.textColor = .secondaryLabelColor; reasoning.isHidden = true
            toggle.isHidden = reasoning.stringValue.isEmpty
            row.addArrangedSubview(toggle); row.addArrangedSubview(reasoning)
            reasoning.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            reasoningViews[message.id] = reasoning; reasoningButtons[message.id] = toggle
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
            copy.identifier = NSUserInterfaceItemIdentifier(message.id); copy.isBordered = false; copy.contentTintColor = .secondaryLabelColor; copy.toolTip = "复制回复"
            let delete = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "删除消息") ?? NSImage(), target: self, action: #selector(deleteMessage(_:)))
            delete.identifier = copy.identifier; delete.isBordered = false; delete.contentTintColor = .secondaryLabelColor; delete.toolTip = "删除消息"
            let formatter = DateFormatter(); formatter.dateFormat = "MM 月 dd 日 HH:mm"
            let time = NSTextField(labelWithString: formatter.string(from: message.createdAt)); time.font = .systemFont(ofSize: 10); time.textColor = .tertiaryLabelColor
            let footer = NSStackView(views: [copy, delete, time]); footer.orientation = .horizontal; footer.spacing = 8
            row.addArrangedSubview(footer)
        }
        row.wantsLayer = true; row.layer?.cornerRadius = 10
        if message.role == .user { row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor; row.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10) }
        messagesStack.addArrangedSubview(row)
        if message.role != .user {
            row.widthAnchor.constraint(equalTo: messagesStack.widthAnchor, constant: -32).isActive = true
            rendered.leadingAnchor.constraint(equalTo: row.leadingAnchor).isActive = true
            rendered.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        } else {
            row.widthAnchor.constraint(lessThanOrEqualTo: messagesStack.widthAnchor, multiplier: 0.85).isActive = true
            row.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            let hasAttachments = !message.imageAttachments.isEmpty || message.pdfAttachmentName != nil
            let width = row.widthAnchor.constraint(equalToConstant: bubbleWidth(for: message.content, hasImages: hasAttachments))
            width.priority = .defaultHigh; width.isActive = true; userBubbleWidths[message.id] = width
            if hasAttachments { userBubbleHasImages.insert(message.id) }
        }
        messages[message.id] = rendered; messageRows[message.id] = row; messageContents[message.id] = message.content
        DispatchQueue.main.async { [weak self] in self?.scrollToBottom() }
    }
    func updateMessage(id: String, content: String, renderMarkdown: Bool = false) { messageContents[id] = content; messages[id]?.setContent(content, renderMarkdown: renderMarkdown) }
    func updateReasoning(id: String, content: String) { reasoningViews[id]?.stringValue = content; reasoningButtons[id]?.isHidden = content.isEmpty }
    func updateToolEvent(id: String, event: AIChatToolEvent) {
        reasoningViews[id]?.stringValue = "输入\n" + event.arguments + (event.result.map { "\n\n结果\n" + $0 } ?? "")
        reasoningButtons[id]?.title = (reasoningViews[id]?.isHidden == false ? "▾" : "▸") + " 工具 · " + event.name + (event.isError ? "（失败）" : "")
    }
    func setToolActivity(_ name: String) { statusLabel.stringValue = "正在调用 \(name)…" }
    private func bubbleWidth(for text: String, hasImages: Bool) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 14 * chatZoom)
        let widest = text.components(separatedBy: "\n").map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return max(hasImages ? 180 : 44, ceil(widest) + 24)
    }
    func removeMessage(id: String) { if let row = messageRows.removeValue(forKey: id) { messagesStack.removeArrangedSubview(row); row.removeFromSuperview() }; messages.removeValue(forKey: id); messageContents.removeValue(forKey: id); userBubbleWidths.removeValue(forKey: id); userBubbleHasImages.remove(id); reasoningViews.removeValue(forKey: id); reasoningButtons.removeValue(forKey: id) }
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
    func setMessageActivity(id: String, phase: AIChatActivityPhase, identity: String) { }
    func setStreaming(_ streaming: Bool) {
        busy = streaming; sendButton.title = streaming ? "■" : "↑"; addButton.isEnabled = !streaming
        for row in tabs.arrangedSubviews { for button in row.subviews.compactMap({ $0 as? NSButton }) { button.isEnabled = !streaming } }
        webButton.isEnabled = !streaming
    }
    func setQueuedSubmissions(_ submissions: [AIChatSubmission]) { if !submissions.isEmpty { statusLabel.stringValue = "排队中：\(submissions.count)" } }
    func prefill(_ text: String, attachments: [AIChatImageAttachment] = [], includeCurrentPDF: Bool = false) {
        guard composer.string.isEmpty else { return }; composer.string = text; self.attachments = attachments; includePDF = includeCurrentPDF; updateAttachments(); draftChanged()
    }
    func restoreDraft(_ text: String, attachments: [AIChatImageAttachment], includePDF: Bool) {
        suppressDraftCallback = true; composer.string = text; self.attachments = attachments; self.includePDF = includePDF; updateAttachments(); suppressDraftCallback = false
    }
    func insertPrompt(_ text: String) { guard !text.isEmpty else { return }; composer.string = text + (composer.string.isEmpty ? "" : "\n\n" + composer.string); draftChanged(); focusComposer() }
    func insertQuote(_ text: String) { guard !text.isEmpty else { return }; composer.string = text + composer.string; draftChanged(); focusComposer() }
    func focusComposer() { window?.makeFirstResponder(composer) }
    func clearComposer() { composer.string = ""; attachments = []; includePDF = false; updateAttachments(); draftChanged() }
    func presentHistoryMenu(_ menu: NSMenu) { menu.popUp(positioning: nil, at: .zero, in: recordButton) }
    func textDidChange(_ notification: Notification) { composer.needsDisplay = true; draftChanged() }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)),
           !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false), !busy {
            sendOrStop(); return true
        }
        return false
    }
    private func draftChanged() { if !suppressDraftCallback { onDraftChange?(composer.string, attachments, includePDF) } }
    private func updateAttachments() { attachmentLabel.stringValue = ([includePDF ? "PDF" : nil, attachments.isEmpty ? nil : "\(attachments.count) 张图片"].compactMap { $0 }).joined(separator: " · ") }
    private func scrollToBottom() { let clip = messagesScroll.contentView; let h = messagesStack.frame.height; clip.scroll(to: NSPoint(x: 0, y: max(0, h - clip.bounds.height))); messagesScroll.reflectScrolledClipView(clip) }
    @objc private func addConversation() { onNewConversation?() }
    @objc private func selectConversation(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onSelectConversation?(id) } }
    @objc private func deleteConversation(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onDeleteConversation?(id) } }
    @objc private func copyMessage(_ sender: NSButton) { guard let id = sender.identifier?.rawValue, let content = messageContents[id] else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
    @objc private func toggleReasoning(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue, let view = reasoningViews[id] else { return }
        view.isHidden.toggle()
        let base = sender.title.dropFirst(2)
        sender.title = (view.isHidden ? "▸ " : "▾ ") + base
    }
    @objc private func deleteMessage(_ sender: NSButton) { if let id = sender.identifier?.rawValue { onDeleteMessage?(id) } }
    @objc private func changePreset() { guard let id = presetPopup.selectedItem?.representedObject as? String else { return }; selectedPreset = AIPromptPreset(rawValue: id); onPresetChange?(selectedPreset) }
    @objc private func applyPreset() { onApplyPrompt?(selectedPreset) }
    @objc private func revealHistory() { onRevealCurrentHistory?() }
    @objc private func openWebConversation() { if let webConversationURL { NSWorkspace.shared.open(webConversationURL) } }
    @objc private func configureModel() {
        guard !modelRoutes.isEmpty else { onConfigure?(); return }
        let menu = NSMenu()
        if customModelTitle != "自定义模型" {
            let custom = NSMenuItem(title: customModelTitle, action: #selector(selectModel(_:)), keyEquivalent: "")
            custom.target = self; custom.representedObject = Self.customRouteID; custom.state = currentModelRouteID == Self.customRouteID ? .on : .off
            menu.addItem(custom)
        }
        for route in modelRoutes {
            let item = NSMenuItem(title: route.name + (route.isSupported ? "" : "（暂不支持此协议）"), action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = route.id; item.state = route.id == currentModelRouteID ? .on : .off; item.isEnabled = route.isSupported
            menu.addItem(item)
        }
        if let route = modelRoutes.first(where: { $0.id == currentModelRouteID }), let efforts = route.reasoningEfforts, !efforts.isEmpty {
            menu.addItem(.separator())
            let parent = NSMenuItem(title: "思考强度", action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: "思考强度")
            let automatic = NSMenuItem(title: "默认", action: #selector(selectReasoning(_:)), keyEquivalent: "")
            automatic.target = self; automatic.state = currentReasoningEffort == nil ? .on : .off; submenu.addItem(automatic)
            for effort in efforts {
                let item = NSMenuItem(title: effort, action: #selector(selectReasoning(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = effort; item.state = currentReasoningEffort == effort ? .on : .off; submenu.addItem(item)
            }
            parent.submenu = submenu; menu.addItem(parent)
        }
        menu.addItem(.separator()); let settings = NSMenuItem(title: "模型设置…", action: #selector(openModelSettings), keyEquivalent: ""); settings.target = self; menu.addItem(settings)
        menu.popUp(positioning: nil, at: .zero, in: modelButton)
    }
    @objc private func selectModel(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { onSelectModel?(id) } }
    @objc private func selectReasoning(_ sender: NSMenuItem) { onSelectReasoning?(sender.representedObject as? String) }
    @objc private func openModelSettings() { onConfigure?() }
    @objc private func sendOrStop() { if busy { onCancel?(); return }; let text = composer.string; guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty || includePDF else { return }; onSend?(text, attachments, selectedPreset, includePDF) }
    @objc private func attach() {
        let menu = NSMenu(); menu.addItem(withTitle: includePDF ? "移除当前 PDF" : "附加当前 PDF", action: #selector(togglePDF), keyEquivalent: "").target = self
        menu.addItem(withTitle: "添加图片…", action: #selector(addImage), keyEquivalent: "").target = self
        if !attachments.isEmpty { menu.addItem(withTitle: "移除所有图片", action: #selector(removeImages), keyEquivalent: "").target = self }
        menu.popUp(positioning: nil, at: .zero, in: attachButton)
    }
    @objc private func togglePDF() { includePDF.toggle(); updateAttachments(); draftChanged() }
    @objc private func removeImages() { attachments = []; updateAttachments(); draftChanged() }
    @objc private func addImage() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls.prefix(max(0, 4 - attachments.count)) {
            guard let data = try? Data(contentsOf: url), let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType else { continue }
            attachments.append(AIChatImageAttachment(fileName: url.lastPathComponent, mimeType: type, data: data))
        }
        updateAttachments(); draftChanged()
    }
}

private final class NativePaperTab: NSStackView {
    var selected = false { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selected else { return }
        NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1.5).fill()
    }
}

private final class NativePaperComposer: NSTextView {
    var onImages: (([AIChatImageAttachment]) -> Void)?

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
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.placeholderTextColor]
        ("发消息或创建任务" as NSString).draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height), withAttributes: attributes)
    }
}

private final class NativePaperMessageStack: NSStackView {
    override var isFlipped: Bool { true }
}

private final class NativePaperChatScrollView: NSScrollView {
    var onZoom: ((CGFloat) -> Void)?
    override func magnify(with event: NSEvent) { onZoom?(event.magnification * 250) }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { onZoom?(event.scrollingDeltaY); return }
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
