import AppKit
import CoreGraphics
import PDFlightCore
import PDFlightMuPDF

private enum HorizontalScrollBehavior {
    case preserve
    case useDestination
}

@MainActor
final class ReaderWindowController: NSWindowController, NSWindowDelegate, PageViewDelegate {
    var onClose: (() -> Void)?

    let documentURL: URL
    private let engine: MuPDFDocument
    private let scheduler: RenderScheduler
    private let pageCount: Int
    private let scrollView = NSScrollView()
    private let canvasView = DocumentCanvasView()
    private let contentSplitView = NSSplitView()
    private let outlineSidebar = OutlineSidebarView()
    private let pageLabel = NSTextField(labelWithString: "—")
    private let zoomLabel = NSTextField(labelWithString: "100%")
    private let searchField = NSSearchField()
    private let searchLabel = NSTextField(labelWithString: "")
    private let highlightButton = NSButton()
    private let noteButton = NSButton()
    private let outlineButton = NSButton()
    private var pages: [DocumentPage] = []
    private var currentPage = 0
    private var zoom = 1.0
    private var tool: ReaderTool = .select
    private var navigationHistory: [DocumentViewportBookmark] = []
    private var loadTask: Task<Void, Never>?
    private var renderTasks: [Int: Task<Void, Never>] = [:]
    private var textTasks: [Int: Task<Void, Never>] = [:]
    private var renderTokens: [Int: UUID] = [:]
    private var textTokens: [Int: UUID] = [:]
    private var searchTask: Task<Void, Never>?
    private var suspensionTask: Task<Void, Never>?
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
    private var outlineWidthConstraints: [NSLayoutConstraint] = []

    init(url: URL, engine: MuPDFDocument) {
        let initialEditState = UUID()
        self.documentURL = url
        self.engine = engine
        self.pageCount = engine.pageCount
        self.editState = initialEditState
        self.savedEditState = initialEditState
        self.scheduler = RenderScheduler(byteLimit: 12 * 1_024 * 1_024) { request in
            try await engine.render(request)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1020, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.minSize = NSSize(width: 620, height: 400)

        super.init(window: window)
        window.delegate = self
        configureContent()
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
        setOutlineVisible(outlineSidebar.isHidden)
    }

    @objc func fitWidth(_ sender: Any?) {
        guard pages.indices.contains(currentPage) else { return }
        let availableWidth = max(120, scrollView.contentSize.width - 48)
        setZoom(availableWidth / pages[currentPage].width)
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
                if canvasView.pageViews.indices.contains(pageIndex) {
                    canvasView.pageViews[pageIndex].image = nil
                }
                requestRender(for: pageIndex)
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
                if canvasView.pageViews.indices.contains(pageIndex) {
                    canvasView.pageViews[pageIndex].image = nil
                }
                requestRender(for: pageIndex)
            } catch {
                present(error: error, title: "Could not undo annotation")
            }
        }
    }

    @objc func copySelection(_ sender: Any?) {
        for pageView in canvasView.pageViews where pageView.copySelection() {
            return
        }
    }

    func pageView(_ pageView: PageView, activated link: DocumentLink) {
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
        cancelPageWork()
        loadTask?.cancel()
        searchTask?.cancel()
        suspensionTask?.cancel()
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

    func windowDidResize(_ notification: Notification) {
        guard !pages.isEmpty else { return }
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        updateVisiblePages()
    }

    func windowDidResignKey(_ notification: Notification) {
        scheduleSuspension()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        suspensionTask?.cancel()
        suspensionTask = nil
        isSuspended = false
        suspensionToken = UUID()
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

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [
            back, previous, next, pageLabel, outlineButton, spacer,
            zoomOut, fit, zoomIn, zoomLabel,
            highlightButton, noteButton, save
        ])
        controls.orientation = .horizontal
        controls.spacing = 7
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(controls)

        let searchControls = NSStackView(views: [searchField, searchLabel, previousHit, nextHit])
        searchControls.orientation = .horizontal
        searchControls.spacing = 7
        searchControls.alignment = .centerY
        searchControls.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(searchControls)

        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(calibratedWhite: 0.89, alpha: 1)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = canvasView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipBoundsChanged(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        outlineSidebar.onActivate = { [weak self] entry in
            self?.activateOutlineEntry(entry)
        }
        outlineSidebar.translatesAutoresizingMaskIntoConstraints = false
        outlineSidebar.isHidden = true
        outlineButton.state = .off
        contentSplitView.isVertical = true
        contentSplitView.dividerStyle = .thin
        contentSplitView.translatesAutoresizingMaskIntoConstraints = false
        contentSplitView.addArrangedSubview(outlineSidebar)
        contentSplitView.addArrangedSubview(scrollView)

        root.addSubview(header)
        root.addSubview(contentSplitView)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 78),
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: header.topAnchor, constant: 7),
            searchControls.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            searchControls.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -7),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            contentSplitView.topAnchor.constraint(equalTo: header.bottomAnchor),
            contentSplitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentSplitView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
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
                let loadedOutline = (try? await engine.outline()) ?? []
                guard !Task.isCancelled else { return }
                outlineSidebar.install(loadedOutline)
                if !loadedOutline.isEmpty {
                    setOutlineVisible(true, relayoutDocument: false)
                    window?.contentView?.layoutSubtreeIfNeeded()
                }
                var loaded: [DocumentPage] = []
                loaded.reserveCapacity(pageCount)
                for index in 0..<pageCount {
                    loaded.append(try await engine.page(at: index))
                }
                guard !Task.isCancelled else { return }
                pages = loaded
                canvasView.install(pages: loaded, delegate: self, tool: tool)
                if shouldFitInitialPage, let first = loaded.first {
                    shouldFitInitialPage = false
                    let availableWidth = max(120, scrollView.contentSize.width - 48)
                    zoom = min(2, max(0.15, availableWidth / first.width))
                }
                canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
                zoomLabel.stringValue = "\(Int((zoom * 100).rounded()))%"
                pageLabel.stringValue = "1 / \(pageCount)"
                scroll(to: 0)
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
        updateVisiblePages()
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
                let request = PageRenderRequest(pageIndex: pageIndex, scale: requestedZoom * backingScale)
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
        relayoutDocument: Bool = true
    ) {
        outlineWidthConstraints.forEach { $0.isActive = false }
        outlineWidthConstraints.removeAll()
        outlineSidebar.isHidden = !visible
        outlineButton.state = visible ? .on : .off
        if visible {
            let preferred = outlineSidebar.widthAnchor.constraint(equalToConstant: 240)
            preferred.priority = .defaultHigh
            outlineWidthConstraints = [
                outlineSidebar.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
                outlineSidebar.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
                preferred
            ]
            NSLayoutConstraint.activate(outlineWidthConstraints)
        }
        guard relayoutDocument else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        canvasView.layoutPages(zoom: zoom, viewportWidth: scrollView.contentSize.width)
        updateVisiblePages()
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
        scrollView.contentView.scroll(to: origin)
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

    private func setZoom(
        _ requestedZoom: Double,
        anchor: DocumentViewportZoomAnchor? = nil,
        renderFinalImage: Bool = true
    ) {
        guard !pages.isEmpty else { return }
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
                if canvasView.pageViews.indices.contains(pageIndex) {
                    canvasView.pageViews[pageIndex].image = nil
                }
                requestRender(for: pageIndex)
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
