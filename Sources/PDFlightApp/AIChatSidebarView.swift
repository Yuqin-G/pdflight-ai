import AppKit
import PDFlightAI
import UniformTypeIdentifiers

extension Notification.Name {
    static let aiReplyGestureZoomPreferenceDidChange = Notification.Name(
        "PDFlightAIReplyGestureZoomPreferenceDidChange"
    )
}

enum AIReplyGestureZoomPreference {
    static let defaultsKey = "reader.aiReplyGestureZoomEnabled"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultsKey)
    }

    static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = .standard,
        broadcast: Bool = true
    ) {
        defaults.set(enabled, forKey: defaultsKey)
        if broadcast {
            NotificationCenter.default.post(
                name: .aiReplyGestureZoomPreferenceDidChange,
                object: nil,
                userInfo: ["enabled": enabled]
            )
        }
    }
}
import iosMath

enum AIChatActivityPhase: Equatable {
    case ready
    case loading
    case preparing
    case uploading
    case waiting
    case thinking
    case answering
    case completed
    case stopped
    case failed

    fileprivate var title: String {
        switch self {
        case .ready: "Ready"
        case .loading: "Loading"
        case .preparing: "Preparing request"
        case .uploading: "Uploading PDF"
        case .waiting: "Waiting for model"
        case .thinking: "Thinking"
        case .answering: "Writing answer"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .failed: "Request failed"
        }
    }

    fileprivate var isActive: Bool {
        switch self {
        case .loading, .preparing, .uploading, .waiting, .thinking, .answering: true
        case .ready, .completed, .stopped, .failed: false
        }
    }

    fileprivate var color: NSColor {
        switch self {
        case .ready, .completed: .systemGreen
        case .loading, .preparing, .uploading, .waiting, .answering: AIChatClaudePalette.clay
        case .thinking: .systemOrange
        case .stopped: .secondaryLabelColor
        case .failed: .systemRed
        }
    }
}

/// Claude-style warm palette (open-claude-ui tokens): terracotta clay
/// accents on warm neutrals instead of the cool system accent.
enum AIChatClaudePalette {
    private static func dynamic(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
    }

    static let clay = dynamic(rgb(217, 119, 87), rgb(204, 107, 73))       // #d97757 / #cc6b49
    static let userBubble = dynamic(rgb(240, 238, 230), rgb(255, 255, 255, alpha: 0.07))
    static let composerCard = dynamic(.white, rgb(26, 26, 25))
    static let hairline = dynamic(rgb(0, 0, 0, alpha: 0.08), rgb(255, 255, 255, alpha: 0.10))
    static let sidebarBackground = dynamic(rgb(252, 252, 251), .windowBackgroundColor)
    static let chipSelectedBackground = dynamic(rgb(251, 243, 239), rgb(204, 107, 73, alpha: 0.18))
    static let chipHover = dynamic(rgb(0, 0, 0, alpha: 0.045), rgb(255, 255, 255, alpha: 0.06))
}

@MainActor
final class AIChatSidebarView: NSView {
    var onSend: ((String, [AIChatImageAttachment], AIPromptPreset, Bool) -> Void)?
    var onConfigure: (() -> Void)?
    var onNewConversation: (() -> Void)?
    var onSelectConversation: ((String) -> Void)?
    var onDeleteConversation: (() -> Void)?
    var onDeleteMessage: ((String) -> Void)?
    var onRemoveQueuedSubmission: ((String) -> Void)?
    var onShowHistory: ((NSButton) -> Void)?
    var onRevealCurrentHistory: (() -> Void)?
    var onPresetChange: ((AIPromptPreset) -> Void)?
    var onEditPromptTemplate: ((AIPromptPreset) -> Void)?
    var onAddPromptTemplate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onResizeBy: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "Ask PDF")
    private let paperLabel = NSTextField(labelWithString: "")
    private let conversationScrollView = NSScrollView()
    private let conversationStack = NSStackView()
    private let historyButton = NSButton()
    private let currentHistoryButton = NSButton()
    private let newConversationButton = NSButton()
    private let deleteConversationButton = NSButton()
    private let decreaseFontButton = NSButton()
    private let increaseFontButton = NSButton()
    private let settingsButton = NSButton()
    private let messageScrollView = AIChatMessageScrollView()
    private let messageStack = AIChatMessageStackView()
    private let queueContainer = NSView()
    private let queueTitleLabel = NSTextField(labelWithString: "Queued")
    private let queueScrollView = NSScrollView()
    private let queueStack = NSStackView()
    private let composerContainer = NSView()
    private let attachmentScrollView = NSScrollView()
    private let attachmentStack = NSStackView()
    private let composerScrollView = NSScrollView()
    private let composer = AIChatComposerTextView(frame: .zero)
    private let promptModeScrollView = NSScrollView()
    private let promptModeStack = NSStackView()
    private let promptManageButton = NSButton()
    private let attachPDFButton = NSButton()
    private let attachImageButton = NSButton()
    private let sendButton = NSButton()
    private let cancelButton = NSButton()
    private let activityContainer = NSView()
    private let activityIndicator = NSProgressIndicator()
    private let activityDot = AIActivityDotView()
    private let activityTitleLabel = NSTextField(labelWithString: "Ready")
    private let statusLabel = NSTextField(labelWithString: "No prompt sends only the visible chat.")
    private let resizeHandle = AISidebarResizeHandle()
    private var messageViews: [String: AIChatMessageView] = [:]
    private var emptyStateView: NSView?
    private var conversationIDs: [String] = []
    private var conversationButtons: [String: AIChatSelectionButton] = [:]
    private var selectedConversationID: String?
    private var promptTemplates = AIPromptTemplate.defaults
    private var promptButtons: [String: AIChatSelectionButton] = [:]
    private var selectedPromptPreset = AIPromptPreset.defaultForNewConversation
    private var messageFontSize: CGFloat = {
        let stored = UserDefaults.standard.double(forKey: "reader.aiChatFontSize")
        return stored.isFinite && stored >= 11 && stored <= 24 ? stored : 13.5
    }()
    private var replyGestureZoomEnabled = false
    private var isApplyingSelection = false
    private var composerAttachments: [AIChatImageAttachment] = []
    private var attachmentHeightConstraint: NSLayoutConstraint!
    private var queueHeightConstraint: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if point.x >= 0, point.x <= 18, bounds.contains(point) {
            return resizeHandle
        }
        return super.hitTest(point)
    }

    func setPaperTitle(_ title: String) {
        paperLabel.stringValue = title
        paperLabel.toolTip = title
    }

    func setReplyGestureZoomEnabled(_ enabled: Bool) {
        replyGestureZoomEnabled = enabled
        messageScrollView.toolTip = enabled
            ? "Pinch or Command-scroll to resize reply text"
            : "Reply gesture zoom is off in AI Settings"
    }

    func setConversations(_ conversations: [AIConversation], selectedID: String) {
        let ordered = conversations.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.id < rhs.id }
            return lhs.createdAt < rhs.createdAt
        }
        isApplyingSelection = true
        conversationStack.arrangedSubviews.forEach {
            conversationStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        conversationIDs = ordered.map(\.id)
        conversationButtons.removeAll()
        selectedConversationID = conversationIDs.contains(selectedID) ? selectedID : conversationIDs.first
        for conversation in ordered {
            let button = AIChatSelectionButton(title: conversation.title)
            button.identifierValue = conversation.id
            button.toolTip = conversation.title
            button.target = self
            button.action = #selector(conversationChanged(_:))
            button.setSelected(conversation.id == selectedConversationID)
            conversationButtons[conversation.id] = button
            conversationStack.addArrangedSubview(button)
        }
        conversationStack.addArrangedSubview(newConversationButton)
        deleteConversationButton.isEnabled = !ordered.isEmpty
        isApplyingSelection = false
        scrollConversationTabToVisible(selectedConversationID)
    }

    func selectPromptPreset(_ preset: AIPromptPreset) {
        let resolved = promptTemplates.contains { $0.id == preset.rawValue }
            ? preset
            : AIPromptPreset.none
        selectedPromptPreset = resolved
        promptButtons.forEach { id, button in
            button.setSelected(id == resolved.rawValue)
        }
    }

    func setPromptTemplates(_ templates: [AIPromptTemplate], selectedPreset: AIPromptPreset) {
        promptTemplates = templates.isEmpty ? AIPromptTemplate.defaults : templates
        promptModeStack.arrangedSubviews.forEach {
            promptModeStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        promptButtons.removeAll()
        for template in promptTemplates {
            let button = AIChatSelectionButton(title: template.name, compact: true)
            button.identifierValue = template.id
            button.toolTip = "Use \(template.name) prompt mode"
            button.target = self
            button.action = #selector(promptChanged(_:))
            promptButtons[template.id] = button
            promptModeStack.addArrangedSubview(button)
        }
        selectPromptPreset(selectedPreset)
    }

    func install(_ messages: [AIChatMessage]) {
        messageStack.arrangedSubviews.forEach {
            messageStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        emptyStateView = nil
        messageViews.removeAll()
        if messages.isEmpty {
            installEmptyState()
        } else {
            messages.forEach(append)
        }
        setCurrentPDFAttachmentSelected(false)
        scrollToBottom()
    }

    func append(_ message: AIChatMessage) {
        removeEmptyState()
        let view = AIChatMessageView(message: message, fontSize: messageFontSize)
        view.onDelete = { [weak self] in self?.onDeleteMessage?(message.id) }
        messageViews[message.id] = view
        messageStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: messageStack.widthAnchor, constant: -32).isActive = true
        scrollToBottom()
    }

    func updateMessage(id: String, content: String, renderMarkdown: Bool = false) {
        messageViews[id]?.setContent(content, renderMarkdown: renderMarkdown)
        messageStack.needsLayout = true
        scrollToBottom()
    }

    func setMessageActivity(id: String, phase: AIChatActivityPhase, identity: String) {
        messageViews[id]?.setActivity(phase, identity: identity)
        messageStack.needsLayout = true
        scrollToBottom()
    }

    func removeMessage(id: String) {
        guard let view = messageViews.removeValue(forKey: id) else { return }
        messageStack.removeArrangedSubview(view)
        view.removeFromSuperview()
        if messageViews.isEmpty {
            installEmptyState()
        }
        if messageViews.isEmpty { installEmptyState() }
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func setActivity(_ phase: AIChatActivityPhase, detail: String) {
        activityTitleLabel.stringValue = phase.title
        activityTitleLabel.textColor = (phase.isActive || phase == .failed) ? phase.color : .labelColor
        statusLabel.stringValue = detail
        activityDot.color = phase.color
        activityDot.isHidden = phase.isActive
        activityIndicator.isHidden = !phase.isActive
        if phase.isActive {
            activityIndicator.startAnimation(nil)
        } else {
            activityIndicator.stopAnimation(nil)
        }
        activityContainer.setAccessibilityLabel("AI activity")
        activityContainer.setAccessibilityValue("\(phase.title). \(detail)")
    }

    func setStreaming(_ streaming: Bool) {
        sendButton.isHidden = false
        cancelButton.isHidden = !streaming
        composer.isEditable = true
        promptButtons.values.forEach { $0.isEnabled = true }
        promptManageButton.isEnabled = true
        attachPDFButton.isEnabled = true
        attachImageButton.isEnabled = true
        conversationButtons.values.forEach { $0.isEnabled = !streaming }
        newConversationButton.isEnabled = !streaming
        deleteConversationButton.isEnabled = !streaming && !conversationIDs.isEmpty
    }

    func setQueuedSubmissions(_ submissions: [AIChatSubmission]) {
        queueStack.arrangedSubviews.forEach {
            queueStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, submission) in submissions.enumerated() {
            let row = AIQueuedSubmissionView(submission: submission, position: index + 1)
            row.onRemove = { [weak self] in
                self?.onRemoveQueuedSubmission?(submission.id)
            }
            queueStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: queueStack.widthAnchor).isActive = true
        }
        queueTitleLabel.stringValue = submissions.isEmpty
            ? "Queued"
            : "Queued · \(submissions.count)"
        let height: CGFloat = submissions.isEmpty
            ? 0
            : min(118, 25 + CGFloat(submissions.count) * 35)
        queueContainer.isHidden = submissions.isEmpty
        queueHeightConstraint?.constant = height
        needsLayout = true
    }

    func prefill(
        _ text: String,
        attachments: [AIChatImageAttachment] = [],
        includeCurrentPDF: Bool = false
    ) {
        guard composer.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        composer.string = text
        if composerAttachments.isEmpty, !attachments.isEmpty {
            composerAttachments = Array(attachments.prefix(4))
            rebuildComposerAttachments()
        }
        if includeCurrentPDF {
            setCurrentPDFAttachmentSelected(true)
        }
        composer.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        composer.needsDisplay = true
    }

    func focusComposer() {
        window?.makeFirstResponder(composer)
    }

    func messageFramesForLayoutCheck() -> [NSRect] {
        layoutSubtreeIfNeeded()
        messageStack.layoutSubtreeIfNeeded()
        return messageViews.values.map { $0.convert($0.bounds, to: self) }
    }

    func selectedConversationIDForLayoutCheck() -> String? {
        selectedConversationID
    }

    func selectedPromptPresetForLayoutCheck() -> AIPromptPreset {
        selectedPromptPreset
    }

    func messageFontSizeForLayoutCheck() -> CGFloat {
        messageFontSize
    }

    func setMessageFontSizeForLayoutCheck(_ fontSize: CGFloat) {
        applyMessageFontSize(fontSize, persist: false)
    }

    func magnifyMessageContentForLayoutCheck(by delta: CGFloat) {
        guard replyGestureZoomEnabled else { return }
        applyMessageFontSize(
            messageFontSize + delta,
            persist: false,
            preserveScrollPosition: true
        )
    }

    func newConversationButtonFollowsTabsForLayoutCheck() -> Bool {
        conversationStack.arrangedSubviews.last === newConversationButton
            && !newConversationButton.isDescendant(of: titleLabel.superview ?? self)
    }

    func isMessageVisibleForLayoutCheck(id: String) -> Bool {
        layoutSubtreeIfNeeded()
        messageStack.layoutSubtreeIfNeeded()
        guard let view = messageViews[id] else { return false }
        let frame = view.convert(view.bounds, to: messageStack)
        return messageScrollView.documentVisibleRect.intersects(frame)
    }

    func renderedMessageTextForLayoutCheck(id: String) -> String {
        messageViews[id]?.renderedTextForLayoutCheck() ?? ""
    }

    func messageContentAcceptsFocusForLayoutCheck(id: String) -> Bool {
        messageViews[id]?.contentAcceptsFocusForLayoutCheck() ?? false
    }

    func messageContentContainsSelectableTextForLayoutCheck(id: String) -> Bool {
        messageViews[id]?.contentContainsSelectableTextForLayoutCheck() ?? false
    }

    func copyMessageSelectionForLayoutCheck(id: String) -> Bool {
        messageViews[id]?.copyContentForLayoutCheck() ?? false
    }

    func renderedMathLatexForLayoutCheck(id: String) -> [String] {
        messageViews[id]?.renderedMathLatexForLayoutCheck() ?? []
    }

    func messageTimestampForLayoutCheck(id: String) -> String {
        messageViews[id]?.timestampForLayoutCheck() ?? ""
    }

    func hasScrollableDisplayMathForLayoutCheck(id: String) -> Bool {
        messageViews[id]?.hasScrollableDisplayMathForLayoutCheck() ?? false
    }

    func renderedBlockCountForLayoutCheck(id: String) -> Int {
        messageViews[id]?.renderedBlockCountForLayoutCheck() ?? 0
    }

    func inlineMathAttachmentCountForLayoutCheck(id: String) -> Int {
        messageViews[id]?.inlineMathAttachmentCountForLayoutCheck() ?? 0
    }

    func messageHasFontTraitForLayoutCheck(
        id: String,
        text: String,
        trait: NSFontTraitMask
    ) -> Bool {
        messageViews[id]?.contentHasFontTraitForLayoutCheck(text: text, trait: trait) ?? false
    }

    func messageHasBottomActionsForLayoutCheck(id: String) -> Bool {
        messageViews[id]?.hasBottomActionsForLayoutCheck() ?? false
    }

    func tableColumnWidthsForLayoutCheck(id: String) -> [CGFloat] {
        messageViews[id]?.tableColumnWidthsForLayoutCheck() ?? []
    }

    func triggerDeleteMessageForLayoutCheck(id: String) {
        messageViews[id]?.triggerDeleteForLayoutCheck()
    }

    func composerFontSizeForLayoutCheck() -> CGFloat {
        composer.font?.pointSize ?? 0
    }

    func currentPDFAttachmentIsVisuallyEmphasizedForLayoutCheck() -> Bool {
        attachPDFButton.state == .on
            && attachPDFButton.title == "PDF"
            && attachPDFButton.contentTintColor?.isEqual(AIChatClaudePalette.clay) == true
            && attachPDFButton.layer?.backgroundColor != nil
    }

    func setCurrentPDFAttachmentSelectedForLayoutCheck(_ selected: Bool) {
        setCurrentPDFAttachmentSelected(selected)
    }

    func currentPDFAttachmentSelectedForLayoutCheck() -> Bool {
        attachPDFButton.state == .on
    }

    func triggerPromptPresetForLayoutCheck(_ preset: AIPromptPreset) {
        promptButtons[preset.rawValue]?.performClick(nil)
    }

    func clearComposer() {
        composer.string = ""
        composerAttachments.removeAll()
        rebuildComposerAttachments()
        composer.needsDisplay = true
    }

    func addImageAttachmentForLayoutCheck(_ attachment: AIChatImageAttachment) {
        addImageAttachments([attachment])
    }

    func composerImageAttachmentCountForLayoutCheck() -> Int {
        composerAttachments.count
    }

    func pasteImageFromKeyboardForLayoutCheck(_ pasteboard: NSPasteboard) -> Bool {
        composer.performPasteKeyEquivalentForLayoutCheck(from: pasteboard)
    }

    func triggerRevealCurrentHistoryForLayoutCheck() {
        revealCurrentHistoryPressed(nil)
    }

    func composerAcceptsQueuedInputForLayoutCheck() -> Bool {
        composer.isEditable
            && composer.acceptsFirstResponder
            && attachImageButton.isEnabled
            && !sendButton.isHidden
    }

    func composerReceivesPointerForLayoutCheck() -> Bool {
        layoutSubtreeIfNeeded()
        composerContainer.layoutSubtreeIfNeeded()
        composerScrollView.layoutSubtreeIfNeeded()
        let visibleBounds = composerScrollView.contentView.bounds
        guard visibleBounds.width > 1, visibleBounds.height > 1,
              composer.frame.width > 1, composer.frame.height > 1 else { return false }
        let centerInSuperview = composerScrollView.contentView.convert(
            NSPoint(x: visibleBounds.midX, y: visibleBounds.midY),
            to: superview
        )
        var target = hitTest(centerInSuperview)
        while let view = target {
            if view === composer { return true }
            target = view.superview
        }
        return false
    }

    func composerAcceptsActivationClickForLayoutCheck() -> Bool {
        composer.acceptsFirstMouse(for: nil)
    }

    func composerAcceptsTextInsertionForLayoutCheck(_ text: String) -> Bool {
        let original = composer.string
        let originalSelection = composer.selectedRange()
        defer {
            composer.string = original
            composer.setSelectedRange(originalSelection)
        }
        composer.setSelectedRange(NSRange(location: (original as NSString).length, length: 0))
        composer.insertText(text, replacementRange: composer.selectedRange())
        return composer.string == original + text
    }

    func queuedSubmissionCountForLayoutCheck() -> Int {
        queueStack.arrangedSubviews.count
    }

    func triggerSendForLayoutCheck() {
        submitComposer()
    }

    func presentHistoryMenu(_ menu: NSMenu) {
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: historyButton.bounds.minY - 4), in: historyButton)
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = AIChatClaudePalette.sidebarBackground.cgColor
        translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.onDrag = { [weak self] delta in self?.onResizeBy?(delta) }
        resizeHandle.onDragEnded = { [weak self] in self?.onResizeEnded?() }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.setAccessibilityElement(true)
        resizeHandle.setAccessibilityRole(.splitter)
        resizeHandle.setAccessibilityLabel("Resize Ask PDF sidebar")

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        paperLabel.font = .systemFont(ofSize: 11)
        paperLabel.textColor = .secondaryLabelColor
        paperLabel.lineBreakMode = .byTruncatingMiddle
        paperLabel.maximumNumberOfLines = 1
        paperLabel.translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(historyButton, symbol: "clock.arrow.circlepath", tooltip: "Chat history")
        historyButton.action = #selector(historyPressed(_:))
        configureIconButton(
            currentHistoryButton,
            symbol: "doc.text.magnifyingglass",
            tooltip: "Show this paper's chat file in Finder"
        )
        currentHistoryButton.action = #selector(revealCurrentHistoryPressed(_:))
        configureIconButton(newConversationButton, symbol: "plus", tooltip: "New conversation")
        newConversationButton.action = #selector(newConversationPressed(_:))
        newConversationButton.controlSize = .small
        newConversationButton.widthAnchor.constraint(equalToConstant: 27).isActive = true
        newConversationButton.heightAnchor.constraint(equalToConstant: 27).isActive = true
        configureIconButton(decreaseFontButton, symbol: "textformat.size.smaller", tooltip: "Smaller chat text")
        decreaseFontButton.action = #selector(decreaseFontPressed(_:))
        configureIconButton(increaseFontButton, symbol: "textformat.size.larger", tooltip: "Larger chat text")
        increaseFontButton.action = #selector(increaseFontPressed(_:))
        configureIconButton(settingsButton, symbol: "gearshape", tooltip: "AI settings")
        settingsButton.action = #selector(configurePressed(_:))

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [
            titleLabel,
            headerSpacer,
            decreaseFontButton,
            increaseFontButton,
            historyButton,
            currentHistoryButton,
            settingsButton
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 5
        header.translatesAutoresizingMaskIntoConstraints = false

        configureHorizontalStrip(scrollView: conversationScrollView, stack: conversationStack)
        conversationScrollView.toolTip = "Conversations for this paper"
        conversationScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        configureIconButton(deleteConversationButton, symbol: "trash", tooltip: "Delete current conversation")
        deleteConversationButton.action = #selector(deleteConversationPressed(_:))
        let conversationRow = NSStackView(views: [conversationScrollView, deleteConversationButton])
        conversationRow.orientation = .horizontal
        conversationRow.alignment = .centerY
        conversationRow.spacing = 6
        conversationRow.translatesAutoresizingMaskIntoConstraints = false

        messageScrollView.drawsBackground = false
        messageScrollView.hasVerticalScroller = true
        messageScrollView.autohidesScrollers = true
        messageScrollView.toolTip = "Reply gesture zoom is off in AI Settings"
        messageScrollView.onZoom = { [weak self] delta, phase in
            guard let self, replyGestureZoomEnabled else { return }
            zoomMessageContent(by: delta, phase: phase)
        }
        messageScrollView.translatesAutoresizingMaskIntoConstraints = false
        messageStack.orientation = .vertical
        messageStack.alignment = .leading
        messageStack.spacing = 14
        messageStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 14)
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        messageScrollView.documentView = messageStack

        queueContainer.wantsLayer = true
        queueContainer.layer?.cornerRadius = 8
        queueContainer.layer?.cornerCurve = .continuous
        queueContainer.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(0.55).cgColor
        queueContainer.translatesAutoresizingMaskIntoConstraints = false
        queueContainer.isHidden = true

        queueTitleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        queueTitleLabel.textColor = .secondaryLabelColor
        queueTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        queueScrollView.drawsBackground = false
        queueScrollView.borderType = .noBorder
        queueScrollView.hasVerticalScroller = true
        queueScrollView.autohidesScrollers = true
        queueScrollView.translatesAutoresizingMaskIntoConstraints = false
        queueStack.orientation = .vertical
        queueStack.alignment = .leading
        queueStack.spacing = 3
        queueStack.translatesAutoresizingMaskIntoConstraints = false
        queueScrollView.documentView = queueStack
        queueContainer.addSubview(queueTitleLabel)
        queueContainer.addSubview(queueScrollView)

        composerContainer.wantsLayer = true
        composerContainer.layer?.cornerRadius = 16
        composerContainer.layer?.cornerCurve = .continuous
        composerContainer.layer?.borderWidth = 1
        composerContainer.layer?.borderColor = AIChatClaudePalette.hairline.cgColor
        composerContainer.layer?.backgroundColor = AIChatClaudePalette.composerCard.cgColor
        composerContainer.translatesAutoresizingMaskIntoConstraints = false

        composer.font = .systemFont(ofSize: 13)
        composer.textContainerInset = NSSize(width: 9, height: 8)
        composer.isRichText = false
        composer.isEditable = true
        composer.isSelectable = true
        composer.drawsBackground = false
        composer.placeholderString = "Ask about this paper…"
        composer.isAutomaticQuoteSubstitutionEnabled = false
        composer.isAutomaticDashSubstitutionEnabled = false
        composer.isVerticallyResizable = true
        composer.isHorizontallyResizable = false
        composer.autoresizingMask = [.width]
        composer.textContainer?.widthTracksTextView = true
        composer.onSubmit = { [weak self] in self?.submitComposer() }
        composer.onFocusChange = { [weak self] in self?.updateComposerFocusRing() }
        composer.onPasteboardImages = { [weak self] pasteboard in
            self?.addImages(from: pasteboard) ?? false
        }
        composerScrollView.documentView = composer
        composerScrollView.hasVerticalScroller = true
        composerScrollView.autohidesScrollers = true
        composerScrollView.borderType = .noBorder
        composerScrollView.drawsBackground = false
        composerScrollView.translatesAutoresizingMaskIntoConstraints = false
        composer.frame = composerScrollView.contentView.bounds

        configureHorizontalStrip(scrollView: attachmentScrollView, stack: attachmentStack)
        attachmentScrollView.toolTip = "Images attached to this message"
        attachmentScrollView.isHidden = true

        configureComposerAction(attachImageButton, symbol: "photo.badge.plus", tooltip: "Attach images")
        attachImageButton.action = #selector(attachImagePressed(_:))

        configureComposerAction(
            attachPDFButton,
            symbol: "doc.badge.plus",
            tooltip: "Attach the current PDF to the next message"
        )
        attachPDFButton.title = "PDF"
        attachPDFButton.imagePosition = .imageLeading
        attachPDFButton.font = .systemFont(ofSize: 10.5, weight: .semibold)
        attachPDFButton.isBordered = false
        attachPDFButton.wantsLayer = true
        attachPDFButton.layer?.cornerRadius = 6
        attachPDFButton.layer?.cornerCurve = .continuous
        attachPDFButton.setButtonType(.toggle)
        attachPDFButton.action = #selector(attachPDFPressed(_:))
        setCurrentPDFAttachmentSelected(false)

        configureHorizontalStrip(scrollView: promptModeScrollView, stack: promptModeStack)
        promptModeScrollView.toolTip = "Prompt modes"
        promptModeScrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureComposerAction(promptManageButton, symbol: "ellipsis", tooltip: "Edit or add prompt modes")
        promptManageButton.action = #selector(managePromptsPressed(_:))

        configureComposerAction(sendButton, symbol: "arrow.up", tooltip: "Send")
        sendButton.image = NSImage(
            systemSymbolName: "arrow.up",
            accessibilityDescription: "Send"
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        sendButton.wantsLayer = true
        sendButton.layer?.cornerRadius = 11
        sendButton.layer?.cornerCurve = .continuous
        sendButton.layer?.backgroundColor = AIChatClaudePalette.clay.cgColor
        sendButton.contentTintColor = .white
        sendButton.keyEquivalent = "\r"
        sendButton.action = #selector(sendPressed(_:))
        configureComposerAction(cancelButton, symbol: "stop.fill", tooltip: "Stop")
        cancelButton.image = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: "Stop"
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        cancelButton.wantsLayer = true
        cancelButton.layer?.cornerRadius = 11
        cancelButton.layer?.cornerCurve = .continuous
        cancelButton.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        cancelButton.contentTintColor = .labelColor
        cancelButton.action = #selector(cancelPressed(_:))
        cancelButton.isHidden = true

        let composerActions = NSStackView(views: [
            promptModeScrollView,
            promptManageButton,
            attachPDFButton,
            attachImageButton,
            cancelButton,
            sendButton
        ])
        composerActions.orientation = .horizontal
        composerActions.alignment = .centerY
        composerActions.spacing = 6
        composerActions.translatesAutoresizingMaskIntoConstraints = false

        composerContainer.addSubview(attachmentScrollView)
        composerContainer.addSubview(composerScrollView)
        composerContainer.addSubview(composerActions)

        activityContainer.wantsLayer = true
        activityContainer.layer?.cornerRadius = 8
        activityContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
        activityContainer.translatesAutoresizingMaskIntoConstraints = false
        activityContainer.setAccessibilityElement(true)

        activityIndicator.style = .spinning
        activityIndicator.controlSize = .small
        activityIndicator.isIndeterminate = true
        activityIndicator.isDisplayedWhenStopped = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        activityDot.color = .systemGreen
        activityDot.translatesAutoresizingMaskIntoConstraints = false

        activityTitleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        activityTitleLabel.textColor = .labelColor
        activityTitleLabel.setContentHuggingPriority(.required, for: .horizontal)
        activityTitleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        activityContainer.addSubview(activityIndicator)
        activityContainer.addSubview(activityDot)
        activityContainer.addSubview(activityTitleLabel)
        activityContainer.addSubview(statusLabel)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(header)
        addSubview(paperLabel)
        addSubview(conversationRow)
        addSubview(separator)
        addSubview(messageScrollView)
        addSubview(queueContainer)
        addSubview(composerContainer)
        addSubview(activityContainer)
        addSubview(resizeHandle, positioned: .above, relativeTo: nil)

        attachmentHeightConstraint = attachmentScrollView.heightAnchor.constraint(equalToConstant: 0)
        queueHeightConstraint = queueContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            sendButton.widthAnchor.constraint(equalToConstant: 22),
            sendButton.heightAnchor.constraint(equalToConstant: 22),
            cancelButton.widthAnchor.constraint(equalToConstant: 22),
            cancelButton.heightAnchor.constraint(equalToConstant: 22),
            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 18),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            paperLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 3),
            paperLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            paperLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            conversationRow.topAnchor.constraint(equalTo: paperLabel.bottomAnchor, constant: 10),
            conversationRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            conversationRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            conversationRow.heightAnchor.constraint(equalToConstant: 29),
            separator.topAnchor.constraint(equalTo: conversationRow.bottomAnchor, constant: 11),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageScrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            messageScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            messageScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            messageScrollView.bottomAnchor.constraint(equalTo: queueContainer.topAnchor, constant: -7),
            messageStack.widthAnchor.constraint(equalTo: messageScrollView.contentView.widthAnchor),
            queueContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            queueContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            queueContainer.bottomAnchor.constraint(equalTo: composerContainer.topAnchor, constant: -7),
            queueHeightConstraint,
            queueTitleLabel.topAnchor.constraint(equalTo: queueContainer.topAnchor, constant: 6),
            queueTitleLabel.leadingAnchor.constraint(equalTo: queueContainer.leadingAnchor, constant: 9),
            queueTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: queueContainer.trailingAnchor, constant: -9),
            queueScrollView.topAnchor.constraint(equalTo: queueTitleLabel.bottomAnchor, constant: 2),
            queueScrollView.leadingAnchor.constraint(equalTo: queueContainer.leadingAnchor, constant: 5),
            queueScrollView.trailingAnchor.constraint(equalTo: queueContainer.trailingAnchor, constant: -5),
            queueScrollView.bottomAnchor.constraint(equalTo: queueContainer.bottomAnchor, constant: -5),
            queueStack.leadingAnchor.constraint(equalTo: queueScrollView.contentView.leadingAnchor),
            queueStack.topAnchor.constraint(equalTo: queueScrollView.contentView.topAnchor),
            queueStack.trailingAnchor.constraint(equalTo: queueScrollView.contentView.trailingAnchor),
            queueStack.widthAnchor.constraint(equalTo: queueScrollView.contentView.widthAnchor),
            composerContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            composerContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            attachmentScrollView.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 5),
            attachmentScrollView.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 7),
            attachmentScrollView.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -7),
            attachmentHeightConstraint,
            composerScrollView.topAnchor.constraint(equalTo: attachmentScrollView.bottomAnchor, constant: 3),
            composerScrollView.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 3),
            composerScrollView.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -3),
            composerScrollView.heightAnchor.constraint(equalToConstant: 70),
            composerActions.topAnchor.constraint(equalTo: composerScrollView.bottomAnchor, constant: 2),
            composerActions.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 8),
            composerActions.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -7),
            composerActions.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -7),
            promptModeScrollView.heightAnchor.constraint(equalToConstant: 27),
            activityContainer.topAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: 7),
            activityContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            activityContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            activityContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
            activityContainer.heightAnchor.constraint(equalToConstant: 30),
            activityIndicator.leadingAnchor.constraint(equalTo: activityContainer.leadingAnchor, constant: 9),
            activityIndicator.centerYAnchor.constraint(equalTo: activityContainer.centerYAnchor),
            activityIndicator.widthAnchor.constraint(equalToConstant: 12),
            activityIndicator.heightAnchor.constraint(equalToConstant: 12),
            activityDot.centerXAnchor.constraint(equalTo: activityIndicator.centerXAnchor),
            activityDot.centerYAnchor.constraint(equalTo: activityIndicator.centerYAnchor),
            activityDot.widthAnchor.constraint(equalToConstant: 7),
            activityDot.heightAnchor.constraint(equalToConstant: 7),
            activityTitleLabel.leadingAnchor.constraint(equalTo: activityIndicator.trailingAnchor, constant: 7),
            activityTitleLabel.centerYAnchor.constraint(equalTo: activityContainer.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: activityTitleLabel.trailingAnchor, constant: 6),
            statusLabel.trailingAnchor.constraint(equalTo: activityContainer.trailingAnchor, constant: -9),
            statusLabel.centerYAnchor.constraint(equalTo: activityContainer.centerYAnchor)
        ])

        setActivity(.ready, detail: "No prompt sends only the visible chat.")
        setPromptTemplates(AIPromptTemplate.defaults, selectedPreset: .defaultForNewConversation)
        setQueuedSubmissions([])
        install([])
    }

    private func configureIconButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
    }

    private func configureComposerAction(_ button: NSButton, symbol: String, tooltip: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .inline
        button.isBordered = false
        button.controlSize = .small
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
    }

    private func updateComposerFocusRing() {
        let focused = composerContainer.window?.firstResponder === composer
        composerContainer.layer?.borderColor = (
            focused
                ? AIChatClaudePalette.clay.withAlphaComponent(0.7)
                : AIChatClaudePalette.hairline
        ).cgColor
    }

    private func configureHorizontalStrip(scrollView: NSScrollView, stack: NSStackView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.contentView.heightAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.widthAnchor)
        ])
    }

    private func selectedPreset() -> AIPromptPreset {
        selectedPromptPreset
    }

    private func selectedPromptTemplate() -> AIPromptTemplate {
        promptTemplates.first { $0.id == selectedPromptPreset.rawValue }
            ?? AIPromptTemplate.defaults[0]
    }

    private func submitComposer() {
        let text = composer.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = selectedPreset()
        let includeCurrentPDF = attachPDFButton.state == .on
        guard AIChatRequestBuilder.displayQuestion(
            question: text,
            template: selectedPromptTemplate(),
            hasImageAttachments: !composerAttachments.isEmpty,
            includeCurrentPDF: includeCurrentPDF
        ) != nil,
              composer.isEditable else { return }
        let attachments = composerAttachments
        clearComposer()
        setCurrentPDFAttachmentSelected(false)
        onSend?(text, attachments, preset, includeCurrentPDF)
    }

    private func setCurrentPDFAttachmentSelected(_ selected: Bool) {
        attachPDFButton.state = selected ? .on : .off
        let foreground: NSColor = selected ? AIChatClaudePalette.clay : .secondaryLabelColor
        attachPDFButton.bezelColor = nil
        attachPDFButton.contentTintColor = foreground
        attachPDFButton.attributedTitle = NSAttributedString(
            string: "PDF",
            attributes: [
                .font: attachPDFButton.font
                    ?? NSFont.systemFont(ofSize: 10.5, weight: .semibold),
                .foregroundColor: foreground
            ]
        )
        attachPDFButton.layer?.backgroundColor = (
            selected
                ? AIChatClaudePalette.chipSelectedBackground
                : NSColor.clear
        ).cgColor
        attachPDFButton.layer?.borderWidth = 0
        attachPDFButton.toolTip = selected
            ? "Current PDF will be uploaded with the next message"
            : "Attach the current PDF to the next message"
        attachPDFButton.setAccessibilityValue(selected ? "Selected" : "Not selected")
    }

    private func addImages(from pasteboard: NSPasteboard) -> Bool {
        var images: [(NSImage, String)] = []
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let URLs = (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
        for URL in URLs where UTType(filenameExtension: URL.pathExtension)?.conforms(to: .image) == true {
            if let image = NSImage(contentsOf: URL) {
                images.append((image, URL.lastPathComponent))
            }
        }
        if images.isEmpty {
            let encodedTypes: [(NSPasteboard.PasteboardType, String)] = [
                (.png, "Pasted image.png"),
                (.tiff, "Pasted image.tiff"),
                (NSPasteboard.PasteboardType("public.jpeg"), "Pasted image.jpg"),
                (NSPasteboard.PasteboardType("public.heic"), "Pasted image.heic")
            ]
            for (type, fileName) in encodedTypes {
                guard let data = pasteboard.data(forType: type),
                      let image = NSImage(data: data) else { continue }
                images.append((image, fileName))
                break
            }
        }
        if images.isEmpty, let image = NSImage(pasteboard: pasteboard) {
            images.append((image, "Pasted image.png"))
        }
        guard !images.isEmpty else { return false }
        let available = max(0, 4 - composerAttachments.count)
        let attachments = images.prefix(available).compactMap { image, fileName in
            AIChatImageEncoder.attachment(from: image, fileName: fileName)
        }
        guard !attachments.isEmpty else {
            setStatus("Image could not be prepared or exceeds 4 MB")
            return true
        }
        addImageAttachments(attachments)
        return true
    }

    private func addImageAttachments(_ attachments: [AIChatImageAttachment]) {
        let remaining = max(0, 4 - composerAttachments.count)
        guard remaining > 0 else {
            setStatus("Up to 4 images can be attached to one message")
            return
        }
        composerAttachments.append(contentsOf: attachments.prefix(remaining))
        rebuildComposerAttachments()
    }

    private func rebuildComposerAttachments() {
        attachmentStack.arrangedSubviews.forEach {
            attachmentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for attachment in composerAttachments {
            let chip = AIChatImageChip(attachment: attachment, removable: true)
            chip.onRemove = { [weak self] in
                self?.composerAttachments.removeAll { $0.id == attachment.id }
                self?.rebuildComposerAttachments()
            }
            attachmentStack.addArrangedSubview(chip)
        }
        let hasAttachments = !composerAttachments.isEmpty
        attachmentScrollView.isHidden = !hasAttachments
        attachmentHeightConstraint?.constant = hasAttachments ? 58 : 0
        composerContainer.needsLayout = true
    }

    private func scrollConversationTabToVisible(_ id: String?) {
        guard let id, let button = conversationButtons[id] else { return }
        DispatchQueue.main.async {
            button.scrollToVisible(button.bounds)
        }
    }

    private func changeMessageFontSize(by delta: CGFloat) {
        applyMessageFontSize(messageFontSize + delta, persist: true, preserveScrollPosition: true)
    }

    private func applyMessageFontSize(
        _ fontSize: CGFloat,
        persist: Bool,
        preserveScrollPosition: Bool = false
    ) {
        let scrollFraction = preserveScrollPosition ? messageScrollFraction() : nil
        messageFontSize = min(24, max(11, fontSize))
        if persist {
            UserDefaults.standard.set(Double(messageFontSize), forKey: "reader.aiChatFontSize")
        }
        messageViews.values.forEach { $0.setFontSize(messageFontSize) }
        messageStack.needsLayout = true
        if let scrollFraction {
            restoreMessageScrollFraction(scrollFraction)
        } else {
            scrollToBottom()
        }
    }

    private func zoomMessageContent(by delta: CGFloat, phase: NSEvent.Phase) {
        if delta != 0 {
            applyMessageFontSize(
                messageFontSize + delta,
                persist: false,
                preserveScrollPosition: true
            )
        }
        if phase == .ended || phase == .cancelled || phase.isEmpty {
            UserDefaults.standard.set(Double(messageFontSize), forKey: "reader.aiChatFontSize")
        }
    }

    private func messageScrollFraction() -> CGFloat {
        messageStack.layoutSubtreeIfNeeded()
        let viewportHeight = messageScrollView.contentView.bounds.height
        let maximumY = max(0, messageStack.bounds.height - viewportHeight)
        guard maximumY > 0 else { return 1 }
        return min(1, max(0, messageScrollView.contentView.bounds.minY / maximumY))
    }

    private func restoreMessageScrollFraction(_ fraction: CGFloat) {
        messageStack.layoutSubtreeIfNeeded()
        messageScrollView.layoutSubtreeIfNeeded()
        let viewportHeight = messageScrollView.contentView.bounds.height
        let maximumY = max(0, messageStack.bounds.height - viewportHeight)
        messageScrollView.contentView.scroll(to: NSPoint(
            x: messageScrollView.contentView.bounds.minX,
            y: maximumY * min(1, max(0, fraction))
        ))
        messageScrollView.reflectScrolledClipView(messageScrollView.contentView)
    }

    private func installEmptyState() {
        guard emptyStateView == nil else { return }
        let title = NSTextField(labelWithString: "Read this paper with AI")
        title.font = .systemFont(ofSize: 15, weight: .medium)
        title.textColor = .labelColor
        let detail = NSTextField(wrappingLabelWithString: "No hidden prompt or PDF pages are sent unless you select them. Use the PDF button to upload this paper once.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 3
        let stack = NSStackView(views: [title, detail])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        stack.edgeInsets = NSEdgeInsets(top: 54, left: 26, bottom: 30, right: 26)
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView = stack
        messageStack.addArrangedSubview(stack)
        stack.widthAnchor.constraint(equalTo: messageStack.widthAnchor, constant: -32).isActive = true
    }

    private func removeEmptyState() {
        guard let emptyStateView else { return }
        messageStack.removeArrangedSubview(emptyStateView)
        emptyStateView.removeFromSuperview()
        self.emptyStateView = nil
    }

    private func scrollToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            messageStack.layoutSubtreeIfNeeded()
            guard let documentView = messageScrollView.documentView else { return }
            let y = documentView.isFlipped
                ? max(0, documentView.bounds.height - messageScrollView.contentView.bounds.height)
                : 0
            messageScrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
            messageScrollView.reflectScrolledClipView(messageScrollView.contentView)
        }
    }

    @objc private func sendPressed(_ sender: Any?) { submitComposer() }
    @objc private func attachPDFPressed(_ sender: NSButton) {
        setCurrentPDFAttachmentSelected(sender.state == .on)
        setStatus(sender.state == .on
            ? "Current PDF will be uploaded once with the next message"
            : "Current PDF attachment is off")
    }
    @objc private func attachImagePressed(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Attach images"
        panel.prompt = "Attach"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let attachments = panel.urls.prefix(max(0, 4 - composerAttachments.count)).compactMap { URL in
            NSImage(contentsOf: URL).flatMap {
                AIChatImageEncoder.attachment(from: $0, fileName: URL.lastPathComponent)
            }
        }
        addImageAttachments(attachments)
    }
    @objc private func cancelPressed(_ sender: Any?) { onCancel?() }
    @objc private func configurePressed(_ sender: Any?) { onConfigure?() }
    @objc private func newConversationPressed(_ sender: Any?) { onNewConversation?() }
    @objc private func deleteConversationPressed(_ sender: Any?) { onDeleteConversation?() }
    @objc private func historyPressed(_ sender: NSButton) { onShowHistory?(sender) }
    @objc private func revealCurrentHistoryPressed(_ sender: Any?) { onRevealCurrentHistory?() }

    @objc private func decreaseFontPressed(_ sender: Any?) {
        changeMessageFontSize(by: -1)
    }

    @objc private func increaseFontPressed(_ sender: Any?) {
        changeMessageFontSize(by: 1)
    }

    @objc private func conversationChanged(_ sender: AIChatSelectionButton) {
        guard !isApplyingSelection,
              conversationIDs.contains(sender.identifierValue) else { return }
        selectedConversationID = sender.identifierValue
        conversationButtons.forEach { id, button in
            button.setSelected(id == selectedConversationID)
        }
        onSelectConversation?(sender.identifierValue)
    }

    @objc private func promptChanged(_ sender: AIChatSelectionButton) {
        guard promptTemplates.contains(where: { $0.id == sender.identifierValue }) else { return }
        let preset = AIPromptPreset(rawValue: sender.identifierValue)
        selectPromptPreset(preset)
        onPresetChange?(preset)
    }

    @objc private func managePromptsPressed(_ sender: NSButton) {
        let menu = NSMenu(title: "Prompt modes")
        let current = selectedPromptTemplate()
        let edit = NSMenuItem(
            title: "Edit \(current.name)…",
            action: #selector(editPromptPressed(_:)),
            keyEquivalent: ""
        )
        edit.target = self
        edit.representedObject = current.id
        menu.addItem(edit)
        let add = NSMenuItem(
            title: "New prompt mode…",
            action: #selector(addPromptPressed(_:)),
            keyEquivalent: ""
        )
        add.target = self
        menu.addItem(add)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 3), in: sender)
    }

    @objc private func editPromptPressed(_ sender: NSMenuItem) {
        let id = sender.representedObject as? String ?? selectedPromptPreset.rawValue
        onEditPromptTemplate?(AIPromptPreset(rawValue: id))
    }

    @objc private func addPromptPressed(_ sender: Any?) {
        onAddPromptTemplate?()
    }
}

@MainActor
private final class AIChatMessageStackView: NSStackView {
    override var isFlipped: Bool { true }
}

enum AIChatNestedScrollRouting {
    static func sendsToOuterVerticalScroll(deltaX: CGFloat, deltaY: CGFloat) -> Bool {
        abs(deltaY) > 0.01 && abs(deltaY) >= abs(deltaX)
    }
}

@MainActor
private final class AIChatMessageScrollView: NSScrollView {
    var onZoom: ((CGFloat, NSEvent.Phase) -> Void)?

    override func magnify(with event: NSEvent) {
        onZoom?(event.magnification * 8, event.phase)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 0.08 : 0.5
            onZoom?(event.scrollingDeltaY * multiplier, event.phase)
            return
        }
        super.scrollWheel(with: event)
    }
}

@MainActor
private final class AIChatSelectionButton: NSButton {
    var identifierValue = ""
    private let compact: Bool
    private var isSelectedValue = false
    private var isHovered = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String, compact: Bool = false) {
        self.compact = compact
        super.init(frame: .zero)
        self.title = title
        font = .systemFont(ofSize: compact ? 10.5 : 11.5, weight: .medium)
        setButtonType(.momentaryPushIn)
        bezelStyle = .inline
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = compact ? 6 : 7
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        let textWidth = (title as NSString).size(withAttributes: [.font: font as Any]).width
        widthAnchor.constraint(greaterThanOrEqualToConstant: ceil(textWidth) + (compact ? 16 : 22)).isActive = true
        heightAnchor.constraint(equalToConstant: compact ? 24 : 27).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSelected(_ selected: Bool) {
        isSelectedValue = selected
        updateAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        let foreground: NSColor = isSelectedValue ? AIChatClaudePalette.clay : .secondaryLabelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font ?? NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: foreground
            ]
        )
        layer?.backgroundColor = (
            isSelectedValue
                ? AIChatClaudePalette.chipSelectedBackground
                : isHovered
                    ? AIChatClaudePalette.chipHover
                    : NSColor.clear
        ).cgColor
        layer?.borderWidth = 0
    }
}

@MainActor
private final class AISidebarResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    private var previousWindowX: CGFloat?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.65).setFill()
        NSRect(x: 0, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        previousWindowX = event.locationInWindow.x
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let previousWindowX else { return }
        let currentX = event.locationInWindow.x
        self.previousWindowX = currentX
        onDrag?(currentX - previousWindowX)
    }

    override func mouseUp(with event: NSEvent) {
        previousWindowX = nil
        onDragEnded?()
        super.mouseUp(with: event)
    }
}

@MainActor
private final class AIActivityDotView: NSView {
    var color: NSColor = .systemGreen {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
    }
}

@MainActor
private final class AIChatMessageView: NSView {
    var onDelete: (() -> Void)?

    private static let compactBeijingFormatter = makeBeijingFormatter(
        dateFormat: "MM-dd HH:mm"
    )
    private static let detailedBeijingFormatter = makeBeijingFormatter(
        dateFormat: "yyyy-MM-dd HH:mm:ss '北京时间'"
    )

    private let roleBadge = NSView()
    private let roleIcon = NSImageView()
    private let roleLabel = NSTextField(labelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let bottomCopyButton = NSButton()
    private let deleteMessageButton = NSButton()
    private let actionRow = NSStackView()
    private let activityPanel = NSView()
    private let activitySpinner = NSProgressIndicator()
    private let activityDot = AIActivityDotView()
    private let activityLabel = NSTextField(labelWithString: "")
    private let contentView = AIChatRenderedContentView()
    private let card = NSView()
    private var activityHeightConstraint: NSLayoutConstraint!
    private var contentTopConstraint: NSLayoutConstraint!
    private var actionRowHeightConstraint: NSLayoutConstraint!
    private var actionRowTopConstraint: NSLayoutConstraint!
    private var actionRowVisible = false
    private let isAssistant: Bool
    private var rawContent: String

    init(message: AIChatMessage, fontSize: CGFloat) {
        let isUser = message.role == .user
        isAssistant = message.role == .assistant
        rawContent = message.content
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        // Claude style: user gets a warm neutral bubble, assistant
        // replies sit directly on the sidebar with no card chrome.
        card.layer?.borderWidth = 0
        card.layer?.backgroundColor = (
            isUser
                ? AIChatClaudePalette.userBubble
                : NSColor.clear
        ).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        roleBadge.wantsLayer = true
        roleBadge.layer?.cornerRadius = 5
        roleBadge.layer?.backgroundColor = AIChatClaudePalette.chipSelectedBackground.cgColor
        roleBadge.translatesAutoresizingMaskIntoConstraints = false

        roleIcon.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "Assistant"
        )
        roleIcon.contentTintColor = AIChatClaudePalette.clay
        roleIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        roleIcon.translatesAutoresizingMaskIntoConstraints = false
        roleBadge.addSubview(roleIcon)

        roleLabel.stringValue = "Assistant"
        roleLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        roleLabel.textColor = .tertiaryLabelColor
        roleLabel.lineBreakMode = .byTruncatingTail
        roleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        roleLabel.translatesAutoresizingMaskIntoConstraints = false

        timestampLabel.stringValue = isAssistant ? Self.beijingTimestamp(message.createdAt) : ""
        timestampLabel.font = .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
        timestampLabel.textColor = .tertiaryLabelColor
        timestampLabel.toolTip = isAssistant
            ? Self.beijingTimestamp(message.createdAt, includeYearAndSeconds: true)
            : nil
        timestampLabel.isHidden = !isAssistant
        timestampLabel.setContentHuggingPriority(.required, for: .horizontal)
        timestampLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false

        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy message")
        copyButton.bezelStyle = .texturedRounded
        copyButton.isBordered = false
        copyButton.contentTintColor = .secondaryLabelColor
        copyButton.toolTip = "Copy message"
        copyButton.target = self
        copyButton.action = #selector(copyMessage(_:))
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        configureFooterButton(
            bottomCopyButton,
            title: "Copy",
            symbol: "doc.on.doc",
            color: .secondaryLabelColor
        )
        bottomCopyButton.target = self
        bottomCopyButton.action = #selector(copyMessage(_:))
        configureFooterButton(
            deleteMessageButton,
            title: "Delete",
            symbol: "trash",
            color: .systemRed
        )
        deleteMessageButton.target = self
        deleteMessageButton.action = #selector(deleteMessage(_:))
        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10
        actionRow.addArrangedSubview(actionSpacer)
        actionRow.addArrangedSubview(bottomCopyButton)
        actionRow.addArrangedSubview(deleteMessageButton)
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        activityPanel.wantsLayer = true
        activityPanel.layer?.cornerRadius = 8
        activityPanel.layer?.cornerCurve = .continuous
        activityPanel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        activityPanel.isHidden = true
        activityPanel.translatesAutoresizingMaskIntoConstraints = false

        activitySpinner.style = .spinning
        activitySpinner.controlSize = .small
        activitySpinner.isIndeterminate = true
        activitySpinner.isDisplayedWhenStopped = false
        activitySpinner.translatesAutoresizingMaskIntoConstraints = false

        activityDot.color = .systemGreen
        activityDot.isHidden = true
        activityDot.translatesAutoresizingMaskIntoConstraints = false

        activityLabel.font = .systemFont(ofSize: 11, weight: .medium)
        activityLabel.textColor = .secondaryLabelColor
        activityLabel.lineBreakMode = .byTruncatingTail
        activityLabel.translatesAutoresizingMaskIntoConstraints = false

        activityPanel.addSubview(activitySpinner)
        activityPanel.addSubview(activityDot)
        activityPanel.addSubview(activityLabel)
        contentView.setFontSize(fontSize)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        // User bubbles show no header chrome at all.
        roleBadge.isHidden = isUser
        roleLabel.isHidden = isUser
        timestampLabel.isHidden = isUser
        copyButton.isHidden = isUser

        addSubview(card)
        card.addSubview(roleBadge)
        card.addSubview(roleLabel)
        card.addSubview(timestampLabel)
        card.addSubview(copyButton)
        card.addSubview(activityPanel)
        card.addSubview(contentView)
        card.addSubview(actionRow)
        activityHeightConstraint = activityPanel.heightAnchor.constraint(equalToConstant: 0)
        contentTopConstraint = contentView.topAnchor.constraint(equalTo: activityPanel.bottomAnchor)
        actionRowTopConstraint = actionRow.topAnchor.constraint(equalTo: contentView.bottomAnchor)
        actionRowHeightConstraint = actionRow.heightAnchor.constraint(equalToConstant: 0)
        actionRow.isHidden = true
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isUser ? 52 : 0),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: isUser ? 0 : -4),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor),
            roleBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            roleBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 11),
            roleBadge.widthAnchor.constraint(equalToConstant: 20),
            roleBadge.heightAnchor.constraint(equalToConstant: 20),
            roleIcon.centerXAnchor.constraint(equalTo: roleBadge.centerXAnchor),
            roleIcon.centerYAnchor.constraint(equalTo: roleBadge.centerYAnchor),
            roleIcon.widthAnchor.constraint(equalToConstant: 11),
            roleIcon.heightAnchor.constraint(equalToConstant: 11),
            roleLabel.centerYAnchor.constraint(equalTo: roleBadge.centerYAnchor),
            roleLabel.leadingAnchor.constraint(equalTo: roleBadge.trailingAnchor, constant: 7),
            timestampLabel.centerYAnchor.constraint(equalTo: roleBadge.centerYAnchor),
            timestampLabel.leadingAnchor.constraint(equalTo: roleLabel.trailingAnchor, constant: 7),
            timestampLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -7),
            copyButton.centerYAnchor.constraint(equalTo: roleBadge.centerYAnchor),
            copyButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -7),
            copyButton.widthAnchor.constraint(equalToConstant: 24),
            copyButton.heightAnchor.constraint(equalToConstant: 24),
            activityPanel.topAnchor.constraint(
                equalTo: isUser ? card.topAnchor : roleBadge.bottomAnchor,
                constant: isUser ? 4 : 8
            ),
            activityPanel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            activityPanel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            activityHeightConstraint,
            activitySpinner.leadingAnchor.constraint(equalTo: activityPanel.leadingAnchor, constant: 10),
            activitySpinner.centerYAnchor.constraint(equalTo: activityPanel.centerYAnchor),
            activitySpinner.widthAnchor.constraint(equalToConstant: 12),
            activitySpinner.heightAnchor.constraint(equalToConstant: 12),
            activityDot.centerXAnchor.constraint(equalTo: activitySpinner.centerXAnchor),
            activityDot.centerYAnchor.constraint(equalTo: activitySpinner.centerYAnchor),
            activityDot.widthAnchor.constraint(equalToConstant: 7),
            activityDot.heightAnchor.constraint(equalToConstant: 7),
            activityLabel.leadingAnchor.constraint(equalTo: activitySpinner.trailingAnchor, constant: 8),
            activityLabel.trailingAnchor.constraint(equalTo: activityPanel.trailingAnchor, constant: -10),
            activityLabel.centerYAnchor.constraint(equalTo: activityPanel.centerYAnchor),
            contentTopConstraint,
            contentView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            contentView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            actionRowTopConstraint,
            actionRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            actionRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            actionRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            actionRowHeightConstraint
        ])
        contentView.setImageAttachments(message.imageAttachments)
        setContent(message.content, renderMarkdown: message.role == .assistant)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        setActionRowVisible(true)
    }

    override func mouseExited(with event: NSEvent) {
        setActionRowVisible(false)
    }

    private func setActionRowVisible(_ visible: Bool) {
        guard visible != actionRowVisible else { return }
        actionRowVisible = visible
        actionRow.isHidden = !visible
        actionRowHeightConstraint.constant = visible ? 22 : 0
        actionRowTopConstraint.constant = visible ? 8 : 0
    }

    private static func beijingTimestamp(
        _ date: Date,
        includeYearAndSeconds: Bool = false
    ) -> String {
        let formatter = includeYearAndSeconds
            ? detailedBeijingFormatter
            : compactBeijingFormatter
        return formatter.string(from: date)
    }

    private static func makeBeijingFormatter(dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = dateFormat
        return formatter
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: String, renderMarkdown: Bool) {
        rawContent = content
        bottomCopyButton.isEnabled = !content.isEmpty
        if !activityPanel.isHidden {
            contentTopConstraint.constant = content.isEmpty ? 0 : 10
        }
        contentView.setContent(content, renderMarkdown: renderMarkdown)
    }

    func setFontSize(_ fontSize: CGFloat) {
        contentView.setFontSize(fontSize)
    }

    func renderedTextForLayoutCheck() -> String {
        contentView.renderedTextForLayoutCheck()
    }

    func contentAcceptsFocusForLayoutCheck() -> Bool {
        contentView.acceptsFocusForLayoutCheck()
    }

    func contentContainsSelectableTextForLayoutCheck() -> Bool {
        contentView.containsSelectableTextForLayoutCheck()
    }

    func copyContentForLayoutCheck() -> Bool {
        contentView.copyFirstTextFieldForLayoutCheck()
    }

    func renderedMathLatexForLayoutCheck() -> [String] {
        contentView.renderedMathLatexForLayoutCheck()
    }

    func timestampForLayoutCheck() -> String {
        timestampLabel.stringValue
    }

    func hasScrollableDisplayMathForLayoutCheck() -> Bool {
        contentView.hasScrollableDisplayMathForLayoutCheck()
    }

    func renderedBlockCountForLayoutCheck() -> Int {
        contentView.arrangedSubviews.count
    }

    func inlineMathAttachmentCountForLayoutCheck() -> Int {
        contentView.inlineMathAttachmentCountForLayoutCheck()
    }

    func contentHasFontTraitForLayoutCheck(
        text: String,
        trait: NSFontTraitMask
    ) -> Bool {
        contentView.hasFontTraitForLayoutCheck(text: text, trait: trait)
    }

    func hasBottomActionsForLayoutCheck() -> Bool {
        bottomCopyButton.superview != nil && deleteMessageButton.superview != nil
    }

    func tableColumnWidthsForLayoutCheck() -> [CGFloat] {
        contentView.tableColumnWidthsForLayoutCheck()
    }

    func triggerDeleteForLayoutCheck() {
        deleteMessageButton.performClick(nil)
    }

    func setActivity(_ phase: AIChatActivityPhase, identity: String) {
        guard isAssistant else { return }
        roleLabel.stringValue = identity
        roleLabel.toolTip = identity
        activityPanel.isHidden = false
        activityHeightConstraint.constant = 32
        contentTopConstraint.constant = rawContent.isEmpty ? 0 : 10
        activityLabel.stringValue = phase.title
        activityLabel.textColor = phase == .failed ? .systemRed : .secondaryLabelColor
        activityDot.color = phase.color
        activitySpinner.isHidden = !phase.isActive
        activityDot.isHidden = phase.isActive
        deleteMessageButton.isEnabled = !phase.isActive
        if phase.isActive {
            activitySpinner.startAnimation(nil)
        } else {
            activitySpinner.stopAnimation(nil)
        }
        activityPanel.setAccessibilityLabel("Model activity")
        activityPanel.setAccessibilityValue(phase.title)
    }

    @objc private func copyMessage(_ sender: NSButton) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(rawContent, forType: .string)
        sender.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak sender] in
            sender?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy message")
        }
    }

    @objc private func deleteMessage(_ sender: NSButton) {
        onDelete?()
    }

    private func configureFooterButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        color: NSColor
    ) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 10.5, weight: .medium)
        button.bezelStyle = .inline
        button.isBordered = false
        button.contentTintColor = color
        button.toolTip = "\(title) message"
        button.setAccessibilityLabel("\(title) message")
    }
}

@MainActor
private final class AIChatRenderedContentView: NSStackView {
    private var rawContent = ""
    private var rendersMarkdown = false
    private var bodyFontSize: CGFloat = 13.5
    private var imageAttachments: [AIChatImageAttachment] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .leading
        spacing = 5
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ content: String, renderMarkdown: Bool) {
        rawContent = content
        rendersMarkdown = renderMarkdown
        render()
    }

    func setImageAttachments(_ attachments: [AIChatImageAttachment]) {
        imageAttachments = attachments
        render()
    }

    func setFontSize(_ fontSize: CGFloat) {
        bodyFontSize = min(24, max(11, fontSize))
        render()
    }

    func renderedTextForLayoutCheck() -> String {
        textFields(in: self).map(\.stringValue).joined(separator: "\n")
    }

    func acceptsFocusForLayoutCheck() -> Bool {
        textFields(in: self).contains { $0.acceptsFirstResponder }
    }

    func containsSelectableTextForLayoutCheck() -> Bool {
        textFields(in: self).contains { $0.isSelectable }
    }

    func copyFirstTextFieldForLayoutCheck() -> Bool {
        guard let field = textFields(in: self).first,
              let window,
              window.makeFirstResponder(field) else { return false }
        field.selectText(nil)
        guard let editor = field.currentEditor() else { return false }
        editor.selectAll(nil)
        editor.copy(nil)
        return true
    }

    func renderedMathLatexForLayoutCheck() -> [String] {
        mathLabels(in: self).compactMap(\.latex)
    }

    func hasScrollableDisplayMathForLayoutCheck() -> Bool {
        mathLabels(in: self).contains { label in
            var ancestor = label.superview
            while let current = ancestor {
                if let scrollView = current as? NSScrollView,
                   scrollView.hasHorizontalScroller {
                    return true
                }
                ancestor = current.superview
            }
            return false
        }
    }

    func inlineMathAttachmentCountForLayoutCheck() -> Int {
        textFields(in: self).reduce(into: 0) { count, field in
            let value = field.attributedStringValue
            value.enumerateAttribute(
                .attachment,
                in: NSRange(location: 0, length: value.length)
            ) { attachment, _, _ in
                if attachment != nil { count += 1 }
            }
        }
    }

    func hasFontTraitForLayoutCheck(text: String, trait: NSFontTraitMask) -> Bool {
        textFields(in: self).contains { field in
            let value = field.attributedStringValue
            let range = (value.string as NSString).range(of: text)
            guard range.location != NSNotFound,
                  let font = value.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont else {
                return false
            }
            return NSFontManager.shared.traits(of: font).contains(trait)
        }
    }

    func tableColumnWidthsForLayoutCheck() -> [CGFloat] {
        layoutSubtreeIfNeeded()
        guard let grid = gridViews(in: self).first,
              grid.numberOfRows > 0 else { return [] }
        grid.layoutSubtreeIfNeeded()
        return (0..<grid.numberOfColumns).compactMap { columnIndex in
            grid.cell(atColumnIndex: columnIndex, rowIndex: 0).contentView?.frame.width
        }
    }

    private func textFields(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { child -> [NSTextField] in
            let own = (child as? NSTextField).map { [$0] } ?? []
            return own + textFields(in: child)
        }
    }

    private func mathLabels(in view: NSView) -> [MTMathUILabel] {
        view.subviews.flatMap { child -> [MTMathUILabel] in
            let own = (child as? MTMathUILabel).map { [$0] } ?? []
            return own + mathLabels(in: child)
        }
    }

    private func gridViews(in view: NSView) -> [NSGridView] {
        view.subviews.flatMap { child -> [NSGridView] in
            let own = (child as? NSGridView).map { [$0] } ?? []
            return own + gridViews(in: child)
        }
    }

    private func render() {
        arrangedSubviews.forEach {
            removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        if !imageAttachments.isEmpty {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 7
            for attachment in imageAttachments {
                row.addArrangedSubview(AIChatImageChip(attachment: attachment, removable: false))
            }
            addArrangedSubview(row)
        }
        guard !rawContent.isEmpty else { return }
        guard rendersMarkdown else {
            addText(rawContent, markdown: false)
            return
        }
        for block in AIChatMarkdownParser.blocks(in: rawContent) {
            add(block)
        }
    }

    private func add(_ block: AIChatMarkdownBlock) {
        switch block {
        case let .heading(level, text):
            let scale: CGFloat = switch level {
            case 1: 1.18
            case 2: 1.10
            default: 1.0
            }
            addRichContent(
                text,
                fontSize: bodyFontSize * scale,
                weight: .semibold,
                paragraphSpacing: 7
            )
        case let .paragraph(text):
            addRichContent(text)
        case let .unorderedList(items):
            let indent = listItemIndent(marker: "•")
            for item in items {
                addRichContent(item, paragraphSpacing: 2, hangingIndent: ("•", indent))
            }
        case let .orderedList(start, items):
            for (offset, item) in items.enumerated() {
                let marker = "\(start + offset)."
                addRichContent(
                    item,
                    paragraphSpacing: 2,
                    hangingIndent: (marker, listItemIndent(marker: marker))
                )
            }
        case let .blockquote(text):
            addRichContent(
                "▍  \(text)",
                color: .secondaryLabelColor,
                paragraphSpacing: 6
            )
        case let .code(language, content):
            addCodeBlock(language: language, content: content)
        case let .table(headers, rows):
            addTable(headers: headers, rows: rows)
        case .horizontalRule:
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(separator)
            separator.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
    }

    private func listItemIndent(marker: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let width = (marker as NSString).size(withAttributes: [.font: font]).width
        return (width + bodyFontSize * 0.5).rounded(.up)
    }

    private func addRichContent(
        _ content: String,
        fontSize: CGFloat? = nil,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        paragraphSpacing: CGFloat? = nil,
        hangingIndent: (marker: String, indent: CGFloat)? = nil
    ) {
        var inlineSegments: [AIMessageContentSegment] = []
        for segment in AIMessageContentParser.segments(in: content) {
            switch segment {
            case .text, .math(_, false):
                inlineSegments.append(segment)
            case let .math(latex, true):
                addInlineRichContent(
                    inlineSegments,
                    fontSize: fontSize,
                    weight: weight,
                    color: color,
                    paragraphSpacing: paragraphSpacing,
                    hangingIndent: hangingIndent
                )
                inlineSegments.removeAll(keepingCapacity: true)
                if !addMath(latex, display: true) {
                    addText(
                        "$$\(latex)$$",
                        markdown: false,
                        fontSize: fontSize,
                        weight: weight,
                        color: color,
                        paragraphSpacing: paragraphSpacing
                    )
                }
            }
        }
        addInlineRichContent(
            inlineSegments,
            fontSize: fontSize,
            weight: weight,
            color: color,
            paragraphSpacing: paragraphSpacing,
            hangingIndent: hangingIndent
        )
    }

    private func addInlineRichContent(
        _ segments: [AIMessageContentSegment],
        fontSize: CGFloat?,
        weight: NSFont.Weight,
        color: NSColor,
        paragraphSpacing: CGFloat?,
        hangingIndent: (marker: String, indent: CGFloat)? = nil
    ) {
        guard !segments.isEmpty else { return }
        let resolvedSize = fontSize ?? bodyFontSize
        var markdownSource = ""
        var mathReplacements: [(token: String, attachment: NSAttributedString)] = []
        for segment in segments {
            switch segment {
            case let .text(text):
                markdownSource += text
            case let .math(latex, false):
                if let attachment = inlineMathAttachment(
                    latex: latex,
                    fontSize: resolvedSize,
                    color: color
                ) {
                    let token = "PDFlightMath\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
                    markdownSource += token
                    mathReplacements.append((token, attachment))
                } else {
                    markdownSource += "$\(latex)$"
                }
            case .math(_, true):
                assertionFailure("Display math must be flushed before inline layout")
            }
        }
        let combined = NSMutableAttributedString(attributedString: styledText(
            markdownSource,
            markdown: true,
            fontSize: resolvedSize,
            weight: weight,
            color: color,
            paragraphSpacing: paragraphSpacing,
            hangingIndent: hangingIndent
        ))
        for replacement in mathReplacements {
            let range = (combined.string as NSString).range(of: replacement.token)
            guard range.location != NSNotFound else { continue }
            let inheritedAttributes = combined.attributes(
                at: range.location,
                effectiveRange: nil
            )
            let attachment = NSMutableAttributedString(
                attributedString: replacement.attachment
            )
            attachment.addAttributes(
                inheritedAttributes,
                range: NSRange(location: 0, length: attachment.length)
            )
            combined.replaceCharacters(in: range, with: attachment)
        }
        addAttributedText(combined)
    }

    private func addText(
        _ text: String,
        markdown: Bool,
        fontSize: CGFloat? = nil,
        weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor,
        paragraphSpacing: CGFloat? = nil
    ) {
        guard !text.isEmpty else { return }
        let resolvedSize = fontSize ?? bodyFontSize
        addAttributedText(styledText(
            text,
            markdown: markdown,
            fontSize: resolvedSize,
            weight: weight,
            color: color,
            paragraphSpacing: paragraphSpacing
        ))
    }

    private func styledText(
        _ text: String,
        markdown: Bool,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        color: NSColor,
        paragraphSpacing: CGFloat?,
        hangingIndent: (marker: String, indent: CGFloat)? = nil
    ) -> NSAttributedString {
        let resolvedSize = fontSize
        let bodyFont = NSFont.systemFont(ofSize: resolvedSize, weight: weight)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = max(2, resolvedSize * 0.26)
        paragraphStyle.paragraphSpacing = paragraphSpacing ?? max(4, resolvedSize * 0.36)
        if let hangingIndent {
            paragraphStyle.headIndent = hangingIndent.indent
            paragraphStyle.firstLineHeadIndent = 0
            paragraphStyle.tabStops = [NSTextTab(
                textAlignment: .left,
                location: hangingIndent.indent
            )]
        }
        let styled: NSMutableAttributedString
        if markdown,
           let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
           ) {
            styled = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
            styled.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(location: 0, length: styled.length)
            )
            styled.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: styled.length)
            )
            applyArgusSystemFonts(
                to: styled,
                baseSize: resolvedSize,
                baseWeight: weight
            )
        } else {
            styled = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]
            )
        }
        if let hangingIndent {
            let markerFont = NSFont.systemFont(ofSize: resolvedSize, weight: .medium)
            styled.insert(
                NSAttributedString(
                    string: "\(hangingIndent.marker)\t",
                    attributes: [.font: markerFont, .foregroundColor: NSColor.secondaryLabelColor]
                ),
                at: 0
            )
            styled.addAttribute(
                .paragraphStyle,
                value: paragraphStyle,
                range: NSRange(location: 0, length: styled.length)
            )
        }
        return styled
    }

    private func addAttributedText(_ attributed: NSAttributedString) {
        guard attributed.length > 0 else { return }
        let label = AIChatSelectableTextField(labelWithString: "")
        label.attributedStringValue = attributed
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.isSelectable = true
        label.isEditable = false
        label.allowsEditingTextAttributes = true
        label.focusRingType = .none
        label.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    private func inlineMathAttachment(
        latex: String,
        fontSize: CGFloat,
        color: NSColor
    ) -> NSAttributedString? {
        let label = MTMathUILabel()
        label.latex = IOSMathLatexCompatibility.renderable(latex)
        guard label.error == nil else { return nil }
        label.fontSize = fontSize + 0.5
        label.mode = .text
        label.textColor = color
        label.textAlignment = .left
        label.displayErrorInline = false

        let intrinsic = label.intrinsicContentSize
        guard intrinsic.width > 0, intrinsic.height > 0 else { return nil }
        let imageSize = NSSize(
            width: ceil(intrinsic.width) + 2,
            height: ceil(intrinsic.height) + 2
        )
        label.frame = NSRect(origin: .zero, size: imageSize)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            label.displayIgnoringOpacity(label.bounds, in: context)
            return true
        }
        image.accessibilityDescription = latex
        let attachment = NSTextAttachment()
        attachment.image = image
        let bodyFont = NSFont.systemFont(ofSize: fontSize)
        attachment.bounds = NSRect(
            x: 0,
            y: floor((bodyFont.capHeight - imageSize.height) / 2),
            width: imageSize.width,
            height: imageSize.height
        )
        return NSAttributedString(attachment: attachment)
    }

    private func applyArgusSystemFonts(
        to value: NSMutableAttributedString,
        baseSize: CGFloat,
        baseWeight: NSFont.Weight
    ) {
        let intentKey = NSAttributedString.Key("NSInlinePresentationIntent")
        let fullRange = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(intentKey, in: fullRange) { intent, range, _ in
            let rawValue = (intent as? NSNumber)?.intValue ?? 0
            let isItalic = rawValue & 1 != 0
            let isStrong = rawValue & 2 != 0
            let isCode = rawValue & 4 != 0
            var font = isCode
                ? NSFont.monospacedSystemFont(ofSize: baseSize * 0.90, weight: .regular)
                : NSFont.systemFont(ofSize: baseSize, weight: isStrong ? .semibold : baseWeight)
            if isItalic,
               let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) as NSFont? {
                font = italic
            }
            value.addAttribute(.font, value: font, range: range)
            if isCode {
                value.addAttribute(
                    .backgroundColor,
                    value: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
                    range: range
                )
            }
        }
        value.enumerateAttribute(.link, in: fullRange) { link, range, _ in
            guard link != nil else { return }
            value.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: range)
        }
    }

    private func addCodeBlock(language: String?, content: String) {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.82).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = AIChatSelectableTextField(wrappingLabelWithString: content)
        label.font = .monospacedSystemFont(ofSize: bodyFontSize * 0.90, weight: .regular)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byCharWrapping
        label.isSelectable = true
        label.isEditable = false
        label.focusRingType = .none
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: language == nil ? 9 : 21),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -9)
        ])
        if let language {
            let languageLabel = AIChatSelectableTextField(labelWithString: language.uppercased())
            languageLabel.font = .systemFont(ofSize: 9, weight: .semibold)
            languageLabel.textColor = .tertiaryLabelColor
            languageLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(languageLabel)
            NSLayoutConstraint.activate([
                languageLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
                languageLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10)
            ])
        }
    }

    private func addTable(headers: [String], rows: [[String]]) {
        let allRows = [headers] + rows
        guard !headers.isEmpty else { return }
        let columns = headers.count
        let cells: [[NSView]] = allRows.enumerated().map { rowIndex, row in
            (0..<columns).map { columnIndex in
                let text = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let label = AIChatSelectableTextField(labelWithString: "")
                label.attributedStringValue = styledText(
                    text,
                    markdown: true,
                    fontSize: bodyFontSize * 0.90,
                    weight: rowIndex == 0 ? .semibold : .regular,
                    color: .labelColor,
                    paragraphSpacing: 0
                )
                label.textColor = .labelColor
                label.maximumNumberOfLines = 0
                label.lineBreakMode = .byWordWrapping
                label.isSelectable = true
                label.isEditable = false
                label.allowsEditingTextAttributes = true
                label.focusRingType = .none
                return label
            }
        }
        let grid = AIChatTableGridView(views: cells)
        grid.rowSpacing = 6
        grid.columnSpacing = 12
        grid.xPlacement = .fill
        grid.yPlacement = .top
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 7
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.56).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 9),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -9),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8)
        ])
    }

    @discardableResult
    private func addMath(_ latex: String, display: Bool) -> Bool {
        let label = MTMathUILabel()
        label.latex = IOSMathLatexCompatibility.renderable(latex)
        guard label.error == nil else { return false }
        label.fontSize = display ? bodyFontSize + 2.5 : bodyFontSize + 0.5
        label.mode = display ? .display : .text
        label.textColor = .labelColor
        label.textAlignment = display ? .center : .left
        label.displayErrorInline = true
        if display {
            let scrollView = AIChatDisplayMathScrollView(mathLabel: label)
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(scrollView)
            scrollView.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            scrollView.heightAnchor.constraint(
                equalToConstant: max(30, ceil(label.intrinsicContentSize.height) + 10)
            ).isActive = true
        } else {
            label.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            label.heightAnchor.constraint(
                greaterThanOrEqualToConstant: max(24, label.intrinsicContentSize.height + 4)
            ).isActive = true
        }
        return true
    }
}

@MainActor
private final class AIChatDisplayMathScrollView: NSScrollView {
    private let mathLabel: MTMathUILabel
    private let formulaSize: NSSize
    private let mathDocument = NSView()

    init(mathLabel: MTMathUILabel) {
        self.mathLabel = mathLabel
        formulaSize = mathLabel.intrinsicContentSize
        super.init(frame: .zero)
        borderType = .noBorder
        drawsBackground = false
        hasHorizontalScroller = true
        hasVerticalScroller = false
        autohidesScrollers = true
        scrollerStyle = .overlay
        horizontalScrollElasticity = .automatic
        verticalScrollElasticity = .none
        mathLabel.translatesAutoresizingMaskIntoConstraints = true
        mathDocument.addSubview(mathLabel)
        documentView = mathDocument
        setAccessibilityLabel("Scrollable display equation")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func scrollWheel(with event: NSEvent) {
        if AIChatNestedScrollRouting.sendsToOuterVerticalScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY
        ), let outerVerticalScrollView {
            outerVerticalScrollView.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()
        let viewportSize = contentView.bounds.size
        let documentWidth = max(viewportSize.width, ceil(formulaSize.width) + 16)
        let documentHeight = max(viewportSize.height, ceil(formulaSize.height) + 8)
        mathDocument.frame = NSRect(
            x: 0,
            y: 0,
            width: documentWidth,
            height: documentHeight
        )
        mathLabel.frame = NSRect(
            x: max(8, (documentWidth - formulaSize.width) / 2),
            y: max(4, (documentHeight - formulaSize.height) / 2),
            width: ceil(formulaSize.width),
            height: ceil(formulaSize.height)
        )
    }

    private var outerVerticalScrollView: NSScrollView? {
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? NSScrollView,
               scrollView !== self,
               scrollView.hasVerticalScroller {
                return scrollView
            }
            ancestor = view.superview
        }
        return nil
    }
}

@MainActor
private final class AIChatSelectableTextField: NSTextField {
    override var acceptsFirstResponder: Bool {
        isSelectable || isEditable
    }
}

@MainActor
private final class AIQueuedSubmissionView: NSView {
    var onRemove: (() -> Void)?

    private let removeButton = NSButton()

    init(submission: AIChatSubmission, position: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let positionLabel = NSTextField(labelWithString: "\(position)")
        positionLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.alignment = .center
        positionLabel.wantsLayer = true
        positionLabel.layer?.cornerRadius = 8
        positionLabel.layer?.backgroundColor = NSColor.separatorColor
            .withAlphaComponent(0.35).cgColor
        positionLabel.translatesAutoresizingMaskIntoConstraints = false

        let trimmedQuestion = submission.question
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let question = trimmedQuestion.isEmpty
            ? (submission.includeCurrentPDF ? "PDF message" : "Image message")
            : trimmedQuestion
        let imageSuffix = submission.imageAttachments.isEmpty
            ? ""
            : " · \(submission.imageAttachments.count) image\(submission.imageAttachments.count == 1 ? "" : "s")"
        let pdfSuffix = submission.includeCurrentPDF ? " · PDF" : ""
        let summaryLabel = NSTextField(labelWithString: question + imageSuffix + pdfSuffix)
        summaryLabel.font = .systemFont(ofSize: 11.5)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.maximumNumberOfLines = 1
        summaryLabel.toolTip = question + imageSuffix + pdfSuffix
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        removeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: "Remove queued message"
        )
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.toolTip = "Remove from queue"
        removeButton.target = self
        removeButton.action = #selector(removePressed(_:))
        removeButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(positionLabel)
        addSubview(summaryLabel)
        addSubview(removeButton)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            positionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            positionLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            positionLabel.widthAnchor.constraint(equalToConstant: 17),
            positionLabel.heightAnchor.constraint(equalToConstant: 17),
            summaryLabel.leadingAnchor.constraint(equalTo: positionLabel.trailingAnchor, constant: 7),
            summaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.leadingAnchor.constraint(equalTo: summaryLabel.trailingAnchor, constant: 5),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 22),
            removeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func removePressed(_ sender: Any?) {
        onRemove?()
    }
}

@MainActor
private final class AIChatTableGridView: NSGridView {
    override func layout() {
        let spacingWidth = CGFloat(max(0, numberOfColumns - 1)) * columnSpacing
        let availableWidth = max(0, bounds.width - spacingWidth)
        if numberOfColumns > 0, availableWidth > 0 {
            let columnWidth = floor(availableWidth / CGFloat(numberOfColumns))
            for columnIndex in 0..<numberOfColumns {
                column(at: columnIndex).width = columnWidth
            }
        }
        super.layout()
    }
}

@MainActor
private final class AIChatComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onFocusChange: (() -> Void)?
    var onPasteboardImages: ((NSPasteboard) -> Bool)?
    var pasteboardProvider: () -> NSPasteboard = { .general }
    var placeholderString = "" {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        onFocusChange?()
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        onFocusChange?()
        return resigned
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if isEditable {
            window?.makeFirstResponder(self)
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.placeholderTextColor
        ]
        NSString(string: placeholderString).draw(
            at: NSPoint(x: textContainerInset.width + 1, y: textContainerInset.height),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36,
           !event.modifierFlags.contains(.shift),
           !event.modifierFlags.contains(.option) {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if relevantModifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           onPasteboardImages?(pasteboardProvider()) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPasteboardImages?(pasteboardProvider()) == true { return }
        super.paste(sender)
    }

    func performPasteKeyEquivalentForLayoutCheck(from pasteboard: NSPasteboard) -> Bool {
        let previousProvider = pasteboardProvider
        pasteboardProvider = { pasteboard }
        defer { pasteboardProvider = previousProvider }
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "v",
            charactersIgnoringModifiers: "v",
            isARepeat: false,
            keyCode: 9
        ) else { return false }
        return performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard onPasteboardImages != nil,
              sender.draggingPasteboard.availableType(from: [.fileURL, .png, .tiff]) != nil else {
            return super.draggingEntered(sender)
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if onPasteboardImages?(sender.draggingPasteboard) == true { return true }
        return super.performDragOperation(sender)
    }
}

@MainActor
private final class AIChatImageChip: NSView {
    var onRemove: (() -> Void)?
    private let removeButton = NSButton()

    init(attachment: AIChatImageAttachment, removable: Bool) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = NSImage(data: attachment.data)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.toolTip = attachment.fileName
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove image")
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removePressed(_:))
        removeButton.isHidden = !removable
        removeButton.toolTip = "Remove image"
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 54),
            heightAnchor.constraint(equalToConstant: 54),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: -3),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 3),
            removeButton.widthAnchor.constraint(equalToConstant: 18),
            removeButton.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func removePressed(_ sender: Any?) {
        onRemove?()
    }
}

@MainActor
private enum AIChatImageEncoder {
    static func attachment(from image: NSImage, fileName: String) -> AIChatImageAttachment? {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(1, 1_600 / max(sourceSize.width, sourceSize.height))
        let width = max(1, Int((sourceSize.width * scale).rounded()))
        let height = max(1, Int((sourceSize.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        if let PNG = bitmap.representation(using: .png, properties: [:]), PNG.count <= 4_000_000 {
            return AIChatImageAttachment(fileName: normalizedName(fileName, extension: "png"), mimeType: "image/png", data: PNG)
        }
        guard let JPEG = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.82]),
              JPEG.count <= 4_000_000 else { return nil }
        return AIChatImageAttachment(fileName: normalizedName(fileName, extension: "jpg"), mimeType: "image/jpeg", data: JPEG)
    }

    private static func normalizedName(_ fileName: String, extension fileExtension: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return "\(stem.isEmpty ? "Image" : stem).\(fileExtension)"
    }
}
