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
    private weak var previousKeyWindow: NSWindow?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
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
        searchField.font = .claudeSerif(ofSize: 19, weight: .regular)
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

    func show(papers: [PaperLibraryPaper]) {
        allPapers = papers.sorted {
            ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt)
        }
        searchField.stringValue = ""
        applyFilter()
        previousKeyWindow = NSApp.keyWindow
        if let screen = previousKeyWindow?.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            setFrameOrigin(NSPoint(
                x: frame.midX - frame.width / 2,
                y: frame.midY - frame.height / 4
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
        let cell: NSTableCellView
        if let reused = tableView.makeView(
            withIdentifier: identifier, owner: nil
        ) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingMiddle
            field.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(
                    equalTo: cell.leadingAnchor, constant: 14),
                field.trailingAnchor.constraint(
                    equalTo: cell.trailingAnchor, constant: -14),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            cell.identifier = identifier
        }
        let directory = URL(fileURLWithPath: paper.path)
            .deletingLastPathComponent().lastPathComponent
        cell.textField?.attributedStringValue = QuickOpenPanel.rowTitle(
            paper.displayTitle, directory: directory
        )
        cell.toolTip = paper.path
        return cell
    }

    private static func rowTitle(
        _ title: String, directory: String
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        if !directory.isEmpty {
            result.append(NSAttributedString(
                string: "  —  \(directory)",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            ))
        }
        return result
    }
}
