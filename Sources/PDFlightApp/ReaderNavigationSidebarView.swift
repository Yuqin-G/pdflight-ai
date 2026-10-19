import AppKit
import PDFlightCore

@MainActor
final class ReaderNavigationSidebarView: NSVisualEffectView {
    var onResizeBy: ((CGFloat) -> Void)?
    var onModeChange: ((Int) -> Void)?
    private(set) var selectedMode = 0
    var onActivateOutline: ((DocumentOutlineEntry) -> Void)? {
        didSet { outlineSidebar.onActivate = onActivateOutline }
    }
    var onOpenPaper: ((URL) -> Void)? {
        didSet { librarySidebar.onOpenPaper = onOpenPaper }
    }

    private let modeControl = NSSegmentedControl(labels: ["Library", "Outline"], trackingMode: .selectOne, target: nil, action: nil)
    private let librarySidebar: LibrarySidebarView
    private let outlineSidebar = OutlineSidebarView()
    private let resizeHandle = ReaderNavigationSidebarResizeHandle()

    init(store: PaperLibraryStore) {
        librarySidebar = LibrarySidebarView(store: store)
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installOutline(_ entries: [DocumentOutlineEntry]) {
        outlineSidebar.install(entries)
    }

    func reloadLibrary() {
        librarySidebar.reload()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if point.x >= bounds.maxX - 14, bounds.contains(point) {
            return resizeHandle
        }
        return super.hitTest(point)
    }

    private func configure() {
        material = .sidebar
        blendingMode = .withinWindow
        state = .active
        translatesAutoresizingMaskIntoConstraints = false

        modeControl.selectedSegment = 0
        modeControl.controlSize = .small
        modeControl.selectedSegmentBezelColor = AIChatClaudePalette.chipSelectedBackground
        modeControl.target = self
        modeControl.action = #selector(modeChanged(_:))
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        librarySidebar.translatesAutoresizingMaskIntoConstraints = false
        outlineSidebar.translatesAutoresizingMaskIntoConstraints = false
        outlineSidebar.isHidden = true
        resizeHandle.onDrag = { [weak self] delta in self?.onResizeBy?(delta) }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.setAccessibilityElement(true)
        resizeHandle.setAccessibilityRole(.splitter)
        resizeHandle.setAccessibilityLabel("Resize library sidebar")

        addSubview(modeControl)
        addSubview(librarySidebar)
        addSubview(outlineSidebar)
        addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            modeControl.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            modeControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            modeControl.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: -5),
            librarySidebar.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 4),
            librarySidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            librarySidebar.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor),
            librarySidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            outlineSidebar.topAnchor.constraint(equalTo: modeControl.bottomAnchor, constant: 4),
            outlineSidebar.leadingAnchor.constraint(equalTo: leadingAnchor),
            outlineSidebar.trailingAnchor.constraint(equalTo: resizeHandle.leadingAnchor),
            outlineSidebar.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 9)
        ])
    }

    /// 0 = Library, 1 = Outline. `notify` is false when restoring a
    /// persisted/cross-window mode so we don't echo the change back.
    func selectMode(_ mode: Int, notify: Bool = true) {
        let clamped = mode == 1 ? 1 : 0
        selectedMode = clamped
        modeControl.selectedSegment = clamped
        let showLibrary = clamped == 0
        librarySidebar.isHidden = !showLibrary
        outlineSidebar.isHidden = showLibrary
        if showLibrary { librarySidebar.reload() }
        if notify { onModeChange?(clamped) }
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        selectMode(sender.selectedSegment)
    }
}

@MainActor
private final class ReaderNavigationSidebarResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private var previousWindowX: CGFloat?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.65).setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }

    override func mouseDown(with event: NSEvent) {
        previousWindowX = event.locationInWindow.x
        guard let window else { return }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { break }
            guard let previousWindowX else { break }
            let currentX = next.locationInWindow.x
            self.previousWindowX = currentX
            onDrag?(currentX - previousWindowX)
        }
        previousWindowX = nil
    }
}
