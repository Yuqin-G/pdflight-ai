import AppKit
import PDFlightCore

@MainActor
enum ReaderGroupOrder {
    static let key = "reader.libraryGroupOrder"

    static func ids(in library: PaperLibrarySnapshot) -> [String] {
        let valid = ReaderTabGroups.orderedIDs(in: library)
        var result = [ReaderTabGroups.defaultID]
        for id in (UserDefaults.standard.stringArray(forKey: key) ?? []) + valid
            where valid.contains(id) && !result.contains(id) { result.append(id) }
        return result
    }
}

@MainActor
private final class DraggableGroupButton: NSButton {
    var groupID = ""
    weak var groupRow: GroupTabRow?
    var tabWidth: CGFloat?
    var onClose: (() -> Void)?
    private var closeButton: NSButton?
    var isDocumentTab = false
    private var isHovered = false
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        super.updateTrackingAreas()
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .enabledDuringMouseDrag], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        guard isDocumentTab else { super.draw(dirtyRect); return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let selected = state == .on
        let active = isHovered || cell?.isHighlighted == true
        let fill: NSColor
        if dark {
            fill = NSColor(calibratedRed: selected ? 0.34 : active ? 0.29 : 0.24,
                           green: selected ? 0.34 : active ? 0.29 : 0.24,
                           blue: selected ? 0.32 : active ? 0.28 : 0.23, alpha: 1)
        } else {
            fill = NSColor(calibratedRed: selected ? 0.84 : active ? 0.89 : 0.94,
                           green: selected ? 0.83 : active ? 0.88 : 0.93,
                           blue: selected ? 0.79 : active ? 0.85 : 0.90, alpha: 1)
        }
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 6, yRadius: 6)
        fill.setFill(); shape.fill()
        (selected ? NSColor.secondaryLabelColor.withAlphaComponent(0.65) : NSColor.separatorColor).setStroke()
        shape.lineWidth = selected ? 1 : 0.75
        shape.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let textFont = font ?? .systemFont(ofSize: 12)
        let height = textFont.ascender - textFont.descender
        title.draw(in: NSRect(x: 10, y: (bounds.height - height) / 2 - 1,
                              width: max(0, bounds.width - 40), height: height + 2),
                   withAttributes: [.font: textFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }

    func configureClose(_ action: @escaping () -> Void) {
        onClose = action
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close paper")!,
                             target: self, action: #selector(closePaper))
        close.isBordered = false
        close.controlSize = .mini
        close.contentTintColor = .secondaryLabelColor
        close.frame = NSRect(x: (tabWidth ?? 180) - 24, y: 6, width: 18, height: 18)
        addSubview(close)
        closeButton = close
    }

    @objc private func closePaper() { onClose?() }

    override func mouseDown(with event: NSEvent) {
        guard groupID != ReaderTabGroups.defaultID || groupRow?.allowsFirstTabMove == true else { super.mouseDown(with: event); return }
        groupRow?.track(self, from: event)
    }
}

/// Move the actual colored button above a vacant slot. Neighboring buttons animate
/// into their new slots during tracking; no pasteboard or system drag image is used.
@MainActor
private final class GroupTabRow: NSView {
    private(set) var groupButtons: [DraggableGroupButton] = []
    private(set) var isTracking = false
    private weak var movingButton: DraggableGroupButton?
    private let placeholder = NSView()
    var onFinish: (([String]) -> Void)?
    var allowsFirstTabMove = false
    var onHover: ((String, NSPoint?) -> Bool)?
    var onDrop: ((String, NSPoint) -> Bool)?

    func setButtons(_ buttons: [DraggableGroupButton]) {
        subviews.forEach { $0.removeFromSuperview() }
        groupButtons = buttons
        wantsLayer = true
        placeholder.wantsLayer = true
        placeholder.layer?.cornerRadius = 5
        placeholder.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        placeholder.isHidden = true
        addSubview(placeholder)
        for button in buttons {
            button.groupRow = self
            button.wantsLayer = true
            addSubview(button)
        }
        let width = buttons.reduce(CGFloat(12)) { $0 + ($1.tabWidth ?? max(50, $1.fittingSize.width)) + 6 }
        setFrameSize(NSSize(width: width, height: 38))
        placeButtons(animated: false)
    }

    private var slots: [NSRect] {
        var x: CGFloat = 6
        return groupButtons.map { button in
            let width = button.tabWidth ?? max(50, button.fittingSize.width)
            defer { x += width + 6 }
            return NSRect(x: x, y: 4, width: width, height: 30)
        }
    }

    private func placeButtons(animated: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.14 : 0
            context.allowsImplicitAnimation = animated
            for (button, slot) in zip(groupButtons, slots) {
                if button === movingButton { placeholder.frame = slot; continue }
                if animated { button.animator().setFrameOrigin(slot.origin) }
                else { button.frame = slot }
            }
        }
    }

    func track(_ button: DraggableGroupButton, from event: NSEvent) {
        guard !isTracking, let window else { return }
        isTracking = true
        let originalOrder = groupButtons
        let start = event.locationInWindow
        let grabOffset = convert(start, from: nil).x - button.frame.minX
        var didDrag = false
        var cancelled = false
        var lastPoint = start
        var dragCenter: CGFloat = 0
        let overlay = allowsFirstTabMove ? enclosingScrollView?.superview : nil
        button.highlight(true)
        while true {
            // A tracking-mode tick also scrolls at the edge while the pointer is still.
            let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown],
                                       until: Date(timeIntervalSinceNow: 1.0 / 60),
                                       inMode: .eventTracking, dequeue: true)
            if next?.type == .keyDown {
                if next?.keyCode == 53 { cancelled = true; break }
                continue
            }
            if next?.type == .leftMouseUp {
                lastPoint = next!.locationInWindow
                if !didDrag {
                    let inside = button.bounds.contains(button.convert(next!.locationInWindow, from: nil))
                    button.highlight(false)
                    isTracking = false
                    if inside { button.performClick(nil) }
                    return
                }
                break
            }
            guard window.isVisible, NSApp.isActive else { cancelled = true; break }
            let point = next?.locationInWindow ?? window.mouseLocationOutsideOfEventStream
            lastPoint = point
            if !didDrag {
                guard hypot(point.x - start.x, point.y - start.y) >= 5 else { continue }
                didDrag = true
                movingButton = button
                button.highlight(false)
                placeholder.isHidden = false
                if let overlay {
                    let liftedFrame = convert(button.frame, to: overlay)
                    overlay.addSubview(button, positioned: .above, relativeTo: nil)
                    button.frame = liftedFrame
                } else { addSubview(button, positioned: .above, relativeTo: nil) }
                button.layer?.shadowColor = NSColor.black.cgColor
                button.layer?.shadowOpacity = 0.2
                button.layer?.shadowRadius = 4
                button.layer?.shadowOffset = NSSize(width: 0, height: -1)
                NSCursor.closedHand.push()
                placeButtons(animated: false)
            }
            scrollAtEdge(point)
            let minimumX: CGFloat = allowsFirstTabMove ? 6 : (slots.first?.maxX ?? 0) + 6
            let local = convert(point, from: nil)
            let x = overlay != nil ? local.x - grabOffset
                : min(max(local.x - grabOffset, minimumX), bounds.maxX - button.frame.width - 6)
            let dragFrame = NSRect(x: x, y: overlay == nil ? 4 : local.y - 15,
                                   width: button.frame.width, height: 30)
            button.frame = overlay.map { convert(dragFrame, to: $0) } ?? dragFrame
            dragCenter = dragFrame.midX
            if onHover?(button.groupID, point) == true { continue }
            let center = dragCenter
            var index = groupButtons.firstIndex(of: button)!
            var changed = false
            while index > (allowsFirstTabMove ? 0 : 1) && center < slots[index - 1].midX {
                groupButtons.swapAt(index, index - 1)
                index -= 1
                changed = true
            }
            while index + 1 < groupButtons.count && center > slots[index + 1].midX {
                groupButtons.swapAt(index, index + 1)
                index += 1
                changed = true
            }
            if changed { placeButtons(animated: true) }
        }
        button.highlight(false)
        _ = onHover?(button.groupID, nil)
        let dropped = didDrag && !cancelled && (onDrop?(button.groupID, lastPoint) == true)
        if let overlay, button.superview === overlay {
            let returnedFrame = convert(button.frame, from: overlay)
            addSubview(button, positioned: .above, relativeTo: nil)
            button.frame = returnedFrame
        }
        if cancelled || dropped { groupButtons = originalOrder }
        guard didDrag else {
            isTracking = false
            onFinish?(dropped ? [] : groupButtons.map(\.groupID))
            return
        }
        NSCursor.pop()
        movingButton = nil
        if dropped { button.isHidden = true }
        placeButtons(animated: true)
        // Leave the slot in place until the whole tab has settled into it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak button] in
            guard let self else { return }
            button?.layer?.shadowOpacity = 0
            button?.isHidden = false
            placeholder.isHidden = true
            isTracking = false
            onFinish?(dropped ? [] : groupButtons.map(\.groupID))
        }
    }

    fileprivate func scrollAtEdge(_ windowPoint: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let point = clip.convert(windowPoint, from: nil)
        let viewport = clip.bounds
        let edge: CGFloat = min(36, viewport.width / 4)
        let delta: CGFloat
        if point.x < viewport.minX + edge { delta = -min(14, (viewport.minX + edge - point.x) * 0.4) }
        else if point.x > viewport.maxX - edge { delta = min(14, (point.x - viewport.maxX + edge) * 0.4) }
        else { return }
        let x = min(max(viewport.minX + delta, 0), max(0, bounds.width - viewport.width))
        clip.scroll(to: NSPoint(x: x, y: viewport.minY))
        scroll.reflectScrolledClipView(clip)
    }
}

/// The standard window toolbar sits above AppKit's document tab bar.
@MainActor
final class ReaderGroupToolbar: NSObject, NSToolbarDelegate {
    private let scroll = NSScrollView()
    private let row = GroupTabRow()
    private let documentScroll = NSScrollView()
    private let documentRow = GroupTabRow()
    private let container = NSStackView()
    private var documentSignature: [String] = []
    private var pendingDocuments: [ReaderDocumentTab]?
    private var dropTargetID: String?
    private var pendingUpdate: (PaperLibrarySnapshot, String)?
    var onReorder: (() -> Void)?
    var onSelectDocument: ((String) -> Void)?
    var onCloseDocument: ((String) -> Void)?
    var onReorderDocuments: (([String]) -> Void)?
    var onMoveDocument: ((String, String) -> Void)?
    private var displayedIDs: [String] = []
    private var displayedLabels: [String] = []
    private var displayedSelection: String?
    private var onSelect: (String) -> Void
    private var buttons: [NSButton: String] = [:]
    private let toolbar = NSToolbar(identifier: "PDFlightGroups")
    private static let itemID = NSToolbarItem.Identifier("PDFlightGroupTabs")

    init(window: NSWindow, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        super.init()
        row.onFinish = { [weak self] ids in
            guard let self else { return }
            UserDefaults.standard.set(ids, forKey: ReaderGroupOrder.key)
            if let (library, selectedID) = pendingUpdate {
                pendingUpdate = nil
                update(library: library, selectedID: selectedID)
            }
            onReorder?()
        }
        documentRow.allowsFirstTabMove = true
        documentRow.onFinish = { [weak self] ids in
            guard let self else { return }
            if !ids.isEmpty { onReorderDocuments?(ids) }
            if let pendingDocuments {
                self.pendingDocuments = nil
                updateDocuments(pendingDocuments)
            }
            if let (library, selectedID) = pendingUpdate {
                pendingUpdate = nil
                update(library: library, selectedID: selectedID)
            }
        }
        documentRow.onHover = { [weak self] _, point in
            guard let self else { return false }
            if let point, scroll.contentView.bounds.contains(scroll.contentView.convert(point, from: nil)) {
                row.scrollAtEdge(point)
            }
            let id = point.flatMap { group(at: $0) }
            setDropTarget(id)
            return id != nil
        }
        documentRow.onDrop = { [weak self] documentID, point in
            guard let self, let id = group(at: point) else { return false }
            onMoveDocument?(documentID, id)
            return true
        }
        scroll.documentView = row
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.setContentHuggingPriority(.defaultLow, for: .horizontal)
        documentScroll.documentView = documentRow
        documentScroll.drawsBackground = false
        documentScroll.hasHorizontalScroller = true
        documentScroll.autohidesScrollers = true
        documentScroll.translatesAutoresizingMaskIntoConstraints = false
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 0
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addArrangedSubview(scroll)
        container.addArrangedSubview(documentScroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            scroll.widthAnchor.constraint(equalTo: container.widthAnchor),
            documentScroll.widthAnchor.constraint(equalTo: container.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 38),
            documentScroll.heightAnchor.constraint(equalToConstant: 38)
        ])
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .expanded
        window.toolbar = toolbar
    }

    func update(library: PaperLibrarySnapshot, selectedID: String) {
        if row.isTracking || documentRow.isTracking { pendingUpdate = (library, selectedID); return }
        let ids = ReaderGroupOrder.ids(in: library)
        let labels = ids.map { id in
            library.collections.first { ReaderTabGroups.collectionID($0.id) == id }
                .map { collectionPath($0, library: library) } ?? "Default"
        }
        guard ids != displayedIDs || labels != displayedLabels || selectedID != displayedSelection else { return }
        displayedIDs = ids
        displayedLabels = labels
        displayedSelection = selectedID
        buttons.removeAll()
        var groupButtons: [DraggableGroupButton] = []
        for id in ids {
            let collection = library.collections.first { ReaderTabGroups.collectionID($0.id) == id }
            let name = collection?.name ?? "Default"
            let button = DraggableGroupButton(title: name, target: self, action: #selector(selectGroup(_:)))
            button.groupID = id
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.state = id == selectedID ? .on : .off
            button.imagePosition = .imageLeading
            let color = Self.color(for: id)
            let dot = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
                color.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                return true
            }
            dot.isTemplate = false
            button.image = dot
            button.font = .systemFont(ofSize: 12, weight: id == selectedID ? .semibold : .regular)
            button.bezelColor = id == selectedID ? color : nil
            button.toolTip = collection.map { collectionPath($0, library: library) } ?? "Default"
            button.setAccessibilityLabel("Group: \(button.toolTip ?? name)")
            button.setAccessibilityIdentifier("reader.group.\(id)")
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            buttons[button] = id
            groupButtons.append(button)
        }
        row.setButtons(groupButtons)
    }

    func selectForLayoutCheck(_ id: String) -> Bool {
        guard let button = buttons.first(where: { $0.value == id })?.key else { return false }
        button.performClick(nil)
        return true
    }

    func titlesForLayoutCheck() -> [String] { row.groupButtons.map(\.title) }

    func updateDocuments(_ documents: [ReaderDocumentTab]) {
        if documentRow.isTracking { pendingDocuments = documents; return }
        let signature = documents.flatMap { [$0.id, $0.title, String($0.isSelected)] }
        guard signature != documentSignature else { return }
        documentSignature = signature
        let tabs = documents.map { document in
            let button = DraggableGroupButton(title: document.title, target: self, action: #selector(selectDocument(_:)))
            button.groupID = document.id
            button.isDocumentTab = true
            button.tabWidth = min(240, max(130, button.fittingSize.width + 30))
            button.bezelStyle = .texturedRounded
            button.setButtonType(.pushOnPushOff)
            button.state = document.isSelected ? .on : .off
            button.font = .systemFont(ofSize: 12, weight: document.isSelected ? .semibold : .regular)
            button.lineBreakMode = .byTruncatingTail
            // Leave the trailing edge free for the close control.
            button.image = NSImage(size: NSSize(width: 22, height: 1))
            button.imagePosition = .imageTrailing
            button.toolTip = document.title
            button.setAccessibilityLabel("Paper: \(document.title)")
            button.configureClose { [weak self] in self?.onCloseDocument?(document.id) }
            return button
        }
        documentRow.setButtons(tabs)
        if let (library, selectedID) = pendingUpdate {
            pendingUpdate = nil
            update(library: library, selectedID: selectedID)
        }
    }

    @objc private func selectDocument(_ sender: DraggableGroupButton) { onSelectDocument?(sender.groupID) }

    private func group(at point: NSPoint) -> String? {
        let clip = scroll.contentView
        guard clip.bounds.contains(clip.convert(point, from: nil)) else { return nil }
        let local = row.convert(point, from: nil)
        return row.groupButtons.first { $0.frame.contains(local) }?.groupID
    }

    private func setDropTarget(_ id: String?) {
        guard dropTargetID != id else { return }
        dropTargetID = id
        for button in row.groupButtons {
            button.layer?.borderWidth = button.groupID == id ? 2 : 0
            button.layer?.borderColor = NSColor.controlAccentColor.cgColor
            button.layer?.cornerRadius = 5
        }
    }

    private func collectionPath(_ collection: PaperLibraryCollection, library: PaperLibrarySnapshot) -> String {
        var names = [collection.name]
        var parent = collection.parentID
        var seen: Set<String> = [collection.id]
        while let id = parent, seen.insert(id).inserted,
              let item = library.collections.first(where: { $0.id == id }) {
            names.insert(item.name, at: 0)
            parent = item.parentID
        }
        return names.joined(separator: " / ")
    }

    static func color(for id: String) -> NSColor {
        if id == ReaderTabGroups.defaultID { return .secondaryLabelColor }
        // Fixed hash rather than Swift's process-randomized Hasher: renames and restarts keep color.
        let hash = id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return NSColor(calibratedHue: CGFloat(hash % 360) / 360, saturation: 0.62, brightness: 0.72, alpha: 1)
    }

    @objc private func selectGroup(_ sender: NSButton) {
        if let id = buttons[sender] { onSelect(id) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [Self.itemID] }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Groups"
        item.view = container
        item.minSize = NSSize(width: 240, height: 76)
        item.maxSize = NSSize(width: 10_000, height: 76)
        return item
    }
}

struct ReaderDocumentTab {
    let id: String
    let title: String
    let isSelected: Bool
}

/// A real window for a group with no documents; it never borrows another group's reader.
@MainActor
final class EmptyReaderGroupWindow: NSWindowController, NSWindowDelegate {
    var onActivate: (() -> Void)?
    var onClose: (() -> Void)?
    let library: LibrarySidebarView

    init(store: PaperLibraryStore) {
        library = LibrarySidebarView(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PDFlight"
        window.minSize = NSSize(width: 620, height: 400)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        let root = NSView()
        window.contentView = root
        let label = NSTextField(labelWithString: "Open a PDF from Library or File → Open…")
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(library)
        root.addSubview(label)
        NSLayoutConstraint.activate([
            library.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            library.topAnchor.constraint(equalTo: root.topAnchor),
            library.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            library.widthAnchor.constraint(equalToConstant: 240),
            label.centerXAnchor.constraint(equalTo: root.centerXAnchor, constant: 120),
            label.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowDidBecomeKey(_ notification: Notification) { onActivate?() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
