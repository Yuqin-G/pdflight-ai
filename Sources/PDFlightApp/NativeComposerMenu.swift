import AppKit

/// The floating command menu used above the paper chat composer.
@MainActor
final class NativeComposerMenu: NSViewController {
    struct Item {
        let title: String
        let token: String
        let detail: String
        let symbol: String
        let action: () -> Void
    }

    private let width: CGFloat
    private let groups: [(String, [Item])]
    private let dismiss: () -> Void
    private var rows: [NativeComposerMenuRow] = []
    private var selectedIndex = 0

    init(width: CGFloat, groups: [(String, [Item])], dismiss: @escaping () -> Void) {
        self.width = width; self.groups = groups; self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
        var height: CGFloat = 16
        for (label, items) in groups where !items.isEmpty {
            let heading = NSTextField(labelWithString: label); heading.font = .systemFont(ofSize: 11)
            heading.textColor = NativeHarnessStyle.secondary
            let container = NSStackView(views: [heading]); container.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 4, right: 8)
            container.heightAnchor.constraint(equalToConstant: 25).isActive = true
            stack.addArrangedSubview(container); height += 25
            for item in items {
                let row = NativeComposerMenuRow(item: item) { [weak self] in self?.dismiss(); item.action() }
                rows.append(row)
                row.heightAnchor.constraint(equalToConstant: 34).isActive = true
                stack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -10).isActive = true
                height += 34
            }
        }
        preferredContentSize = NSSize(width: width, height: height)
        view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize)); view.wantsLayer = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.layer?.backgroundColor = NativeHarnessStyle.menu.cgColor }
        view.layer?.cornerRadius = 9; view.layer?.borderWidth = 0.5; view.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                     stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        rows.first?.keyboardHighlighted = true
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard !rows.isEmpty else { return false }
        switch event.keyCode {
        case 125, 126:
            rows[selectedIndex].keyboardHighlighted = false
            selectedIndex = (selectedIndex + (event.keyCode == 125 ? 1 : rows.count - 1)) % rows.count
            rows[selectedIndex].keyboardHighlighted = true
            return true
        case 36, 76:
            rows[selectedIndex].performClick(nil)
            return true
        default: return false
        }
    }
}

private final class NativeComposerMenuRow: NSButton {
    private let item: NativeComposerMenu.Item
    private let perform: () -> Void
    private var hovered = false
    var keyboardHighlighted = false { didSet { needsDisplay = true } }
    init(item: NativeComposerMenu.Item, perform: @escaping () -> Void) {
        self.item = item; self.perform = perform
        super.init(frame: .zero); title = ""; isBordered = false; target = self; action = #selector(invoke)
        setAccessibilityLabel(item.title + " " + item.token)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        if hovered || keyboardHighlighted { NativeHarnessStyle.primary.withAlphaComponent(0.055).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill() }
        let iconRect = NSRect(x: 8, y: (bounds.height - 14) / 2, width: 14, height: 14)
        NSImage(systemSymbolName: item.symbol, accessibilityDescription: nil)?.draw(in: iconRect)
        let title = NSMutableAttributedString(string: item.title, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NativeHarnessStyle.primary])
        title.append(NSAttributedString(string: "  " + item.token, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NativeHarnessStyle.secondary]))
        title.draw(at: NSPoint(x: 29, y: (bounds.height - title.size().height) / 2))
        let detail = NSAttributedString(string: item.detail, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NativeHarnessStyle.secondary])
        let available = max(0, bounds.width - 40 - title.size().width)
        if detail.size().width < available { detail.draw(at: NSPoint(x: bounds.width - 10 - detail.size().width, y: (bounds.height - detail.size().height) / 2)) }
    }
    @objc private func invoke() { perform() }
}
