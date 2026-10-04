import AppKit
import CoreGraphics
import PDFlightAI
import PDFlightCore
import PDFlightMuPDF

enum ReaderPageKeyAction: Equatable {
    case previous
    case next
    case highlightSelection
}

enum ReaderPageKeyRouting {
    static func action(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        isEditingText: Bool
    ) -> ReaderPageKeyAction? {
        guard !isEditingText,
              modifiers.intersection([.command, .option, .control, .shift]).isEmpty else {
            return nil
        }
        switch keyCode {
        case 14: return .highlightSelection
        case 38: return .next        // j
        case 40: return .previous    // k
        case 123: return .previous
        case 124: return .next
        default: return nil
        }
    }
}

enum GoogleScholarLinkBuilder {
    static func paperSearchURL(fileNameOrDisplayTitle: String) -> URL? {
        let title = PaperLibraryPaper.automaticDisplayAlias(for: fileNameOrDisplayTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "scholar.google.com"
        components.path = "/scholar"
        components.queryItems = [
            URLQueryItem(name: "hl", value: "zh-CN"),
            URLQueryItem(name: "q", value: "\"\(title)\"")
        ]
        return components.url
    }
}

@MainActor
private final class ReaderWindow: NSWindow {
    var onPageKeyAction: ((ReaderPageKeyAction) -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = ReaderPageKeyRouting.action(
            keyCode: event.keyCode,
            modifiers: event.modifierFlags,
            isEditingText: firstResponder is NSTextView
           ) {
            onPageKeyAction?(action)
            return
        }
        super.sendEvent(event)
    }
}

private enum HorizontalScrollBehavior {
    case preserve
    case useDestination
}

private extension Notification.Name {
    static let readerWorkspaceLayoutDidChange = Notification.Name(
        "PDFlightReaderWorkspaceLayoutDidChange"
    )
}

@MainActor
enum ReaderNavigationSidebarSizing {
    static let minimumWidth: CGFloat = 160
    static let defaultWidth: CGFloat = 240

    static func flexibleConstraints(
        for view: NSView,
        coordinator: ReaderWorkspaceLayoutCoordinator = .shared
    ) -> [NSLayoutConstraint] {
        [
            view.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth),
            coordinator.bindNavigationSidebar(view)
        ]
    }
}

@MainActor
final class ReaderWorkspaceLayoutCoordinator {
    static let shared = ReaderWorkspaceLayoutCoordinator()

    static let minimumAISidebarWidth: CGFloat = 120
    static let defaultAISidebarWidth: CGFloat = 340

    private final class WeakConstraint {
        weak var value: NSLayoutConstraint?
        let pane: Pane

        init(_ value: NSLayoutConstraint, pane: Pane) {
            self.value = value
            self.pane = pane
        }
    }

    private enum Pane: Equatable {
        case navigation
        case AI
    }

    private let defaults: UserDefaults
    private var bindings: [WeakConstraint] = []
    private(set) var navigationWidth: CGFloat
    private(set) var aiWidth: CGFloat
    private(set) var navigationVisible: Bool
    private(set) var aiVisible: Bool
    private(set) var navigationMode: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedNavigationWidth = defaults.double(forKey: "reader.navigationSidebarWidth")
        navigationWidth = storedNavigationWidth.isFinite
            && storedNavigationWidth >= Double(ReaderNavigationSidebarSizing.minimumWidth)
            ? CGFloat(storedNavigationWidth)
            : ReaderNavigationSidebarSizing.defaultWidth
        let storedAIWidth = defaults.double(forKey: "reader.aiSidebarWidth")
        aiWidth = storedAIWidth.isFinite
            && storedAIWidth >= Double(Self.minimumAISidebarWidth)
            ? CGFloat(storedAIWidth)
            : Self.defaultAISidebarWidth
        navigationVisible = defaults.object(forKey: "reader.navigationSidebarVisible") as? Bool
            ?? true
        aiVisible = defaults.object(forKey: "reader.aiSidebarVisible") as? Bool
            ?? true
        let storedNavigationMode = defaults.integer(forKey: "reader.navigationSidebarMode")
        navigationMode = storedNavigationMode == 1 ? 1 : 0
    }

    func bindNavigationSidebar(_ view: NSView) -> NSLayoutConstraint {
        let constraint = view.widthAnchor.constraint(equalToConstant: navigationWidth)
        bindings.append(WeakConstraint(constraint, pane: .navigation))
        return constraint
    }

    func bindAISidebar(_ view: NSView) -> NSLayoutConstraint {
        let constraint = view.widthAnchor.constraint(equalToConstant: aiWidth)
        bindings.append(WeakConstraint(constraint, pane: .AI))
        return constraint
    }

    func setNavigationWidth(
        _ requestedWidth: CGFloat,
        source: AnyObject? = nil,
        broadcast: Bool = true
    ) {
        let normalized = max(ReaderNavigationSidebarSizing.minimumWidth, requestedWidth)
        guard normalized.isFinite else { return }
        navigationWidth = normalized
        defaults.set(Double(normalized), forKey: "reader.navigationSidebarWidth")
        updateBindings(for: .navigation, width: normalized)
        notify(source: source, broadcast: broadcast)
    }

    func setAIWidth(
        _ requestedWidth: CGFloat,
        source: AnyObject? = nil,
        broadcast: Bool = true
    ) {
        let normalized = max(Self.minimumAISidebarWidth, requestedWidth)
        guard normalized.isFinite else { return }
        aiWidth = normalized
        defaults.set(Double(normalized), forKey: "reader.aiSidebarWidth")
        updateBindings(for: .AI, width: normalized)
        notify(source: source, broadcast: broadcast)
    }

    func setNavigationVisible(
        _ visible: Bool,
        source: AnyObject? = nil,
        broadcast: Bool = true
    ) {
        navigationVisible = visible
        defaults.set(visible, forKey: "reader.navigationSidebarVisible")
        notify(source: source, broadcast: broadcast)
    }

    func setAIVisible(
        _ visible: Bool,
        source: AnyObject? = nil,
        broadcast: Bool = true
    ) {
        aiVisible = visible
        defaults.set(visible, forKey: "reader.aiSidebarVisible")
        notify(source: source, broadcast: broadcast)
    }

    /// 0 = Library, 1 = Outline. Persisted so the active sidebar survives restarts.
    func setNavigationMode(
        _ mode: Int,
        source: AnyObject? = nil,
        broadcast: Bool = true
    ) {
        navigationMode = mode == 1 ? 1 : 0
        defaults.set(navigationMode, forKey: "reader.navigationSidebarMode")
        notify(source: source, broadcast: broadcast)
    }

    private func updateBindings(for pane: Pane, width: CGFloat) {
        bindings = bindings.filter { binding in
            guard let constraint = binding.value else { return false }
            if binding.pane == pane { constraint.constant = width }
            return true
        }
    }

    private func notify(source: AnyObject?, broadcast: Bool) {
        guard broadcast else { return }
        NotificationCenter.default.post(
            name: .readerWorkspaceLayoutDidChange,
            object: source
        )
    }
}

private final class AIHistoryMenuSelection: NSObject {
    let documentPath: String
    let conversationID: String

    init(documentPath: String, conversationID: String) {
        self.documentPath = documentPath
        self.conversationID = conversationID
    }
}

enum ReaderSidebarResizePhase {
    case live
    case ended
}

enum ReaderSidebarResizeWorkPolicy {
    static func persistsSharedWidth(during phase: ReaderSidebarResizePhase) -> Bool {
        phase == .ended
    }

    static func relayoutsDocument(during phase: ReaderSidebarResizePhase) -> Bool {
        phase == .ended
    }
}

@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, PageViewDelegate, NSSplitViewDelegate {
    var onClose: (() -> Void)?
    var onActivate: (() -> Void)?
    var onNavigateAIHistory: ((URL, String) -> Void)?
    var onOpenPaperFromLibrary: ((URL) -> Void)?

    let documentURL: URL
    private let engine: MuPDFDocument
    private let readingPositionStore: ReadingPositionStore
    private let paperLibraryStore: PaperLibraryStore
    private let aiChatHistoryStore: AIChatHistoryStore
    private let aiPromptTemplateStore: AIPromptTemplateStore
    private let aiConfigurationStore: AIConfigurationStore
    private let aiClient = OpenAICompatibleClient()
    private let scheduler: RenderScheduler
    private let pageCount: Int
    private let scrollView = NSScrollView()
    private let canvasView = DocumentCanvasView()
    private let documentPane = NSView()
    private let selectionActionBar = PDFSelectionActionBar(frame: .zero)
    private let contentSplitView = NSSplitView()
    private let navigationSidebar: ReaderNavigationSidebarView
    private let aiSidebar = AIChatSidebarView()
    private let pageLabel = NSTextField(labelWithString: "—")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let searchField = NSSearchField()
    private let searchLabel = NSTextField(labelWithString: "")
    private let highlightButton = NSButton()
    private let noteButton = NSButton()
    private let outlineButton = NSButton()
    private let aiButton = NSButton()
    private var pages: [DocumentPage] = []
    private var currentPage = 0
    private var zoom = 1.0
    /// Beyond these caps pages are rendered once at the capped scale and
    /// upscaled by the view, instead of allocating giant bitmaps per zoom
    /// level (a 8x Retina render of one A4 page is ~500 MB of VRAM).
    private static let maxRenderPixels: Double = 25_000_000
    private static let maxRenderDimension: Double = 8192
    /// Whether the host window was full screen when the app last quit.
    static let windowFullScreenDefaultsKey = "reader.windowFullScreen"
    /// Windowed frame persisted manually; shared autosave names break
    /// once tabbed windows all claim the same name.
    static let windowFrameDefaultsKey = "reader.windowFrame"
    private var tool: ReaderTool = .select
    private var navigationHistory: [DocumentViewportBookmark] = []
    private var loadTask: Task<Void, Never>?
    private var renderTasks: [Int: Task<Void, Never>] = [:]
    private var textTasks: [Int: Task<Void, Never>] = [:]
    private var renderTokens: [Int: UUID] = [:]
    private var textTokens: [Int: UUID] = [:]
    private var searchTask: Task<Void, Never>?
    private var suspensionTask: Task<Void, Never>?
    private var readingPositionSaveTask: Task<Void, Never>?
    private var searchResults: [DocumentSearchHit] = []
    private var activeSearchIndex: Int?
    private var completedSearchQuery: String?
    private var renderGeneration = 0
    private var shouldFitInitialPage = true
    private var isSuspended = false
    private var suspensionToken = UUID()
    private var closingAfterSave = false
    private var editState: UUID
    private var savedEditState: UUID
    private var undoEditStates: [UUID] = []
    private var magnificationAnchor: DocumentViewportZoomAnchor?
    private var isApplyingZoomLayout = false
    private var hasFinishedInitialLoad = false
    private var outlineWidthConstraints: [NSLayoutConstraint] = []
    private var isApplyingNavigationSidebarLayout = false
    private let workspaceLayoutCoordinator = ReaderWorkspaceLayoutCoordinator.shared
    private var aiMessages: [AIChatMessage] = []
    private var aiHistory: AIPaperChatHistory?
    private var aiTask: Task<Void, Never>?
    private var activeAIPlaceholderID: String?
    private var aiHistorySaveTask: Task<Void, Never>?
    private var aiHistoryLoaded = false
    private var aiSubmissionQueue = AIChatSubmissionQueue()
    private var pendingAIConversationID: String?
    private var aiPromptTemplates = AIPromptTemplate.defaults
    private var aiConversationGeneration = 0
    private var splitResizeAnchor: DocumentViewportZoomAnchor?
    private var isApplyingAISidebarLayout = false
    private var aiSidebarWidthConstraint: NSLayoutConstraint?
    private var isResizingAISidebar = false
    private var aiSidebarResizeAnchor: DocumentViewportZoomAnchor?
    private weak var activeSelectionPageView: PageView?

    init(
        url: URL,
        engine: MuPDFDocument,
        readingPositionStore: ReadingPositionStore,
        paperLibraryStore: PaperLibraryStore,
        aiChatHistoryStore: AIChatHistoryStore,
        aiPromptTemplateStore: AIPromptTemplateStore,
        aiConfigurationStore: AIConfigurationStore
    ) {
        let initialEditState = UUID()
        self.documentURL = url
        self.engine = engine
        self.readingPositionStore = readingPositionStore
        self.paperLibraryStore = paperLibraryStore
        self.navigationSidebar = ReaderNavigationSidebarView(store: paperLibraryStore)
        self.aiChatHistoryStore = aiChatHistoryStore
        self.aiPromptTemplateStore = aiPromptTemplateStore
        self.aiConfigurationStore = aiConfigurationStore
        self.pageCount = engine.pageCount
        self.editState = initialEditState
        self.savedEditState = initialEditState
        self.scheduler = RenderScheduler(byteLimit: 12 * 1_024 * 1_024) { request in
            try await engine.render(request)
        }

        let window = ReaderWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.minSize = NSSize(width: 620, height: 400)
        if let stored = UserDefaults.standard.string(
            forKey: ReaderWindowController.windowFrameDefaultsKey
        ) {
            let rect = NSRectFromString(stored)
            let onScreen = NSScreen.screens.contains {
                !$0.visibleFrame.intersection(rect).isEmpty
            }
            if onScreen, rect.width >= window.minSize.width,
               rect.height >= window.minSize.height {
                window.setFrame(rect, display: false)
            }
        }

        super.init(window: window)
        window.onPageKeyAction = { [weak self] action in
            switch action {
            case .previous: self?.previousPage(nil)
            case .next: self?.nextPage(nil)
            case .highlightSelection: self?.highlightSelectionFromKey()
            }
        }
        window.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspaceLayoutChanged(_:)),
            name: .readerWorkspaceLayoutDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(aiReplyGestureZoomPreferenceChanged(_:)),
            name: .aiReplyGestureZoomPreferenceDidChange,
            object: nil
        )
        configureContent()
        loadAIPromptTemplates()
        loadAIHistory()
        loadDocument()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        loadTask?.cancel()
        renderTasks.values.forEach { $0.cancel() }
        textTasks.values.forEach { $0.cancel() }
        searchTask?.cancel()
        suspensionTask?.cancel()
        readingPositionSaveTask?.cancel()
        aiTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
    }

    @objc func previousPage(_ sender: Any?) {
        navigate(to: currentPage - 1)
    }

    @objc func nextPage(_ sender: Any?) {
        navigate(to: currentPage + 1)
    }

    @objc func goToPage(_ sender: Any?) {
        guard pageCount > 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Go to Page"
        alert.informativeText = "Enter a page number (1–\(pageCount)):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.stringValue = "\(currentPage + 1)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn,
              let page = Int(field.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...pageCount).contains(page) else { return }
        navigate(to: page - 1)
    }

    @objc func goBack(_ sender: Any?) {
        guard let location = navigationHistory.popLast() else {
            NSSound.beep()
            return
        }
        guard canvasView.pageViews.indices.contains(location.pageIndex) else { return }
        let pageFrame = canvasView.pageViews[location.pageIndex].frame
        let restoredOrigin = location.restoredViewportOrigin(
            pageOrigin: PagePoint(x: pageFrame.minX, y: pageFrame.minY),
            zoom: zoom
        )
        scroll(to: location.pageIndex, viewportOrigin: restoredOrigin)
    }

    @objc func zoomIn(_ sender: Any?) {
        setZoom(zoom * 1.2)
    }

    @objc func zoomOut(_ sender: Any?) {
        setZoom(zoom / 1.2)
    }

    @objc func toggleOutline(_ sender: Any?) {
        setOutlineVisible(navigationSidebar.isHidden)
    }

    @objc func toggleAI(_ sender: Any?) {
        setAIVisible(aiSidebar.isHidden)
        if !aiSidebar.isHidden {
            if let selectedText = selectedPDFText() {
                aiSidebar.prefill("Explain the following selected text:\n\n\(selectedText)")
            }
            aiSidebar.focusComposer()
        }
    }

    var hasCopyablePDFSelection: Bool {
        selectedPDFText() != nil
    }

    @objc func configureAI(_ sender: Any?) {
        _ = showAISettings()
    }

    @objc func fitWidth(_ sender: Any?) {
        guard pages.indices.contains(currentPage) else { return }
        let availableWidth = max(120, scrollView.contentSize.width - 48)
        setZoom(availableWidth / pages[currentPage].width)
    }

    /// Bare-E shortcut: silently no-ops when nothing is selected, unlike
    /// the menu item which beeps to explain why nothing happened.
    private func highlightSelectionFromKey() {
        guard canvasView.pageViews.contains(where: { $0.textSelection != nil }) else { return }
        highlightSelection(nil)
    }

    @objc func highlightSelection(_ sender: Any?) {
        guard let pageView = canvasView.pageViews.first(where: { $0.textSelection != nil }),
              let pageIndex = pageView.page?.index,
              let selection = pageView.textSelection else {
            NSSound.beep()
            return
        }

        Task { [weak self, weak pageView] in
            guard let self else { return }
            do {
                try await engine.add(.highlight(
                    pageIndex: pageIndex,
                    rects: selection.rects,
                    contents: nil
                ))
                await scheduler.invalidate(pageIndex: pageIndex)
                recordAnnotationAdded()
                pageView?.clearSelection()
                // Keep the old image on screen until the re-rendered page
                // arrives; clearing it first flashes a blank frame.
                requestRender(for: pageIndex, replacingExistingImage: true)
            } catch {
                present(error: error, title: "Could not add highlight")
            }
        }
    }

    @objc func toggleNote(_ sender: Any?) {
        setTool(tool == .note ? .select : .note)
    }

    @objc func focusSearch(_ sender: Any?) {
        window?.makeFirstResponder(searchField)
    }

    @objc func performSearch(_ sender: Any?) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isShiftPressed = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
        switch SearchSubmissionIntent.resolve(
            query: query,
            completedQuery: completedSearchQuery,
            resultCount: searchResults.count,
            isShiftPressed: isShiftPressed
        ) {
        case .nextResult:
            nextSearchResult(sender)
            return
        case .previousResult:
            previousSearchResult(sender)
            return
        case .startSearch:
            break
        }

        searchTask?.cancel()
        clearSearchResults()
        guard !query.isEmpty else { return }

        searchLabel.stringValue = "Searching…"
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await engine.search(query)
                guard !Task.isCancelled, searchField.stringValue == query else { return }
                searchResults = results
                completedSearchQuery = query
                applySearchResults()
                if results.isEmpty {
                    searchLabel.stringValue = "No results"
                } else {
                    activeSearchIndex = 0
                    showSearchResult(at: 0)
                }
            } catch is CancellationError {
                return
            } catch {
                present(error: error, title: "Could not search PDF")
            }
        }
    }

    @objc func previousSearchResult(_ sender: Any?) {
        guard !searchResults.isEmpty else { return }
        let current = activeSearchIndex ?? 0
        showSearchResult(at: (current - 1 + searchResults.count) % searchResults.count)
    }

    @objc func nextSearchResult(_ sender: Any?) {
        guard !searchResults.isEmpty else { return }
        let current = activeSearchIndex ?? -1
        showSearchResult(at: (current + 1) % searchResults.count)
    }

    @objc func saveDocument(_ sender: Any?) {
        save(closeWhenFinished: false)
    }

    @objc func undoLastAnnotation(_ sender: Any?) {
        guard !undoEditStates.isEmpty else {
            NSSound.beep()
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let pageIndex = try await engine.undoLastAnnotation() else {
                    NSSound.beep()
                    return
                }
                editState = undoEditStates.removeLast()
                updateEditedState()
                await scheduler.invalidate(pageIndex: pageIndex)
                requestRender(for: pageIndex, replacingExistingImage: true)
            } catch {
                present(error: error, title: "Could not undo annotation")
            }
        }
    }

    @objc func copySelection(_ sender: Any?) {
        if activeSelectionPageView?.copySelection() == true {
            return
        }
        for pageView in canvasView.pageViews where pageView.copySelection() {
            return
        }
    }

    private func showSelectionActionBar(anchor: NSRect) {
        guard !documentPane.bounds.isEmpty else { return }
        selectionActionBar.frame = PDFSelectionActionBarPlacement.frame(
            anchor: anchor,
            in: documentPane.bounds,
            barSize: PDFSelectionActionBar.preferredSize
        )
        selectionActionBar.isHidden = false
    }

    private func hideSelectionActionBar() {
        selectionActionBar.isHidden = true
    }

    private func copySelectionFromActionBar() {
        guard activeSelectionPageView?.copySelection() == true else {
            NSSound.beep()
            hideSelectionActionBar()
            return
        }
        hideSelectionActionBar()
    }

    private func highlightSelectionFromActionBar() {
        hideSelectionActionBar()
        highlightSelection(nil)
    }

    private func askAIAboutSelectionFromActionBar() {
        guard let selectedText = activeSelectionPageView?.textSelection?.text
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedText.isEmpty else {
            NSSound.beep()
            hideSelectionActionBar()
            return
        }
        hideSelectionActionBar()
        setAIVisible(true)
        aiSidebar.prefill("Explain the following selected text:\n\n\(selectedText)")
        aiSidebar.focusComposer()
    }

    func pageView(_ pageView: PageView, activated link: DocumentLink) {
        hideSelectionActionBar()
        switch link.target {
        case .page(let index, let point):
        if let location = currentNavigationBookmark() {
            navigationHistory.append(location)
        }
        scroll(to: index, point: point, horizontalBehavior: .preserve)
        case .url(let url):
            NSWorkspace.shared.open(url)
        }
    }

    func pageView(
        _ pageView: PageView,
        didFinishSelecting selection: DocumentTextSelection?,
        selectionBounds: NSRect?
    ) {
        guard let selection,
              !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let selectionBounds else {
            activeSelectionPageView = nil
            hideSelectionActionBar()
            return
        }
        canvasView.pageViews
            .filter { $0 !== pageView }
            .forEach { $0.clearSelection(notifyDelegate: false) }
        activeSelectionPageView = pageView
        showSelectionActionBar(anchor: pageView.convert(selectionBounds, to: documentPane))
    }

    func pageView(
        _ pageView: PageView,
        magnifiedBy amount: CGFloat,
        phase: NSEvent.Phase
    ) {
        if phase == .began || magnificationAnchor == nil {
            magnificationAnchor = currentZoomAnchor()
        }
        let gestureEnded = phase == .ended || phase == .cancelled || phase.isEmpty
        setZoom(
            zoom * max(0.5, 1 + amount),
            anchor: magnificationAnchor,
            renderFinalImage: gestureEnded
        )
        if gestureEnded {
            magnificationAnchor = nil
        }
    }

    func pageView(_ pageView: PageView, requestedNoteAt point: PagePoint) {
        guard let pageIndex = pageView.page?.index else { return }
        let alert = NSAlert()
        alert.messageText = "Add note"
        alert.informativeText = "The note is embedded in the PDF."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "Annotation text"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let contents = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contents.isEmpty else { return }
        addAnnotation(
            .note(pageIndex: pageIndex, point: point, contents: contents),
            on: pageIndex,
            failureTitle: "Could not add note"
        )
    }

    func windowWillClose(_ notification: Notification) {
        saveReadingPosition()
        cancelPageWork()
        loadTask?.cancel()
        searchTask?.cancel()
        suspensionTask?.cancel()
        aiTask?.cancel()
        Task {
            await scheduler.removeAll()
            await engine.releaseMemory()
        }
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.isDocumentEdited, !closingAfterSave else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(documentURL.lastPathComponent)?"
        alert.informativeText = "Your annotations have not been saved."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save(closeWhenFinished: true)
            return false
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    private func persistWindowFrame() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        UserDefaults.standard.set(
            NSStringFromRect(window.frame),
            forKey: ReaderWindowController.windowFrameDefaultsKey
        )
    }

    func windowDidMove(_ notification: Notification) {
        persistWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        persistWindowFrame()
        if !aiSidebar.isHidden {
            applyAISidebarWidth(workspaceLayoutCoordinator.aiWidth)
        }
        guard !pages.isEmpty else { return }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        updateVisiblePages()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: ReaderWindowController.windowFullScreenDefaultsKey)
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: ReaderWindowController.windowFullScreenDefaultsKey)
    }

    func windowDidResignKey(_ notification: Notification) {
        saveReadingPosition()
        scheduleSuspension()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        onActivate?()
        navigationSidebar.reloadLibrary()
        suspensionTask?.cancel()
        suspensionTask = nil
        isSuspended = false
        suspensionToken = UUID()
        if !aiSidebar.isHidden {
            DispatchQueue.main.async { [weak self] in
                guard let self, !aiSidebar.isHidden else { return }
                isApplyingAISidebarLayout = true
                applyAISidebarWidth(workspaceLayoutCoordinator.aiWidth)
                window?.contentView?.layoutSubtreeIfNeeded()
                isApplyingAISidebarLayout = false
            }
        }
        updateVisiblePages()
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        guard splitView === contentSplitView else { return proposedEffectiveRect }
        if dividerIndex == 0, !navigationSidebar.isHidden {
            return .zero
        }
        if dividerIndex == 1, !aiSidebar.isHidden {
            return .zero
        }
        return drawnRect.insetBy(dx: -4, dy: 0)
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === contentSplitView,
              !isApplyingAISidebarLayout,
              !isApplyingNavigationSidebarLayout else { return }
        splitResizeAnchor = currentZoomAnchor()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
              splitView === contentSplitView,
              !isApplyingAISidebarLayout,
              !isApplyingNavigationSidebarLayout else { return }
        guard !pages.isEmpty else {
            splitResizeAnchor = nil
            return
        }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        restoreCurrentViewportCenter(from: splitResizeAnchor)
        splitResizeAnchor = nil
        updateVisiblePages()
    }

    private func configureContent() {
        guard let window else { return }

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false

        let back = makeButton(symbol: "arrow.uturn.backward", tooltip: "Back (⌘←)", action: #selector(goBack(_:)))
        let previous = makeButton(symbol: "chevron.left", tooltip: "Previous page", action: #selector(previousPage(_:)))
        let next = makeButton(symbol: "chevron.right", tooltip: "Next page", action: #selector(nextPage(_:)))
        configureToolButton(
            outlineButton,
            symbol: "sidebar.left",
            tooltip: "Toggle outline",
            action: #selector(toggleOutline(_:))
        )
        let zoomOut = makeButton(symbol: "minus.magnifyingglass", tooltip: "Zoom out", action: #selector(zoomOut(_:)))
        let fit = makeButton(symbol: "rectangle.arrowtriangle.2.inward", tooltip: "Fit width", action: #selector(fitWidth(_:)))
        let zoomIn = makeButton(symbol: "plus.magnifyingglass", tooltip: "Zoom in", action: #selector(zoomIn(_:)))
        configureButton(
            highlightButton,
            symbol: "highlighter",
            tooltip: "Highlight selection (⌘E)",
            action: #selector(highlightSelection(_:))
        )
        configureToolButton(
            noteButton,
            symbol: "note.text",
            tooltip: "Text note (N)",
            action: #selector(toggleNote(_:))
        )
        configureToolButton(
            aiButton,
            symbol: "bubble.left.and.bubble.right",
            tooltip: "Ask PDF (⇧⌘A)",
            action: #selector(toggleAI(_:))
        )
        let scholarButton = makeButton(
            symbol: "graduationcap",
            tooltip: "Find citing papers on Google Scholar",
            action: #selector(openGoogleScholarCitations(_:))
        )
        let save = makeButton(symbol: "square.and.arrow.down", tooltip: "Save", action: #selector(saveDocument(_:)))
        let previousHit = makeButton(symbol: "chevron.up", tooltip: "Previous result", action: #selector(previousSearchResult(_:)))
        let nextHit = makeButton(symbol: "chevron.down", tooltip: "Next result", action: #selector(nextSearchResult(_:)))

        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        pageLabel.alignment = .center
        pageLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        zoomLabel.textColor = .secondaryLabelColor
        searchLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        searchLabel.textColor = .secondaryLabelColor
        searchLabel.alignment = .right
        searchLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        searchField.placeholderString = "Search PDF"
        searchField.target = self
        searchField.action = #selector(performSearch(_:))
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let searchControls = NSStackView(views: [searchField, searchLabel, previousHit, nextHit])
        searchControls.orientation = .horizontal
        searchControls.spacing = 7
        searchControls.alignment = .centerY

        let leadingSpacer = NSView()
        leadingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let trailingSpacer = NSView()
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [
            back, previous, next, pageLabel, outlineButton, leadingSpacer,
            searchControls, trailingSpacer,
            zoomOut, fit, zoomIn, zoomLabel,
            highlightButton, noteButton, scholarButton, aiButton, save
        ])
        controls.orientation = .horizontal
        controls.spacing = 7
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(controls)

        let headerSeparator = NSBox()
        headerSeparator.boxType = .separator
        headerSeparator.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerSeparator)

        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.89, alpha: 1)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        scrollView.documentView = canvasView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        documentPane.translatesAutoresizingMaskIntoConstraints = false
        documentPane.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        documentPane.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        documentPane.wantsLayer = true
        documentPane.layer?.masksToBounds = true
        documentPane.addSubview(scrollView)

        selectionActionBar.frame.size = PDFSelectionActionBar.preferredSize
        selectionActionBar.isHidden = true
        selectionActionBar.onCopy = { [weak self] in
            self?.copySelectionFromActionBar()
        }
        selectionActionBar.onHighlight = { [weak self] in
            self?.highlightSelectionFromActionBar()
        }
        selectionActionBar.onAskAI = { [weak self] in
            self?.askAIAboutSelectionFromActionBar()
        }
        documentPane.addSubview(selectionActionBar, positioned: .above, relativeTo: scrollView)

        navigationSidebar.onActivateOutline = { [weak self] entry in
            self?.activateOutlineEntry(entry)
        }
        navigationSidebar.onOpenPaper = { [weak self] url in
            self?.onOpenPaperFromLibrary?(url)
        }
        navigationSidebar.onResizeBy = { [weak self] delta in
            self?.resizeNavigationSidebar(by: delta)
        }
        navigationSidebar.onModeChange = { [weak self] mode in
            guard let self else { return }
            workspaceLayoutCoordinator.setNavigationMode(mode, source: self)
        }
        navigationSidebar.translatesAutoresizingMaskIntoConstraints = false
        navigationSidebar.isHidden = !workspaceLayoutCoordinator.navigationVisible
        outlineButton.state = workspaceLayoutCoordinator.navigationVisible ? .on : .off
        aiSidebar.onSend = { [weak self] question, attachments, preset, includeCurrentPDF in
            self?.submitAIMessage(
                question,
                attachments: attachments,
                preset: preset,
                includeCurrentPDF: includeCurrentPDF
            )
        }
        aiSidebar.onConfigure = { [weak self] in
            self?.configureAI(nil)
        }
        aiSidebar.onNewConversation = { [weak self] in
            self?.createAIConversation()
        }
        aiSidebar.onSelectConversation = { [weak self] conversationID in
            self?.selectAIConversation(conversationID)
        }
        aiSidebar.onDeleteConversation = { [weak self] in
            self?.deleteAIConversation()
        }
        aiSidebar.onDeleteMessage = { [weak self] messageID in
            self?.deleteAIMessage(messageID)
        }
        aiSidebar.onRemoveQueuedSubmission = { [weak self] submissionID in
            guard let self else { return }
            aiSubmissionQueue.remove(id: submissionID)
            refreshQueuedAISubmissions()
        }
        aiSidebar.onShowHistory = { [weak self] _ in
            self?.showAIHistoryMenu()
        }
        aiSidebar.onRevealCurrentHistory = { [weak self] in
            self?.revealCurrentAIHistoryFile()
        }
        aiSidebar.onPresetChange = { [weak self] preset in
            self?.updateAIConversationPreset(preset)
        }
        aiSidebar.onEditPromptTemplate = { [weak self] preset in
            self?.editAIPromptTemplate(preset)
        }
        aiSidebar.onAddPromptTemplate = { [weak self] in
            self?.addAIPromptTemplate()
        }
        aiSidebar.onCancel = { [weak self] in
            self?.aiTask?.cancel()
        }
        aiSidebar.onResizeBy = { [weak self] delta in
            self?.resizeAISidebar(by: delta)
        }
        aiSidebar.onResizeEnded = { [weak self] in
            self?.finishResizingAISidebar()
        }
        aiSidebar.isHidden = !workspaceLayoutCoordinator.aiVisible
        aiSidebar.setPaperTitle(paperTitle)
        aiSidebar.setReplyGestureZoomEnabled(AIReplyGestureZoomPreference.isEnabled())
        aiButton.state = workspaceLayoutCoordinator.aiVisible ? .on : .off
        contentSplitView.isVertical = true
        contentSplitView.dividerStyle = .thin
        contentSplitView.delegate = self
        contentSplitView.translatesAutoresizingMaskIntoConstraints = false
        contentSplitView.addArrangedSubview(navigationSidebar)
        contentSplitView.addArrangedSubview(documentPane)
        contentSplitView.addArrangedSubview(aiSidebar)
        contentSplitView.setHoldingPriority(.defaultLow, forSubviewAt: 1)
        contentSplitView.setHoldingPriority(.defaultHigh, forSubviewAt: 2)

        root.addSubview(header)
        root.addSubview(contentSplitView)
        window.contentView = root

        let minimumSearchWidth = searchField.widthAnchor.constraint(
            greaterThanOrEqualToConstant: 140
        )
        minimumSearchWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 46),
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: header.centerYAnchor, constant: -1),
            minimumSearchWidth,
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            headerSeparator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.topAnchor.constraint(equalTo: documentPane.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: documentPane.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: documentPane.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: documentPane.bottomAnchor),
            contentSplitView.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentSplitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        window.contentView?.layoutSubtreeIfNeeded()
        navigationSidebar.selectMode(
            workspaceLayoutCoordinator.navigationMode,
            notify: false
        )
        setOutlineVisible(
            workspaceLayoutCoordinator.navigationVisible,
            relayoutDocument: false,
            persistLayout: false
        )
        setAIVisible(
            workspaceLayoutCoordinator.aiVisible,
            persistLayout: false
        )
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = tooltip
        return button
    }

    private func configureToolButton(
        _ button: NSButton,
        symbol: String,
        tooltip: String,
        action: Selector
    ) {
        configureButton(button, symbol: symbol, tooltip: tooltip, action: action)
        button.setButtonType(.toggle)
    }

    private func configureButton(
        _ button: NSButton,
        symbol: String,
        tooltip: String,
        action: Selector
    ) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .texturedRounded
        button.target = self
        button.action = action
        button.toolTip = tooltip
    }

    private func loadDocument() {
        pageLabel.stringValue = "Loading…"
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let savedPosition = try? readingPositionStore.position(for: documentURL)
                let loadedOutline = (try? await engine.outline()) ?? []
                guard !Task.isCancelled else { return }
                navigationSidebar.installOutline(loadedOutline)
                var loaded: [DocumentPage] = []
                loaded.reserveCapacity(pageCount)
                for index in 0..<pageCount {
                    loaded.append(try await engine.page(at: index))
                }
                guard !Task.isCancelled else { return }
                pages = loaded
                canvasView.install(pages: loaded, delegate: self, tool: tool)
                if let savedPosition, !loaded.isEmpty, savedPosition.zoom.isFinite {
                    shouldFitInitialPage = false
                    zoom = min(8, max(0.15, savedPosition.zoom))
                } else if shouldFitInitialPage, let first = loaded.first {
                    shouldFitInitialPage = false
                    let availableWidth = max(120, scrollView.contentSize.width - 48)
                    zoom = min(2, max(0.15, availableWidth / first.width))
                }
                canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
                zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
                pageLabel.stringValue = "1 / \(pageCount)"
                if let savedPosition, !loaded.isEmpty {
                    let pageIndex = min(
                        max(0, savedPosition.bookmark.pageIndex),
                        loaded.count - 1
                    )
                    let pageFrame = canvasView.pageViews[pageIndex].frame
                    let restoredOrigin = savedPosition.bookmark.restoredViewportOrigin(
                        pageOrigin: PagePoint(x: pageFrame.minX, y: pageFrame.minY),
                        zoom: zoom
                    )
                    scroll(to: pageIndex, viewportOrigin: restoredOrigin)
                } else {
                    scroll(to: 0)
                }
                hasFinishedInitialLoad = true
                isSuspended = false
                updateVisiblePages()
                if window?.isKeyWindow != true {
                    scheduleSuspension()
                }
            } catch is CancellationError {
                return
            } catch {
                present(error: error, title: "Could not load PDF")
            }
        }
    }

    @objc private func clipBoundsChanged(_ notification: Notification) {
        guard !isApplyingZoomLayout else { return }
        hideSelectionActionBar()
        updateVisiblePages()
        scheduleReadingPositionSave()
    }

    private func updateVisiblePages() {
        guard !isSuspended, !pages.isEmpty else { return }
        var visibleRect = canvasView.visibleRect
        if visibleRect.isEmpty, canvasView.pageViews.indices.contains(currentPage) {
            visibleRect = NSRect(
                origin: canvasView.pageViews[currentPage].frame.origin,
                size: scrollView.contentSize
            )
        }
        var desired = canvasView.indices(near: visibleRect)
        if canvasView.pageViews.indices.contains(currentPage) {
            desired.insert(currentPage)
        }

        if let visiblePage = canvasView.pageIndex(at: visibleRect.minY + 8), visiblePage != currentPage {
            currentPage = visiblePage
        }
        pageLabel.stringValue = "\(currentPage + 1) / \(pageCount)"

        for index in canvasView.pageViews.indices {
            if desired.contains(index) {
                requestRender(for: index)
                requestText(for: index)
            } else {
                renderTasks.removeValue(forKey: index)?.cancel()
                textTasks.removeValue(forKey: index)?.cancel()
                renderTokens.removeValue(forKey: index)
                textTokens.removeValue(forKey: index)
                canvasView.pageViews[index].image = nil
                canvasView.pageViews[index].textPage = nil
            }
        }
    }

    private func requestRender(for pageIndex: Int, replacingExistingImage: Bool = false) {
        guard renderTasks[pageIndex] == nil else { return }
        if !replacingExistingImage, canvasView.pageViews[pageIndex].image != nil { return }
        let requestedZoom = zoom
        let generation = renderGeneration
        let token = UUID()
        renderTokens[pageIndex] = token
        let backingScale = window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        renderTasks[pageIndex] = Task { [weak self] in
            guard let self else { return }
            defer {
                if renderTokens[pageIndex] == token {
                    renderTasks[pageIndex] = nil
                    renderTokens[pageIndex] = nil
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          !self.isSuspended,
                          self.canvasView.pageViews.indices.contains(pageIndex),
                          self.canvasView.pageViews[pageIndex].image == nil else { return }
                    self.updateVisiblePages()
                }
            }
            do {
                guard pages.indices.contains(pageIndex) else { return }
                let page = pages[pageIndex]
                var renderScale = requestedZoom * backingScale
                let nativePixels = page.width * page.height * renderScale * renderScale
                if nativePixels > Self.maxRenderPixels {
                    renderScale = (Self.maxRenderPixels / (page.width * page.height)).squareRoot()
                }
                let longestSide = max(page.width, page.height) * renderScale
                if longestSide > Self.maxRenderDimension {
                    renderScale = Self.maxRenderDimension / max(page.width, page.height)
                }
                let request = PageRenderRequest(pageIndex: pageIndex, scale: renderScale)
                let rendered = try await scheduler.render(request)
                guard !Task.isCancelled, generation == renderGeneration,
                      canvasView.pageViews.indices.contains(pageIndex) else { return }
                canvasView.pageViews[pageIndex].image = try rendered.makeImage(
                    pointSize: canvasView.pageViews[pageIndex].bounds.size
                )
            } catch is CancellationError {
                return
            } catch {
                guard generation == renderGeneration else { return }
                present(error: error, title: "Could not render page")
            }
        }
    }

    private func requestText(for pageIndex: Int) {
        guard canvasView.pageViews[pageIndex].textPage == nil, textTasks[pageIndex] == nil else { return }
        let token = UUID()
        textTokens[pageIndex] = token
        textTasks[pageIndex] = Task { [weak self] in
            guard let self else { return }
            defer {
                if textTokens[pageIndex] == token {
                    textTasks[pageIndex] = nil
                    textTokens[pageIndex] = nil
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          !self.isSuspended,
                          self.canvasView.pageViews.indices.contains(pageIndex),
                          self.canvasView.pageViews[pageIndex].textPage == nil else { return }
                    self.updateVisiblePages()
                }
            }
            do {
                let text = try await engine.text(on: pageIndex)
                guard !Task.isCancelled, canvasView.pageViews.indices.contains(pageIndex) else { return }
                canvasView.pageViews[pageIndex].textPage = text
            } catch is CancellationError {
                return
            } catch {
                // Scanned PDFs can still be read even when no selectable text is available.
            }
        }
    }

    private func navigate(to pageIndex: Int) {
        guard pages.indices.contains(pageIndex), pageIndex != currentPage else { return }
        scroll(to: pageIndex)
    }

    private func activateOutlineEntry(_ entry: DocumentOutlineEntry) {
        guard let pageIndex = entry.pageIndex,
              pages.indices.contains(pageIndex) else { return }
        if let location = currentNavigationBookmark() {
            navigationHistory.append(location)
        }
        scroll(
            to: pageIndex,
            point: entry.point,
            horizontalBehavior: .preserve
        )
    }

    private func setOutlineVisible(
        _ visible: Bool,
        relayoutDocument: Bool = true,
        persistLayout: Bool = true
    ) {
        if persistLayout {
            workspaceLayoutCoordinator.setNavigationVisible(visible, source: self)
        }
        outlineWidthConstraints.forEach { $0.isActive = false }
        outlineWidthConstraints.removeAll()
        navigationSidebar.isHidden = !visible
        outlineButton.state = visible ? .on : .off
        if visible {
            outlineWidthConstraints = ReaderNavigationSidebarSizing.flexibleConstraints(
                for: navigationSidebar,
                coordinator: workspaceLayoutCoordinator
            )
            NSLayoutConstraint.activate(outlineWidthConstraints)
            applyNavigationSidebarWidth()
        }
        guard relayoutDocument else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        updateVisiblePages()
    }

    private func applyNavigationSidebarWidth() {
        guard !navigationSidebar.isHidden else { return }
        isApplyingNavigationSidebarLayout = true
        defer { isApplyingNavigationSidebarLayout = false }
        window?.contentView?.layoutSubtreeIfNeeded()
        if !aiSidebar.isHidden {
            applyAISidebarWidth(workspaceLayoutCoordinator.aiWidth)
        }
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func resizeNavigationSidebar(by delta: CGFloat) {
        guard !navigationSidebar.isHidden else { return }
        let anchor = currentZoomAnchor()
        let splitWidth = contentSplitView.bounds.width
        let aiWidth = aiSidebar.isHidden ? 0 : aiSidebar.frame.width
        let visiblePaneCount = contentSplitView.arrangedSubviews.filter { !$0.isHidden }.count
        let dividers = CGFloat(max(0, visiblePaneCount - 1)) * contentSplitView.dividerThickness
        let maximumWidth = max(
            ReaderNavigationSidebarSizing.minimumWidth,
            splitWidth - aiWidth - dividers - 120
        )
        let requested = min(
            maximumWidth,
            workspaceLayoutCoordinator.navigationWidth + delta
        )
        workspaceLayoutCoordinator.setNavigationWidth(requested, source: self)
        applyNavigationSidebarWidth()
        guard !pages.isEmpty else { return }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        restoreCurrentViewportCenter(from: anchor)
        updateVisiblePages()
    }

    @objc private func workspaceLayoutChanged(_ notification: Notification) {
        if let source = notification.object as? ReaderWindowController,
           source === self {
            return
        }
        navigationSidebar.selectMode(
            workspaceLayoutCoordinator.navigationMode,
            notify: false
        )
        setOutlineVisible(
            workspaceLayoutCoordinator.navigationVisible,
            persistLayout: false
        )
        setAIVisible(
            workspaceLayoutCoordinator.aiVisible,
            persistLayout: false
        )
    }

    private func setAIVisible(_ visible: Bool, persistLayout: Bool = true) {
        let anchor = currentZoomAnchor()
        if persistLayout {
            workspaceLayoutCoordinator.setAIVisible(visible, source: self)
        }
        isApplyingAISidebarLayout = true
        defer { isApplyingAISidebarLayout = false }
        if !visible {
            aiSidebarWidthConstraint?.isActive = false
        }
        aiSidebar.isHidden = !visible
        aiButton.state = visible ? .on : .off
        window?.contentView?.layoutSubtreeIfNeeded()
        if visible {
            applyAISidebarWidth(workspaceLayoutCoordinator.aiWidth)
            window?.contentView?.layoutSubtreeIfNeeded()
        }
        if visible {
            DispatchQueue.main.async { [weak self] in
                guard let self, !aiSidebar.isHidden else { return }
                let delayedAnchor = currentZoomAnchor()
                isApplyingAISidebarLayout = true
                applyAISidebarWidth(workspaceLayoutCoordinator.aiWidth)
                window?.contentView?.layoutSubtreeIfNeeded()
                isApplyingAISidebarLayout = false
                guard !pages.isEmpty else { return }
                canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
                restoreCurrentViewportCenter(from: delayedAnchor)
                updateVisiblePages()
            }
        }
        guard !pages.isEmpty else { return }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        restoreCurrentViewportCenter(from: anchor)
        updateVisiblePages()
    }

    private func resizeAISidebar(by delta: CGFloat) {
        guard !aiSidebar.isHidden else { return }
        if !isResizingAISidebar {
            isResizingAISidebar = true
            aiSidebarResizeAnchor = currentZoomAnchor()
        }
        isApplyingAISidebarLayout = true
        applyAISidebarWidth(aiSidebar.frame.width - delta)
        window?.contentView?.layoutSubtreeIfNeeded()
        isApplyingAISidebarLayout = false
    }

    private func finishResizingAISidebar() {
        guard isResizingAISidebar else { return }
        isResizingAISidebar = false
        let anchor = aiSidebarResizeAnchor
        aiSidebarResizeAnchor = nil
        let finalWidth = aiSidebarWidthConstraint?.constant ?? aiSidebar.frame.width
        if ReaderSidebarResizeWorkPolicy.persistsSharedWidth(during: .ended) {
            workspaceLayoutCoordinator.setAIWidth(finalWidth, source: self)
        }
        isApplyingAISidebarLayout = true
        applyAISidebarWidth(finalWidth)
        window?.contentView?.layoutSubtreeIfNeeded()
        isApplyingAISidebarLayout = false
        guard ReaderSidebarResizeWorkPolicy.relayoutsDocument(during: .ended),
              !pages.isEmpty else { return }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        restoreCurrentViewportCenter(from: anchor)
        updateVisiblePages()
    }

    private func applyAISidebarWidth(_ requestedWidth: CGFloat) {
        let splitWidth = contentSplitView.bounds.width
        let outlineWidth = navigationSidebar.isHidden ? 0 : navigationSidebar.frame.width
        let visiblePaneCount = contentSplitView.arrangedSubviews.filter { !$0.isHidden }.count
        let dividerWidth = CGFloat(max(0, visiblePaneCount - 1)) * contentSplitView.dividerThickness
        let minimumWidth = ReaderWorkspaceLayoutCoordinator.minimumAISidebarWidth
        let maximumWidth = max(minimumWidth, splitWidth - outlineWidth - dividerWidth - 120)
        let width = min(max(minimumWidth, requestedWidth), maximumWidth)

        if let aiSidebarWidthConstraint {
            aiSidebarWidthConstraint.constant = width
            aiSidebarWidthConstraint.isActive = true
        } else {
            let constraint = workspaceLayoutCoordinator.bindAISidebar(aiSidebar)
            constraint.constant = width
            constraint.isActive = true
            aiSidebarWidthConstraint = constraint
        }
    }

    private func restoreCurrentViewportCenter(from anchor: DocumentViewportZoomAnchor?) {
        guard let anchor,
              canvasView.pageViews.indices.contains(anchor.pageIndex) else { return }
        let pageFrame = canvasView.pageViews[anchor.pageIndex].frame
        let viewportSize = scrollView.contentSize
        let origin = PagePoint(
            x: pageFrame.minX + anchor.point.x * zoom - viewportSize.width / 2,
            y: pageFrame.minY + anchor.point.y * zoom - viewportSize.height / 2
        )
        scroll(to: anchor.pageIndex, viewportOrigin: origin, refreshVisiblePages: false)
    }

    private func selectedPDFText() -> String? {
        canvasView.pageViews
            .compactMap(\.textSelection?.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func loadAIPromptTemplates() {
        aiSidebar.setPromptTemplates(
            aiPromptTemplates,
            selectedPreset: activeAIConversationIndex
                .flatMap { aiHistory?.conversations[$0].promptPreset }
                ?? .defaultForNewConversation
        )
        Task { [weak self] in
            guard let self else { return }
            let templates = (try? await aiPromptTemplateStore.templates())
                ?? AIPromptTemplate.defaults
            aiPromptTemplates = templates
            let selected = activeAIConversationIndex
                .flatMap { aiHistory?.conversations[$0].promptPreset }
                ?? .defaultForNewConversation
            aiSidebar.setPromptTemplates(templates, selectedPreset: selected)
        }
    }

    private func loadAIHistory() {
        Task { [weak self] in
            guard let self else { return }
            let history = (try? await aiChatHistoryStore.history(for: documentURL))
                ?? AIPaperChatHistory.new(for: documentURL)
            guard !Task.isCancelled else { return }
            aiHistory = history
            aiHistoryLoaded = true
            let conversationID = pendingAIConversationID ?? history.activeConversationID
            pendingAIConversationID = nil
            activateAIConversation(conversationID, persistSelection: false)
            processNextAISubmissionIfNeeded()
        }
    }

    private func submitAIMessage(
        _ question: String,
        attachments: [AIChatImageAttachment] = [],
        preset: AIPromptPreset,
        includeCurrentPDF: Bool = false
    ) {
        let submission = AIChatSubmission(
            question: question,
            imageAttachments: attachments,
            promptPreset: preset,
            includeCurrentPDF: includeCurrentPDF
        )
        guard aiTask == nil, aiHistoryLoaded else {
            aiSubmissionQueue.enqueue(submission)
            refreshQueuedAISubmissions()
            if !aiHistoryLoaded {
                aiSidebar.setActivity(.loading, detail: "Opening this PDF's local conversation")
            }
            return
        }
        startAIMessage(submission)
    }

    private func processNextAISubmissionIfNeeded() {
        guard aiTask == nil, aiHistoryLoaded,
              let submission = aiSubmissionQueue.dequeue() else { return }
        refreshQueuedAISubmissions()
        startAIMessage(submission)
    }

    private func refreshQueuedAISubmissions() {
        aiSidebar.setQueuedSubmissions(aiSubmissionQueue.submissions)
    }

    private func startAIMessage(_ submission: AIChatSubmission) {
        guard aiTask == nil else {
            aiSubmissionQueue.enqueue(submission)
            refreshQueuedAISubmissions()
            return
        }
        guard aiHistoryLoaded else {
            aiSubmissionQueue.enqueue(submission)
            refreshQueuedAISubmissions()
            aiSidebar.setActivity(.loading, detail: "Opening this PDF's local conversation")
            return
        }

        let question = submission.question
        let attachments = submission.imageAttachments
        let preset = submission.promptPreset
        let includeCurrentPDF = submission.includeCurrentPDF

        let configuration = aiConfigurationStore.configuration()
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiSidebar.prefill(
                question,
                attachments: attachments,
                includeCurrentPDF: includeCurrentPDF
            )
            if showAISettings() {
                startAIMessage(submission)
            } else {
                aiSidebar.setActivity(.failed, detail: "Choose an AI provider and model before sending")
            }
            return
        }

        let apiKey: String
        do {
            apiKey = try aiConfigurationStore.apiKey()
        } catch {
            aiSidebar.prefill(
                question,
                attachments: attachments,
                includeCurrentPDF: includeCurrentPDF
            )
            present(error: error, title: "Could not read AI settings")
            return
        }

        let promptTemplate = promptTemplate(for: preset)
        guard let displayQuestion = AIChatRequestBuilder.displayQuestion(
            question: question,
            template: promptTemplate,
            hasImageAttachments: !attachments.isEmpty,
            includeCurrentPDF: includeCurrentPDF
        ) else { return }
        if let index = activeAIConversationIndex {
            aiHistory?.conversations[index].promptPreset = preset
            if aiMessages.isEmpty,
               aiHistory?.conversations[index].title == "New conversation" {
                aiHistory?.conversations[index].title = conversationTitle(for: displayQuestion)
            }
            aiHistory?.conversations[index].updatedAt = Date()
            refreshAIConversationControls()
        }
        let userMessage = AIChatMessage(
            role: .user,
            content: displayQuestion,
            imageAttachments: attachments
        )
        aiSidebar.clearComposer()
        aiMessages.append(userMessage)
        aiSidebar.append(userMessage)
        persistAIHistory()

        let placeholder = AIChatMessage(role: .assistant, content: "")
        activeAIPlaceholderID = placeholder.id
        let providerIdentity = aiProviderIdentity(for: configuration)
        aiSidebar.append(placeholder)
        aiSidebar.setStreaming(true)
        aiSidebar.setActivity(
            includeCurrentPDF ? .uploading : .preparing,
            detail: includeCurrentPDF ? documentURL.lastPathComponent : configuration.model
        )
        aiSidebar.setMessageActivity(
            id: placeholder.id,
            phase: .preparing,
            identity: providerIdentity
        )
        let conversationGeneration = aiConversationGeneration
        let conversationKey: String?
        if let index = activeAIConversationIndex, let history = aiHistory {
            conversationKey = AIConversationRouting.conversationKey(
                for: history.conversations[index].id,
                configuration: configuration
            )
        } else {
            conversationKey = nil
        }

        aiTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var accumulator = OpenAIStreamAccumulator()
            var reportedThinking = false
            var reportedAnswering = false
            defer {
                if activeAIPlaceholderID == placeholder.id {
                    activeAIPlaceholderID = nil
                }
                aiSidebar.setStreaming(false)
                aiTask = nil
                processNextAISubmissionIfNeeded()
            }
            do {
                let requestMessages = AIChatRequestBuilder.messages(
                    instruction: promptTemplate.instruction(title: paperTitle),
                    paperContext: nil,
                    conversation: recentAIConversation()
                )
                let conversationTitle = conversationKey == nil
                    ? nil
                    : await qwenConversationTitle()
                let bridge = LocalWebBridge.shared
                if let endpoint = bridge.bridgeEndpoint(from: configuration.baseURL),
                   !(await bridge.probe(endpoint)) {
                    aiSidebar.setActivity(.preparing, detail: "Starting local bridge…")
                    aiSidebar.setMessageActivity(
                        id: placeholder.id,
                        phase: .preparing,
                        identity: providerIdentity
                    )
                }
                guard await bridge.ensureReady(for: configuration.baseURL) else {
                    throw OpenAICompatibleError.invalidConfiguration(
                        "Local web bridge did not start on \(configuration.baseURL). See uwa-lite.log in Application Support."
                    )
                }
                let stream = aiClient.streamChat(
                    messages: requestMessages,
                    configuration: configuration,
                    apiKey: apiKey,
                    conversationKey: conversationKey,
                    conversationTitle: conversationTitle,
                    currentPDFURL: includeCurrentPDF ? documentURL : nil
                )
                if !includeCurrentPDF {
                    aiSidebar.setActivity(.waiting, detail: configuration.model)
                }
                aiSidebar.setMessageActivity(
                    id: placeholder.id,
                    phase: .waiting,
                    identity: providerIdentity
                )
                for try await event in stream {
                    try Task.checkCancellation()
                    guard conversationGeneration == aiConversationGeneration else {
                        throw CancellationError()
                    }
                    switch accumulator.consume(event) {
                    case .thinking where !reportedThinking:
                        reportedThinking = true
                        aiSidebar.setActivity(.thinking, detail: configuration.model)
                        aiSidebar.setMessageActivity(
                            id: placeholder.id,
                            phase: .thinking,
                            identity: providerIdentity
                        )
                    case .answering where !reportedAnswering:
                        reportedAnswering = true
                        aiSidebar.setActivity(.answering, detail: configuration.model)
                        aiSidebar.setMessageActivity(
                            id: placeholder.id,
                            phase: .answering,
                            identity: providerIdentity
                        )
                    case .thinking, .answering, .finished:
                        break
                    }
                }
                let finalContent = try accumulator.finalAnswer()
                guard conversationGeneration == aiConversationGeneration else {
                    throw CancellationError()
                }

                let assistantMessage = AIChatMessage(
                    id: placeholder.id,
                    role: .assistant,
                    content: finalContent
                )
                aiMessages.append(assistantMessage)
                aiSidebar.updateMessage(
                    id: placeholder.id,
                    content: finalContent,
                    renderMarkdown: true
                )
                persistAIHistory()
                let promptName = promptTemplate.instruction(title: paperTitle) == nil
                    ? ""
                    : " · \(promptTemplate.name)"
                aiSidebar.setActivity(.completed, detail: "\(configuration.model)\(promptName)")
                aiSidebar.setMessageActivity(
                    id: placeholder.id,
                    phase: .completed,
                    identity: providerIdentity
                )
            } catch is CancellationError {
                guard conversationGeneration == aiConversationGeneration else { return }
                let partialContent = accumulator.content
                if partialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    aiSidebar.removeMessage(id: placeholder.id)
                } else {
                    let assistantMessage = AIChatMessage(
                        id: placeholder.id,
                        role: .assistant,
                        content: partialContent
                    )
                    aiMessages.append(assistantMessage)
                    aiSidebar.updateMessage(
                        id: placeholder.id,
                        content: partialContent,
                        renderMarkdown: true
                    )
                    persistAIHistory()
                }
                aiSidebar.setActivity(.stopped, detail: "Generation stopped")
                aiSidebar.setMessageActivity(
                    id: placeholder.id,
                    phase: .stopped,
                    identity: providerIdentity
                )
            } catch {
                let partialContent = accumulator.content
                if partialContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    aiSidebar.updateMessage(
                        id: placeholder.id,
                        content: "Request failed: \(error.localizedDescription)"
                    )
                } else {
                    let assistantMessage = AIChatMessage(
                        id: placeholder.id,
                        role: .assistant,
                        content: partialContent
                    )
                    aiMessages.append(assistantMessage)
                    aiSidebar.updateMessage(
                        id: placeholder.id,
                        content: partialContent,
                        renderMarkdown: true
                    )
                    persistAIHistory()
                }
                aiSidebar.setActivity(.failed, detail: error.localizedDescription)
                aiSidebar.setMessageActivity(
                    id: placeholder.id,
                    phase: .failed,
                    identity: providerIdentity
                )
            }
        }
    }

    private func recentAIConversation(
        maximumMessages: Int = 24,
        maximumCharacters: Int = 40_000
    ) -> [AIChatMessage] {
        var result: [AIChatMessage] = []
        var remaining = maximumCharacters
        for message in aiMessages.suffix(maximumMessages).reversed() {
            guard remaining > 0 else { break }
            if message.content.count <= remaining {
                result.append(message)
                remaining -= message.content.count
            } else if result.isEmpty {
                result.append(AIChatMessage(
                    id: message.id,
                    role: message.role,
                    content: String(message.content.suffix(remaining)),
                    createdAt: message.createdAt
                ))
                remaining = 0
            }
        }
        return result.reversed()
    }

    private var paperTitle: String {
        documentURL.deletingPathExtension().lastPathComponent
    }

    private func qwenConversationTitle() async -> String {
        let documentPath = documentURL.standardizedFileURL.path
        if let snapshot = try? await paperLibraryStore.snapshot(),
           let paper = snapshot.papers.first(where: {
               URL(fileURLWithPath: $0.path).standardizedFileURL.path == documentPath
           }) {
            return String(paper.displayTitle.prefix(120))
        }
        return String(paperTitle.prefix(120))
    }

    private func scholarPaperTitle() async -> String {
        let documentPath = documentURL.standardizedFileURL.path
        if let snapshot = try? await paperLibraryStore.snapshot(),
           let paper = snapshot.papers.first(where: {
               URL(fileURLWithPath: $0.path).standardizedFileURL.path == documentPath
           }) {
            return paper.displayTitle
        }
        return PaperLibraryPaper.automaticDisplayAlias(for: paperTitle)
    }

    @objc private func openGoogleScholarCitations(_ sender: Any?) {
        Task { [weak self] in
            guard let self,
                  let url = GoogleScholarLinkBuilder.paperSearchURL(
                    fileNameOrDisplayTitle: await scholarPaperTitle()
                  ) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private func promptTemplate(for preset: AIPromptPreset) -> AIPromptTemplate {
        aiPromptTemplates.first { $0.id == preset.rawValue }
            ?? AIPromptTemplate.defaults[0]
    }

    private func aiProviderIdentity(for configuration: AIProviderConfiguration) -> String {
        let host = URL(string: configuration.baseURL)?.host?.lowercased() ?? ""
        let provider: String
        switch host {
        case "127.0.0.1", "localhost", "::1":
            provider = "Universal Web API"
        case "api.openai.com":
            provider = "OpenAI"
        case "openrouter.ai":
            provider = "OpenRouter"
        default:
            provider = host.isEmpty ? "AI provider" : host
        }
        return "\(provider) · \(configuration.model)"
    }

    private var activeAIConversationIndex: Int? {
        guard let aiHistory else { return nil }
        return aiHistory.conversations.firstIndex { $0.id == aiHistory.activeConversationID }
    }

    private func activateAIConversation(_ conversationID: String, persistSelection: Bool) {
        guard var history = aiHistory else {
            pendingAIConversationID = conversationID
            return
        }
        guard let index = history.conversations.firstIndex(where: { $0.id == conversationID }) else {
            let fallback = history.conversations.first ?? AIConversation()
            if history.conversations.isEmpty { history.conversations = [fallback] }
            history.activeConversationID = fallback.id
            aiHistory = history
            activateAIConversation(fallback.id, persistSelection: persistSelection)
            return
        }

        aiTask?.cancel()
        aiConversationGeneration += 1
        aiSubmissionQueue.removeAll()
        refreshQueuedAISubmissions()
        history.activeConversationID = conversationID
        aiHistory = history
        aiMessages = history.conversations[index].messages.filter { $0.role != .system }
        aiSidebar.setStreaming(false)
        aiSidebar.setConversations(history.conversations, selectedID: conversationID)
        aiSidebar.setPromptTemplates(
            aiPromptTemplates,
            selectedPreset: history.conversations[index].promptPreset
        )
        aiSidebar.install(aiMessages)
        if aiMessages.isEmpty {
            let preset = history.conversations[index].promptPreset
            let template = promptTemplate(for: preset)
            aiSidebar.setActivity(
                .ready,
                detail: template.instruction(title: paperTitle) == nil
                    ? "\(template.name) sends only the visible chat"
                    : "\(template.name) mode selected; no PDF pages are attached"
            )
        } else {
            aiSidebar.setActivity(.ready, detail: "Restored this paper's local conversation")
        }
        if persistSelection { persistAIHistory() }
    }

    func selectAIConversation(_ conversationID: String) {
        guard aiHistoryLoaded else {
            pendingAIConversationID = conversationID
            return
        }
        activateAIConversation(conversationID, persistSelection: true)
    }

    private func createAIConversation() {
        guard aiHistoryLoaded, var history = aiHistory else { return }
        let conversation = AIConversation(
            title: "New conversation \(history.conversations.count + 1)",
            promptPreset: .defaultForNewConversation
        )
        history.conversations.append(conversation)
        history.activeConversationID = conversation.id
        aiHistory = history
        activateAIConversation(conversation.id, persistSelection: true)
        aiSidebar.focusComposer()
    }

    private func updateAIConversationPreset(_ preset: AIPromptPreset) {
        guard let index = activeAIConversationIndex else { return }
        aiHistory?.conversations[index].promptPreset = preset
        aiHistory?.conversations[index].updatedAt = Date()
        persistAIHistory()
    }

    private func editAIPromptTemplate(_ preset: AIPromptPreset) {
        guard let index = aiPromptTemplates.firstIndex(where: { $0.id == preset.rawValue }) else {
            return
        }
        guard let edited = promptTemplateEditor(
            template: aiPromptTemplates[index],
            title: "Edit prompt mode"
        ) else { return }
        guard !aiPromptTemplates.enumerated().contains(where: { otherIndex, template in
            otherIndex != index
                && template.name.compare(edited.name, options: .caseInsensitive) == .orderedSame
        }) else {
            aiSidebar.setActivity(.failed, detail: "A prompt mode with that name already exists")
            return
        }
        aiPromptTemplates[index] = edited
        refreshPromptTemplateControls(selecting: preset)
        saveAIPromptTemplates()
    }

    private func addAIPromptTemplate() {
        let draft = AIPromptTemplate(name: "New mode", prompt: "")
        guard let template = promptTemplateEditor(
            template: draft,
            title: "New prompt mode"
        ) else { return }
        guard !aiPromptTemplates.contains(where: {
            $0.name.compare(template.name, options: .caseInsensitive) == .orderedSame
        }) else {
            aiSidebar.setActivity(.failed, detail: "A prompt mode with that name already exists")
            return
        }
        aiPromptTemplates.append(template)
        updateAIConversationPreset(template.preset)
        refreshPromptTemplateControls(selecting: template.preset)
        saveAIPromptTemplates()
    }

    private func promptTemplateEditor(
        template: AIPromptTemplate,
        title: String
    ) -> AIPromptTemplate? {
        let form = AIPromptTemplateEditorView(template: template)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Prompt modes are stored locally as a portable JSON file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = form
        alert.window.initialFirstResponder = form.initialFirstResponder
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = form.templateName
        guard !name.isEmpty else {
            aiSidebar.setActivity(.failed, detail: "Prompt mode name cannot be empty")
            return nil
        }
        return AIPromptTemplate(id: template.id, name: name, prompt: form.prompt)
    }

    private func refreshPromptTemplateControls(selecting preset: AIPromptPreset) {
        aiSidebar.setPromptTemplates(aiPromptTemplates, selectedPreset: preset)
        if let index = activeAIConversationIndex {
            aiHistory?.conversations[index].promptPreset = preset
            aiHistory?.conversations[index].updatedAt = Date()
            persistAIHistory()
        }
    }

    private func saveAIPromptTemplates() {
        let templates = aiPromptTemplates
        Task { [weak self, aiPromptTemplateStore] in
            do {
                try await aiPromptTemplateStore.save(templates)
                self?.aiSidebar.setActivity(
                    .ready,
                    detail: "Prompt modes saved as portable JSON"
                )
            } catch {
                self?.aiSidebar.setActivity(.failed, detail: error.localizedDescription)
            }
        }
    }

    private func refreshAIConversationControls() {
        guard let history = aiHistory else { return }
        aiSidebar.setConversations(history.conversations, selectedID: history.activeConversationID)
        if let index = activeAIConversationIndex {
            aiSidebar.setPromptTemplates(
                aiPromptTemplates,
                selectedPreset: history.conversations[index].promptPreset
            )
        }
    }

    private func conversationTitle(for firstQuestion: String) -> String {
        if aiPromptTemplates.contains(where: { $0.name == firstQuestion }) {
            return firstQuestion
        }
        let firstLine = firstQuestion
            .split(whereSeparator: \Character.isNewline)
            .first
            .map(String.init) ?? firstQuestion
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 48 else { return trimmed }
        return String(trimmed.prefix(47)) + "…"
    }

    private func persistAIHistory() {
        guard let index = activeAIConversationIndex else { return }
        aiHistory?.conversations[index].messages = aiMessages
        if let latest = aiMessages.last?.createdAt {
            aiHistory?.conversations[index].updatedAt = latest
        }
        guard let snapshot = aiHistory else { return }
        aiHistorySaveTask?.cancel()
        aiHistorySaveTask = Task { [weak self, aiChatHistoryStore, documentURL] in
            guard !Task.isCancelled else { return }
            try? await aiChatHistoryStore.save(snapshot, for: documentURL)
            guard let self, !Task.isCancelled else { return }
            aiHistorySaveTask = nil
        }
    }

    private func deleteAIMessage(_ messageID: String) {
        let isActivePlaceholder = activeAIPlaceholderID == messageID
        guard isActivePlaceholder || aiMessages.contains(where: { $0.id == messageID }) else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete this message?"
        alert.informativeText = "This removes the message from this paper's local conversation."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if isActivePlaceholder {
            aiConversationGeneration += 1
            activeAIPlaceholderID = nil
            aiTask?.cancel()
        }
        aiMessages.removeAll { $0.id == messageID }
        aiSidebar.removeMessage(id: messageID)
        persistAIHistory()
    }

    private func deleteAIConversation() {
        guard let index = activeAIConversationIndex, var history = aiHistory else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this conversation?"
        alert.informativeText = "Other conversations for this paper will remain in local history."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        aiTask?.cancel()
        aiConversationGeneration += 1
        aiHistorySaveTask?.cancel()
        aiHistorySaveTask = nil
        history.conversations.remove(at: index)
        if history.conversations.isEmpty {
            history.conversations = [AIConversation(promptPreset: .defaultForNewConversation)]
        }
        let next = history.conversations.max { lhs, rhs in lhs.updatedAt < rhs.updatedAt }
            ?? history.conversations[0]
        history.activeConversationID = next.id
        aiHistory = history
        activateAIConversation(next.id, persistSelection: true)
    }

    private func showAIHistoryMenu() {
        aiSidebar.setActivity(.loading, detail: "Opening local chat history")
        Task { [weak self] in
            guard let self else { return }
            let histories = (try? await aiChatHistoryStore.allHistories()) ?? []
            let menu = NSMenu(title: "Chat History")
            if histories.isEmpty {
                let empty = NSMenuItem(title: "No saved conversations", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                for history in histories {
                    let paperItem = NSMenuItem(
                        title: history.documentTitle,
                        action: nil,
                        keyEquivalent: ""
                    )
                    let conversations = NSMenu(title: history.documentTitle)
                    for conversation in history.conversations.sorted(by: { $0.updatedAt > $1.updatedAt }) {
                        let item = NSMenuItem(
                            title: conversation.title,
                            action: #selector(openAIHistoryItem(_:)),
                            keyEquivalent: ""
                        )
                        item.target = self
                        item.representedObject = AIHistoryMenuSelection(
                            documentPath: history.documentPath,
                            conversationID: conversation.id
                        )
                        conversations.addItem(item)
                    }
                    paperItem.submenu = conversations
                    menu.addItem(paperItem)
                }
            }
            menu.addItem(.separator())
            let reveal = NSMenuItem(
                title: "Show Chat Files in Finder",
                action: #selector(revealAIHistoryFiles(_:)),
                keyEquivalent: ""
            )
            reveal.target = self
            menu.addItem(reveal)
            aiSidebar.setActivity(.ready, detail: "Chat history is stored as portable JSON files")
            aiSidebar.presentHistoryMenu(menu)
        }
    }

    @objc private func openAIHistoryItem(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? AIHistoryMenuSelection else { return }
        let URL = URL(fileURLWithPath: selection.documentPath)
        if URL.standardizedFileURL == documentURL.standardizedFileURL {
            selectAIConversation(selection.conversationID)
        } else if FileManager.default.fileExists(atPath: URL.path) {
            onNavigateAIHistory?(URL, selection.conversationID)
        } else {
            let alert = NSAlert()
            alert.messageText = "PDF not found"
            alert.informativeText = "The chat JSON is still available, but the original PDF is no longer at:\n\(URL.path)"
            alert.runModal()
        }
    }

    @objc private func revealAIHistoryFiles(_ sender: Any?) {
        let directory = aiChatHistoryStore.storageDirectoryURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private func revealCurrentAIHistoryFile() {
        guard let index = activeAIConversationIndex else {
            aiSidebar.setActivity(.failed, detail: "No conversation is available for this paper")
            return
        }
        aiHistory?.conversations[index].messages = aiMessages
        if let latest = aiMessages.last?.createdAt {
            aiHistory?.conversations[index].updatedAt = latest
        }
        guard let snapshot = aiHistory else {
            aiSidebar.setActivity(.failed, detail: "No conversation is available for this paper")
            return
        }

        let historyFileURL = aiChatHistoryStore.fileURL(for: documentURL)
        aiHistorySaveTask?.cancel()
        aiHistorySaveTask = Task { [weak self, aiChatHistoryStore, documentURL] in
            do {
                try await aiChatHistoryStore.save(snapshot, for: documentURL)
                guard !Task.isCancelled else { return }
                NSWorkspace.shared.activateFileViewerSelecting([historyFileURL])
                self?.aiSidebar.setActivity(.ready, detail: "Showing this paper's portable chat JSON")
            } catch {
                guard !Task.isCancelled else { return }
                self?.aiSidebar.setActivity(.failed, detail: error.localizedDescription)
            }
            self?.aiHistorySaveTask = nil
        }
    }

    @objc private func aiReplyGestureZoomPreferenceChanged(_ notification: Notification) {
        let enabled = notification.userInfo?["enabled"] as? Bool
            ?? AIReplyGestureZoomPreference.isEnabled()
        aiSidebar.setReplyGestureZoomEnabled(enabled)
    }

    @discardableResult
    private func showAISettings() -> Bool {
        let apiKey: String
        do {
            apiKey = try aiConfigurationStore.apiKey()
        } catch {
            present(error: error, title: "Could not read AI settings")
            return false
        }

        let form = AISettingsFormView(
            configuration: aiConfigurationStore.configuration(),
            apiKey: apiKey,
            replyGestureZoomEnabled: AIReplyGestureZoomPreference.isEnabled()
        )
        form.onOpenChatHistory = { [weak self] in
            self?.revealAIHistoryFiles(nil)
        }
        let alert = NSAlert()
        alert.messageText = "AI Settings"
        alert.informativeText = "Configure an OpenAI-compatible chat-completions endpoint."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = form
        alert.window.initialFirstResponder = form.initialFirstResponder
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        let configuration = form.configuration
        guard !configuration.baseURL.isEmpty, !configuration.model.isEmpty else {
            let error = OpenAICompatibleError.invalidConfiguration(
                "Base URL and model are required."
            )
            present(error: error, title: "Could not save AI settings")
            return false
        }
        do {
            try aiConfigurationStore.save(configuration: configuration, apiKey: form.apiKey)
            AIReplyGestureZoomPreference.setEnabled(form.replyGestureZoomEnabled)
            aiSidebar.setActivity(.ready, detail: "AI provider saved; paper text is sent only when requested")
            return true
        } catch {
            present(error: error, title: "Could not save AI settings")
            return false
        }
    }

    private func scroll(
        to pageIndex: Int,
        point: PagePoint? = nil,
        horizontalBehavior: HorizontalScrollBehavior = .useDestination,
        refreshVisiblePages: Bool = true
    ) {
        guard canvasView.pageViews.indices.contains(pageIndex) else { return }
        currentPage = pageIndex
        let pageFrame = canvasView.pageViews[pageIndex].frame
        let currentOrigin = scrollView.contentView.bounds.origin
        let targetX: CGFloat
        switch horizontalBehavior {
        case .preserve:
            targetX = currentOrigin.x
        case .useDestination:
            targetX = point.map { pageFrame.minX + $0.x * zoom } ?? currentOrigin.x
        }
        let origin = NSPoint(
            x: targetX,
            y: max(0, point.map { pageFrame.minY + $0.y * zoom } ?? pageFrame.minY - 12)
        )
        applyScroll(to: pageIndex, origin: origin, refreshVisiblePages: refreshVisiblePages)
    }

    private func scroll(
        to pageIndex: Int,
        viewportOrigin: PagePoint,
        refreshVisiblePages: Bool = true
    ) {
        applyScroll(
            to: pageIndex,
            origin: NSPoint(x: viewportOrigin.x, y: max(0, viewportOrigin.y)),
            refreshVisiblePages: refreshVisiblePages
        )
    }

    private func applyScroll(
        to pageIndex: Int,
        origin: NSPoint,
        refreshVisiblePages: Bool
    ) {
        guard canvasView.pageViews.indices.contains(pageIndex) else { return }
        currentPage = pageIndex
        var proposedBounds = scrollView.contentView.bounds
        proposedBounds.origin = origin
        let constrainedBounds = scrollView.contentView.constrainBoundsRect(proposedBounds)
        scrollView.contentView.scroll(to: constrainedBounds.origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pageLabel.stringValue = "\(pageIndex + 1) / \(pageCount)"
        if refreshVisiblePages {
            updateVisiblePages()
        }
    }

    private func currentZoomAnchor() -> DocumentViewportZoomAnchor? {
        let origin = scrollView.contentView.bounds.origin
        let viewportSize = scrollView.contentSize
        let centerY = origin.y + viewportSize.height / 2
        let pageIndex = canvasView.pageIndex(at: centerY) ?? currentPage
        guard canvasView.pageViews.indices.contains(pageIndex) else { return nil }
        let pageFrame = canvasView.pageViews[pageIndex].frame
        return DocumentViewportZoomAnchor.capture(
            pageIndex: pageIndex,
            pageOrigin: PagePoint(x: pageFrame.minX, y: pageFrame.minY),
            viewportOrigin: PagePoint(x: origin.x, y: origin.y),
            viewportSize: PagePoint(x: viewportSize.width, y: viewportSize.height),
            zoom: zoom
        )
    }

    private func currentNavigationBookmark() -> DocumentViewportBookmark? {
        let origin = scrollView.contentView.bounds.origin
        let pageIndex = canvasView.pageIndex(at: origin.y + 8) ?? currentPage
        guard canvasView.pageViews.indices.contains(pageIndex) else { return nil }
        let pageFrame = canvasView.pageViews[pageIndex].frame
        return DocumentViewportBookmark.capture(
            pageIndex: pageIndex,
            pageOrigin: PagePoint(x: pageFrame.minX, y: pageFrame.minY),
            viewportOrigin: PagePoint(x: origin.x, y: origin.y),
            zoom: zoom
        )
    }

    func saveReadingPosition() {
        readingPositionSaveTask?.cancel()
        readingPositionSaveTask = nil
        persistReadingPosition()
    }

    private func scheduleReadingPositionSave() {
        guard hasFinishedInitialLoad else { return }
        readingPositionSaveTask?.cancel()
        readingPositionSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled, let self else { return }
            readingPositionSaveTask = nil
            persistReadingPosition()
        }
    }

    private func persistReadingPosition() {
        guard hasFinishedInitialLoad,
              let bookmark = currentNavigationBookmark() else { return }
        let position = ReadingPosition(bookmark: bookmark, zoom: zoom)
        try? readingPositionStore.save(position, for: documentURL)
    }

    private func setZoom(
        _ requestedZoom: Double,
        anchor: DocumentViewportZoomAnchor? = nil,
        renderFinalImage: Bool = true
    ) {
        guard !pages.isEmpty else { return }
        hideSelectionActionBar()
        let preservedAnchor = anchor ?? currentZoomAnchor()
        if renderFinalImage {
            cancelPageWork()
        }
        zoom = min(8, max(0.15, requestedZoom))
        isApplyingZoomLayout = true
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
        if let preservedAnchor,
           canvasView.pageViews.indices.contains(preservedAnchor.pageIndex) {
            let pageFrame = canvasView.pageViews[preservedAnchor.pageIndex].frame
            let restoredOrigin = preservedAnchor.restoredViewportOrigin(
                pageOrigin: PagePoint(x: pageFrame.minX, y: pageFrame.minY),
                zoom: zoom
            )
            scroll(to: preservedAnchor.pageIndex, viewportOrigin: restoredOrigin, refreshVisiblePages: false)
        }
        isApplyingZoomLayout = false
        guard renderFinalImage else { return }
        updateVisiblePages()
        var desiredPages = canvasView.indices(near: canvasView.visibleRect)
        desiredPages.insert(currentPage)
        for pageIndex in desiredPages where canvasView.pageViews.indices.contains(pageIndex) {
            requestRender(for: pageIndex, replacingExistingImage: true)
        }
    }

    private func setTool(_ newTool: ReaderTool) {
        hideSelectionActionBar()
        tool = newTool
        noteButton.state = newTool == .note ? .on : .off
        noteButton.contentTintColor = newTool == .note ? .systemBlue : .labelColor
        canvasView.pageViews.forEach { $0.tool = newTool }
    }

    private func addAnnotation(
        _ annotation: DocumentAnnotationDraft,
        on pageIndex: Int,
        failureTitle: String
    ) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.add(annotation)
                await scheduler.invalidate(pageIndex: pageIndex)
                recordAnnotationAdded()
                requestRender(for: pageIndex, replacingExistingImage: true)
            } catch {
                present(error: error, title: failureTitle)
            }
        }
    }

    private func applySearchResults() {
        canvasView.pageViews.forEach {
            $0.searchRects = []
            $0.activeSearchRects = []
        }
        for hit in searchResults where canvasView.pageViews.indices.contains(hit.pageIndex) {
            canvasView.pageViews[hit.pageIndex].searchRects.append(contentsOf: hit.rects)
        }
    }

    private func showSearchResult(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        if let previous = activeSearchIndex, searchResults.indices.contains(previous) {
            let previousHit = searchResults[previous]
            canvasView.pageViews[previousHit.pageIndex].activeSearchRects = []
        }
        activeSearchIndex = index
        let hit = searchResults[index]
        canvasView.pageViews[hit.pageIndex].activeSearchRects = hit.rects
        searchLabel.stringValue = "\(index + 1) / \(searchResults.count)"
        scroll(to: hit.pageIndex)
        if let rect = hit.rects.first {
            let pageView = canvasView.pageViews[hit.pageIndex]
            pageView.scrollToVisible(NSRect(
                x: rect.x * zoom,
                y: rect.y * zoom,
                width: max(1, rect.width * zoom),
                height: max(1, rect.height * zoom)
            ).insetBy(dx: -20, dy: -80))
        }
    }

    private func clearSearchResults() {
        searchResults = []
        activeSearchIndex = nil
        completedSearchQuery = nil
        searchLabel.stringValue = ""
        canvasView.pageViews.forEach {
            $0.searchRects = []
            $0.activeSearchRects = []
        }
    }

    private func cancelPageWork() {
        renderGeneration += 1
        renderTasks.values.forEach { $0.cancel() }
        textTasks.values.forEach { $0.cancel() }
        renderTasks.removeAll()
        textTasks.removeAll()
        renderTokens.removeAll()
        textTokens.removeAll()
    }

    private func scheduleSuspension() {
        let token = UUID()
        suspensionToken = token
        suspensionTask?.cancel()
        suspensionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self, suspensionToken == token, window?.isKeyWindow != true else { return }
            isSuspended = true
            cancelPageWork()
            canvasView.pageViews.forEach { view in
                view.image = nil
                view.textPage = nil
            }
            await scheduler.removeAll()
            guard suspensionToken == token, window?.isKeyWindow != true else {
                isSuspended = false
                updateVisiblePages()
                return
            }
            await engine.releaseMemory()
        }
    }

    private func save(closeWhenFinished: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.save(to: documentURL)
                savedEditState = editState
                updateEditedState()
                if closeWhenFinished {
                    closingAfterSave = true
                    window?.performClose(nil)
                }
            } catch {
                present(error: error, title: "Could not save PDF")
            }
        }
    }

    private func recordAnnotationAdded() {
        undoEditStates.append(editState)
        editState = UUID()
        updateEditedState()
    }

    private func updateEditedState() {
        window?.isDocumentEdited = editState != savedEditState
    }

    private func present(error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        if let window {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

private extension RenderedPage {
    func makeImage(pointSize: NSSize) throws -> NSImage {
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw DocumentEngineError.engineFailure("Could not create a macOS image from rendered pixels")
        }
        return NSImage(cgImage: image, size: pointSize)
    }
}
