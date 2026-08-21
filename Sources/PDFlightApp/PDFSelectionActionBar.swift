import AppKit

enum PDFSelectionActionBarPlacement {
    static let gap: CGFloat = 9
    static let edgeInset: CGFloat = 10

    static func frame(anchor: NSRect, in container: NSRect, barSize: NSSize) -> NSRect {
        let minimumX = container.minX + edgeInset
        let maximumX = max(minimumX, container.maxX - edgeInset - barSize.width)
        let centeredX = anchor.midX - barSize.width / 2
        let x = min(max(centeredX, minimumX), maximumX)

        let aboveY = anchor.maxY + gap
        let belowY = anchor.minY - gap - barSize.height
        let minimumY = container.minY + edgeInset
        let maximumY = max(minimumY, container.maxY - edgeInset - barSize.height)
        let preferredY = aboveY + barSize.height <= container.maxY - edgeInset
            ? aboveY
            : belowY
        let y = min(max(preferredY, minimumY), maximumY)
        return NSRect(origin: NSPoint(x: x, y: y), size: barSize)
    }
}

@MainActor
final class PDFSelectionActionBar: NSVisualEffectView {
    static let preferredSize = NSSize(width: 252, height: 44)

    var onCopy: (() -> Void)?
    var onHighlight: (() -> Void)?
    var onAskAI: (() -> Void)?

    private let copyButton = NSButton()
    private let highlightButton = NSButton()
    private let askAIButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 12
        layer?.shadowOffset = NSSize(width: 0, height: -3)

        configure(copyButton, title: "Copy", symbol: "doc.on.doc", action: #selector(copyPressed(_:)))
        configure(
            highlightButton,
            title: "Highlight",
            symbol: "highlighter",
            action: #selector(highlightPressed(_:))
        )
        configure(askAIButton, title: "Ask AI", symbol: "sparkles", action: #selector(askAIPressed(_:)))

        let firstSeparator = makeSeparator()
        let secondSeparator = makeSeparator()
        let stack = NSStackView(views: [copyButton, firstSeparator, highlightButton, secondSeparator, askAIButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            firstSeparator.heightAnchor.constraint(equalToConstant: 21),
            secondSeparator.heightAnchor.constraint(equalToConstant: 21)
        ])
        setAccessibilityRole(.group)
        setAccessibilityLabel("Selected text actions")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure(_ button: NSButton, title: String, symbol: String, action: Selector) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.bezelStyle = .recessed
        button.isBordered = false
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    @objc private func copyPressed(_ sender: Any?) {
        onCopy?()
    }

    @objc private func highlightPressed(_ sender: Any?) {
        onHighlight?()
    }

    @objc private func askAIPressed(_ sender: Any?) {
        onAskAI?()
    }

    func actionTitlesForLayoutCheck() -> [String] {
        [copyButton.title, highlightButton.title, askAIButton.title]
    }
}
