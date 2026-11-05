import AppKit
import PDFlightCore

/// Spotlight-style panel for ⌘P quick document switching: type to filter
/// the paper library, ↑/↓ to move, ⏎ to open, Esc to dismiss.
@MainActor
final class QuickOpenPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {

    var onSelect: ((URL) -> Void)?

    private let searchField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var allPapers: [PaperLibraryPaper] = []
    private var filtered: [PaperLibraryPaper] = []
    private var library = PaperLibrarySnapshot()
    private weak var previousKeyWindow: NSWindow?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        searchField.placeholderString = "Type a paper title to open…"
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.font = .systemFont(ofSize: 18, weight: .light)
        searchField.delegate = self

        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        tableView.headerView = nil
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.target = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("paper"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        scrollView.documentView = tableView

        let separator = NSBox()
        separator.boxType = .separator

        let stack = NSStackView(views: [searchField, separator, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor),
            searchField.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -14),
            searchField.heightAnchor.constraint(equalToConstant: 28),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    func show(library: PaperLibrarySnapshot, relativeTo anchorWindow: NSWindow? = nil) {
        self.library = library
        previousKeyWindow = anchorWindow ?? NSApp.keyWindow
        allPapers = library.papers.sorted {
            ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt)
        }
        searchField.stringValue = ""
        applyFilter()
        if let screen = previousKeyWindow?.screen ?? NSScreen.main {
            let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
            let anchor = previousKeyWindow?.frame ?? bounds
            let width = min(800, anchor.width, bounds.width)
            setContentSize(NSSize(width: width, height: min(360, bounds.height)))
            setFrameOrigin(NSPoint(
                x: min(max(anchor.midX - frame.width / 2, bounds.minX), bounds.maxX - frame.width),
                y: min(max(anchor.midY - frame.height / 2, bounds.minY), bounds.maxY - frame.height)
            ))
        }
        makeKeyAndOrderFront(nil)
        makeFirstResponder(searchField)
    }

    override func close() {
        super.close()
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    private func applyFilter() {
        let query = searchField.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        filtered = query.isEmpty ? allPapers : allPapers.filter {
            $0.displayTitle.lowercased().contains(query)
                || $0.title.lowercased().contains(query)
                || $0.path.lowercased().contains(query)
        }
        tableView.reloadData()
        if !filtered.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func openSelection() {
        let row = tableView.selectedRow
        guard filtered.indices.contains(row) else { return }
        let url = filtered[row].fileURL
        close()
        onSelect?(url)
    }

    @objc private func tableDoubleClicked(_ sender: Any?) {
        openSelection()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(insertNewline(_:)):
            openSelection()
            return true
        case #selector(moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let next = min(max(tableView.selectedRow + delta, 0), filtered.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        filtered.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ReaderWarmTableRowView()
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let paper = filtered[row]
        let identifier = NSUserInterfaceItemIdentifier("QuickOpenRow")
        let cell: QuickOpenPaperCell
        if let reused = tableView.makeView(
            withIdentifier: identifier, owner: nil
        ) as? QuickOpenPaperCell {
            cell = reused
        } else {
            cell = QuickOpenPaperCell()
            cell.identifier = identifier
        }
        let collection = library.collections.first { $0.id == paper.collectionID }
        var names = collection.map { [$0.name] } ?? ["Default"]
        var parent = collection?.parentID
        var seen = Set<String>()
        while let id = parent, seen.insert(id).inserted,
              let ancestor = library.collections.first(where: { $0.id == id }) {
            names.insert(ancestor.name, at: 0)
            parent = ancestor.parentID
        }
        let path = names.joined(separator: " / ")
        cell.textField?.stringValue = paper.displayTitle
        cell.badge.stringValue = collection?.name ?? "Default"
        cell.badge.toolTip = path
        cell.badge.setAccessibilityLabel("Collection: \(path)")
        cell.toolTip = "\(paper.displayTitle)\nCollection: \(path)\n\(paper.path)"
        return cell
    }
}

@MainActor
private final class QuickOpenPaperCell: NSTableCellView {
    let badge = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        let title = NSTextField(labelWithString: "")
        title.font = .systemFont(ofSize: 13)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.font = .systemFont(ofSize: 11, weight: .medium)
        badge.textColor = .secondaryLabelColor
        badge.lineBreakMode = .byTruncatingMiddle
        badge.maximumNumberOfLines = 1
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badge.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        badge.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        for view in [title, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = title
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: badge.leadingAnchor, constant: -12),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            badge.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.3),
            badge.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
