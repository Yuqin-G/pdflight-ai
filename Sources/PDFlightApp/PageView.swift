import AppKit
import PDFlightCore

enum ReaderTool {
    case select
    case note
}

@MainActor
protocol PageViewDelegate: AnyObject {
    func pageView(_ pageView: PageView, activated link: DocumentLink)
    func pageView(_ pageView: PageView, requestedNoteAt point: PagePoint)
    func pageView(_ pageView: PageView, magnifiedBy amount: CGFloat, phase: NSEvent.Phase)
}

@MainActor
final class PageView: NSView {
    private let imageView = PassthroughImageView()
    private let overlayView = PageOverlayView()
    weak var delegate: PageViewDelegate?
    var page: DocumentPage? {
        didSet { resetCursorRects() }
    }
    var textPage: DocumentTextPage? {
        didSet { overlayView.needsDisplay = true }
    }
    var image: NSImage? {
        didSet { imageView.image = image }
    }
    var zoom: Double = 1 {
        didSet { resetCursorRects() }
    }
    var tool: ReaderTool = .select {
        didSet {
            selectionAnchor = nil
            selectionEnd = nil
            window?.invalidateCursorRects(for: self)
            overlayView.needsDisplay = true
        }
    }
    var searchRects: [PageRect] = [] {
        didSet { overlayView.needsDisplay = true }
    }
    var activeSearchRects: [PageRect] = [] {
        didSet { overlayView.needsDisplay = true }
    }

    private var selectionAnchor: Int?
    private var selectionEnd: Int?
    private var pendingLink: DocumentLink?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.drawHandler = { [weak self] dirtyRect in
            self?.drawOverlay(dirtyRect)
        }
        addSubview(imageView)
        addSubview(overlayView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func drawOverlay(_ dirtyRect: NSRect) {

        NSColor.systemYellow.withAlphaComponent(0.24).setFill()
        searchRects.forEach { viewRect(for: $0).fill() }
        NSColor.systemOrange.withAlphaComponent(0.42).setFill()
        activeSearchRects.forEach { viewRect(for: $0).fill() }

        NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
        selectedGlyphs.forEach { viewRect(for: $0.rect).fill() }

    }

    override func resetCursorRects() {
        super.resetCursorRects()
        switch tool {
        case .note:
            addCursorRect(bounds, cursor: .crosshair)
        case .select:
            guard let page else { return }
            addCursorRect(bounds, cursor: .iBeam)
            for link in page.links {
                addCursorRect(viewRect(for: link.rect), cursor: .pointingHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = clamped(convert(event.locationInWindow, from: nil))
        let pagePoint = PagePoint(x: point.x / zoom, y: point.y / zoom)

        switch tool {
        case .note:
            delegate?.pageView(self, requestedNoteAt: pagePoint)
        case .select:
            pendingLink = page?.links.first { contains($0.rect, point: pagePoint) }
            if pendingLink == nil, let index = nearestGlyphIndex(to: pagePoint) {
                selectionAnchor = index
                selectionEnd = index
            } else if pendingLink == nil {
                selectionAnchor = nil
                selectionEnd = nil
            }
        }
        overlayView.needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))
        switch tool {
        case .select:
            pendingLink = nil
            let pagePoint = PagePoint(x: point.x / zoom, y: point.y / zoom)
            if let index = nearestGlyphIndex(to: pagePoint) {
                if selectionAnchor == nil { selectionAnchor = index }
                selectionEnd = index
            }
            autoscroll(with: event)
        case .note:
            break
        }
        overlayView.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .select:
            if let pendingLink {
                delegate?.pageView(self, activated: pendingLink)
            }
            pendingLink = nil
        case .note:
            break
        }
    }

    override func magnify(with event: NSEvent) {
        delegate?.pageView(self, magnifiedBy: event.magnification, phase: event.phase)
    }

    @objc func copy(_ sender: Any?) {
        _ = copySelection()
    }

    @discardableResult
    func copySelection() -> Bool {
        guard let selection = textSelection else { return false }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection.text, forType: .string)
        return true
    }

    var textSelection: DocumentTextSelection? {
        guard let textPage, let selectionAnchor, let selectionEnd else { return nil }
        return textPage.textSelection(from: selectionAnchor, through: selectionEnd)
    }

    func clearSelection() {
        selectionAnchor = nil
        selectionEnd = nil
        overlayView.needsDisplay = true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c",
           textSelection != nil {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var selectedGlyphs: ArraySlice<DocumentTextGlyph> {
        guard let glyphs = textPage?.glyphs,
              let selectionAnchor, let selectionEnd, !glyphs.isEmpty else { return [] }
        let lower = max(0, min(selectionAnchor, selectionEnd))
        let upper = min(glyphs.count - 1, max(selectionAnchor, selectionEnd))
        return glyphs[lower...upper]
    }

    private func nearestGlyphIndex(to point: PagePoint) -> Int? {
        guard let glyphs = textPage?.glyphs, !glyphs.isEmpty else { return nil }
        if let contained = glyphs.firstIndex(where: { contains($0.rect, point: point) }) {
            return contained
        }
        return glyphs.indices.min { left, right in
            distance(from: point, to: glyphs[left].rect) < distance(from: point, to: glyphs[right].rect)
        }
    }

    private func distance(from point: PagePoint, to rect: PageRect) -> Double {
        let dx = max(rect.x - point.x, 0, point.x - (rect.x + rect.width))
        let dy = max(rect.y - point.y, 0, point.y - (rect.y + rect.height))
        return dx * dx + dy * dy
    }

    private func viewRect(for rect: PageRect) -> CGRect {
        CGRect(
            x: rect.x * zoom,
            y: rect.y * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
    }

    private func contains(_ rect: PageRect, point: PagePoint) -> Bool {
        point.x >= rect.x && point.x <= rect.x + rect.width &&
            point.y >= rect.y && point.y <= rect.y + rect.height
    }

    private func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(0, point.x), bounds.width),
            y: min(max(0, point.y), bounds.height)
        )
    }
}

@MainActor
private final class PageOverlayView: NSView {
    var drawHandler: ((NSRect) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawHandler?(dirtyRect)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

@MainActor
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
