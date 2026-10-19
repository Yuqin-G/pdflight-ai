import AppKit
import PDFlightCore

@MainActor
final class OutlineSidebarView: NSVisualEffectView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onActivate: ((DocumentOutlineEntry) -> Void)?

    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No document outline")
    private var roots: [OutlineItem] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .sidebar
        blendingMode = .withinWindow
        state = .active

        let heading = NSTextField(labelWithString: "OUTLINE")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .outlineColumn)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.rowHeight = 25
        outlineView.indentationPerLevel = 13
        outlineView.style = .sourceList
        outlineView.setAccessibilityLabel("Document outline")
        outlineView.dataSource = self
        outlineView.delegate = self

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = outlineView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(heading)
        addSubview(scrollView)
        addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            heading.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            heading.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 7),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func install(_ entries: [DocumentOutlineEntry]) {
        roots = entries.map(OutlineItem.init)
        emptyLabel.isHidden = !roots.isEmpty
        scrollView.isHidden = roots.isEmpty
        outlineView.reloadData()
        expandInitiallyOpenItems(in: roots)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        children(of: item).count
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let item = item as? OutlineItem else { return false }
        return !item.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let item = item as? OutlineItem else { return nil }
        let cell: OutlineCellView
        if let reused = outlineView.makeView(
            withIdentifier: .outlineCell,
            owner: self
        ) as? OutlineCellView {
            cell = reused
        } else {
            cell = OutlineCellView()
            cell.identifier = .outlineCell
        }
        cell.configure(title: item.entry.title, pageIndex: item.entry.pageIndex)
        return cell
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        rowViewForItem item: Any
    ) -> NSTableRowView? {
        ReaderWarmTableRowView()
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row) as? OutlineItem else { return }
        onActivate?(item.entry)
    }

    private func children(of item: Any?) -> [OutlineItem] {
        (item as? OutlineItem)?.children ?? roots
    }

    private func expandInitiallyOpenItems(in items: [OutlineItem]) {
        for item in items {
            if item.entry.isInitiallyExpanded {
                outlineView.expandItem(item)
            }
            expandInitiallyOpenItems(in: item.children)
        }
    }
}

/// Warm-tinted list row selection shared by the sidebars and the
/// quick-open panel, replacing the cool system accent fill.
final class ReaderWarmTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        AIChatClaudePalette.selectionFill.setFill()
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: 4, dy: 0.5),
            xRadius: 6,
            yRadius: 6
        ).fill()
    }
}

private final class OutlineItem {
    let entry: DocumentOutlineEntry
    let children: [OutlineItem]

    init(_ entry: DocumentOutlineEntry) {
        self.entry = entry
        self.children = entry.children.map(OutlineItem.init)
    }
}

@MainActor
private final class OutlineCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let pageLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        pageLabel.textColor = .tertiaryLabelColor
        pageLabel.alignment = .right
        pageLabel.setContentHuggingPriority(.required, for: .horizontal)
        pageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        addSubview(pageLabel)
        textField = titleLabel

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 6),
            pageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            pageLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, pageIndex: Int?) {
        titleLabel.stringValue = title.isEmpty ? "Untitled" : title
        pageLabel.stringValue = pageIndex.map { "\($0 + 1)" } ?? ""
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let outlineColumn = NSUserInterfaceItemIdentifier("PDFlightOutlineColumn")
    static let outlineCell = NSUserInterfaceItemIdentifier("PDFlightOutlineCell")
}
