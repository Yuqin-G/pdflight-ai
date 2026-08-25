import AppKit
import PDFlightCore

extension Notification.Name {
    static let paperLibraryDidChange = Notification.Name("PDFlightPaperLibraryDidChange")
}

@MainActor
final class LibrarySidebarView: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    private static let paperPasteboardType = NSPasteboard.PasteboardType(
        "dev.pdflight.reader.library-paper-id"
    )
    var onOpenPaper: ((URL) -> Void)?

    private let store: PaperLibraryStore
    private let searchField = NSSearchField()
    private let outlineView = LibraryOutlineView()
    private let scrollView = NSScrollView()
    private let countLabel = NSTextField(labelWithString: "")
    private let addCollectionButton = NSButton()
    private let addPaperButton = NSButton()
    private var roots: [LibraryTreeItem] = []
    private var snapshot = PaperLibrarySnapshot()
    private var expandedCollectionIDs: Set<String> = []
    private var isRecentExpanded = false

    init(store: PaperLibraryStore) {
        self.store = store
        super.init(frame: .zero)
        configure()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(libraryChanged(_:)),
            name: .paperLibraryDidChange,
            object: nil
        )
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reload() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await store.snapshot()
                snapshot = loaded
                rebuildTree()
            } catch {
                present(error)
            }
        }
    }

    func paperDraggingEnabledForLayoutCheck() -> Bool {
        outlineView.registeredDraggedTypes.contains(Self.paperPasteboardType)
    }

    func multiplePaperSelectionEnabledForLayoutCheck() -> Bool {
        outlineView.allowsMultipleSelection
    }

    func recentHistoryStartsCollapsedForLayoutCheck() -> Bool {
        !isRecentExpanded
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false

        searchField.placeholderString = "Search library"
        searchField.controlSize = .small
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.translatesAutoresizingMaskIntoConstraints = false

        configureButton(addCollectionButton, symbol: "folder.badge.plus", tooltip: "New collection")
        addCollectionButton.action = #selector(addCollection(_:))
        configureButton(addPaperButton, symbol: "doc.badge.plus", tooltip: "Add PDFs")
        addPaperButton.action = #selector(addPapers(_:))

        countLabel.font = .systemFont(ofSize: 10)
        countLabel.textColor = .tertiaryLabelColor
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionRow = NSStackView(views: [addCollectionButton, addPaperButton, spacer, countLabel])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 6
        actionRow.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: .libraryColumn)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.rowHeight = 27
        outlineView.indentationPerLevel = 14
        outlineView.style = .sourceList
        outlineView.allowsMultipleSelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.doubleAction = #selector(openSelectedPaper(_:))
        outlineView.onReturn = { [weak self] in self?.openSelectedPaper(nil) }
        outlineView.setAccessibilityLabel("Paper library")
        outlineView.registerForDraggedTypes([Self.paperPasteboardType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.delegate = self
        outlineView.menu = menu

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = outlineView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(searchField)
        addSubview(actionRow)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionRow.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 7),
            actionRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            actionRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: actionRow.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func configureButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
    }

    private func rebuildTree() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingPapers: [PaperLibraryPaper]
        if query.isEmpty {
            matchingPapers = snapshot.papers
        } else {
            matchingPapers = snapshot.papers.filter {
                $0.displayTitle.localizedCaseInsensitiveContains(query)
                    || $0.title.localizedCaseInsensitiveContains(query)
                    || $0.path.localizedCaseInsensitiveContains(query)
            }
        }
        let matchingCollectionIDs = ancestorCollectionIDs(for: matchingPapers)
        roots = []
        if query.isEmpty {
            let recent = matchingPapers
                .filter { $0.lastOpenedAt != nil }
                .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            if !recent.isEmpty {
                roots.append(LibraryTreeItem.virtualRecent(
                    children: recent.prefix(20).map(LibraryTreeItem.paper)
                ))
            }
        }
        roots += buildCollections(parentID: nil, papers: matchingPapers, visibleCollectionIDs: matchingCollectionIDs)
        let unfiled = matchingPapers.filter { $0.collectionID == nil }.sorted(by: paperSort)
        if !unfiled.isEmpty {
            roots.append(LibraryTreeItem.virtualUnfiled(children: unfiled.map(LibraryTreeItem.paper)))
        }
        outlineView.reloadData()
        restoreExpansion(in: roots, expandAll: !query.isEmpty)
        countLabel.stringValue = "\(matchingPapers.count)"
    }

    private func buildCollections(
        parentID: String?,
        papers: [PaperLibraryPaper],
        visibleCollectionIDs: Set<String>
    ) -> [LibraryTreeItem] {
        snapshot.collections
            .filter { $0.parentID == parentID && visibleCollectionIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { collection in
                var children = buildCollections(
                    parentID: collection.id,
                    papers: papers,
                    visibleCollectionIDs: visibleCollectionIDs
                )
                children += papers
                    .filter { $0.collectionID == collection.id }
                    .sorted(by: paperSort)
                    .map(LibraryTreeItem.paper)
                return LibraryTreeItem.collection(collection, children: children)
            }
    }

    private func ancestorCollectionIDs(for papers: [PaperLibraryPaper]) -> Set<String> {
        guard !searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Set(snapshot.collections.map(\.id))
        }
        let byID = Dictionary(uniqueKeysWithValues: snapshot.collections.map { ($0.id, $0) })
        var result: Set<String> = []
        for paper in papers {
            var collectionID = paper.collectionID
            while let id = collectionID, result.insert(id).inserted {
                collectionID = byID[id]?.parentID
            }
        }
        return result
    }

    private func paperSort(_ lhs: PaperLibraryPaper, _ rhs: PaperLibraryPaper) -> Bool {
        lhs.displayTitle.localizedCaseInsensitiveCompare(rhs.displayTitle) == .orderedAscending
    }

    private func restoreExpansion(in items: [LibraryTreeItem], expandAll: Bool) {
        for item in items where item.isExpandable {
            let shouldExpand = expandAll
                || item.virtualKind == .unfiled
                || (item.virtualKind == .recent && isRecentExpanded)
                || item.collection.map({ expandedCollectionIDs.contains($0.id) }) == true
            if shouldExpand {
                outlineView.expandItem(item)
            }
            restoreExpansion(in: item.children, expandAll: expandAll)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        children(of: item).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        children(of: item)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? LibraryTreeItem)?.isExpandable == true
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let item = item as? LibraryTreeItem else { return nil }
        let cell = (outlineView.makeView(withIdentifier: .libraryCell, owner: self) as? NSTableCellView)
            ?? makeCell()
        cell.textField?.stringValue = item.title
        cell.textField?.toolTip = item.paper?.path ?? item.title
        cell.imageView?.image = NSImage(
            systemSymbolName: item.paper == nil
                ? (item.virtualKind == .recent ? "clock" : item.isVirtual ? "tray" : "folder")
                : "doc.text",
            accessibilityDescription: nil
        )
        cell.imageView?.contentTintColor = item.paper == nil ? .systemBlue : .secondaryLabelColor
        return cell
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? LibraryTreeItem {
            if let id = item.collection?.id {
                expandedCollectionIDs.insert(id)
            } else if item.virtualKind == .recent {
                isRecentExpanded = true
            }
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let item = notification.userInfo?["NSObject"] as? LibraryTreeItem {
            if let id = item.collection?.id {
                expandedCollectionIDs.remove(id)
            } else if item.virtualKind == .recent {
                isRecentExpanded = false
            }
        }
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {
        guard let paper = (item as? LibraryTreeItem)?.paper else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(paper.id, forType: Self.paperPasteboardType)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        let paperIDs = draggedPaperIDs(from: info.draggingPasteboard)
        guard info.draggingSource as? NSOutlineView === outlineView,
              !paperIDs.isEmpty,
              let target = item as? LibraryTreeItem,
              target.collection != nil || target.virtualKind == .unfiled else { return [] }
        let destinationID = target.collection?.id
        guard paperIDs.contains(where: { paperID in
            snapshot.papers.first(where: { $0.id == paperID })?.collectionID != destinationID
        }) else {
            return []
        }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        let paperIDs = draggedPaperIDs(from: info.draggingPasteboard)
        guard !paperIDs.isEmpty,
              let target = item as? LibraryTreeItem,
              target.collection != nil || target.virtualKind == .unfiled else { return false }
        let destinationID = target.collection?.id
        if let destinationID {
            expandedCollectionIDs.insert(destinationID)
        }
        mutate { store in
            try await store.movePapers(paperIDs, to: destinationID)
        }
        return true
    }

    private func draggedPaperIDs(from pasteboard: NSPasteboard) -> [String] {
        var seen: Set<String> = []
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard let id = item.string(forType: Self.paperPasteboardType),
                  seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private func makeCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .libraryCell
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(icon)
        cell.addSubview(label)
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func children(of item: Any?) -> [LibraryTreeItem] {
        (item as? LibraryTreeItem)?.children ?? roots
    }

    @objc private func openSelectedPaper(_ sender: Any?) {
        for paper in selectedPapers() {
            guard FileManager.default.fileExists(atPath: paper.path) else {
                present(PaperLibraryUIError.missingFile(paper.path))
                continue
            }
            onOpenPaper?(paper.fileURL)
        }
    }

    @objc private func searchChanged(_ sender: Any?) { rebuildTree() }
    @objc private func libraryChanged(_ notification: Notification) { reload() }

    @objc private func addCollection(_ sender: Any?) {
        let parentID = selectedItem()?.collection?.id
        let alert = NSAlert()
        alert.messageText = parentID == nil ? "New collection" : "New subcollection"
        alert.informativeText = "Collections can be nested to any depth."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Collection name"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { store in
            _ = try await store.createCollection(name: field.stringValue, parentID: parentID)
        }
    }

    @objc private func addPapers(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let collectionID = selectedItem()?.collection?.id
        mutate { store in
            for url in panel.urls { _ = try await store.addPaper(at: url, to: collectionID) }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clickedRow = outlineView.clickedRow
        guard clickedRow >= 0, let item = outlineView.item(atRow: clickedRow) as? LibraryTreeItem else { return }
        if !outlineView.selectedRowIndexes.contains(clickedRow) {
            outlineView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        if let collection = item.collection {
            addMenuItem(menu, title: "New subcollection", action: #selector(addCollection(_:)), id: collection.id)
            addMenuItem(menu, title: "Rename…", action: #selector(renameCollection(_:)), id: collection.id)
            menu.addItem(.separator())
            addMenuItem(menu, title: "Delete collection", action: #selector(deleteCollection(_:)), id: collection.id)
        } else if let paper = item.paper {
            let selectedIDs = selectedPapers().map(\.id)
            let paperIDs = selectedIDs.contains(paper.id) ? selectedIDs : [paper.id]
            addMenuItem(
                menu,
                title: paperIDs.count == 1 ? "Open" : "Open \(paperIDs.count) Papers",
                action: #selector(openSelectedPaper(_:)),
                id: paper.id
            )
            if paperIDs.count == 1 {
                addMenuItem(
                    menu,
                    title: "Edit display name…",
                    action: #selector(editPaperDisplayName(_:)),
                    id: paper.id
                )
            }
            let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
            move.submenu = moveMenu(for: paperIDs)
            menu.addItem(move)
            menu.addItem(.separator())
            let remove = NSMenuItem(
                title: paperIDs.count == 1 ? "Remove from library" : "Remove \(paperIDs.count) from library",
                action: #selector(removePapers(_:)),
                keyEquivalent: ""
            )
            remove.target = self
            remove.representedObject = LibraryPaperSelection(ids: paperIDs)
            menu.addItem(remove)
        }
    }

    private func addMenuItem(_ menu: NSMenu, title: String, action: Selector, id: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        menu.addItem(item)
    }

    private func moveMenu(for paperIDs: [String]) -> NSMenu {
        let menu = NSMenu()
        addMoveMenuItem(menu, title: "Unfiled", paperIDs: paperIDs, destinationID: nil)
        for collection in snapshot.collections.sorted(by: { collectionPath($0).localizedCaseInsensitiveCompare(collectionPath($1)) == .orderedAscending }) {
            addMoveMenuItem(
                menu,
                title: collectionPath(collection),
                paperIDs: paperIDs,
                destinationID: collection.id
            )
        }
        return menu
    }

    private func addMoveMenuItem(
        _ menu: NSMenu,
        title: String,
        paperIDs: [String],
        destinationID: String?
    ) {
        let item = NSMenuItem(title: title, action: #selector(movePapers(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = LibraryPaperMove(ids: paperIDs, destinationID: destinationID)
        menu.addItem(item)
    }

    private func collectionPath(_ collection: PaperLibraryCollection) -> String {
        let byID = Dictionary(uniqueKeysWithValues: snapshot.collections.map { ($0.id, $0) })
        var names = [collection.name]
        var parentID = collection.parentID
        while let id = parentID, let parent = byID[id] {
            names.insert(parent.name, at: 0)
            parentID = parent.parentID
        }
        return names.joined(separator: " / ")
    }

    @objc private func renameCollection(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let collection = snapshot.collections.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Rename collection"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = collection.name
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { store in try await store.renameCollection(id, to: field.stringValue) }
    }

    @objc private func deleteCollection(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this collection and its subcollections?"
        alert.informativeText = "PDF files are not deleted. Papers become Unfiled."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { store in try await store.deleteCollection(id) }
    }

    @objc private func movePapers(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? LibraryPaperMove else { return }
        mutate { store in
            try await store.movePapers(selection.ids, to: selection.destinationID)
        }
    }

    @objc private func editPaperDisplayName(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let paper = snapshot.papers.first(where: { $0.id == id }) else { return }
        let automaticName = PaperLibraryPaper.automaticDisplayAlias(for: paper.title)
        let alert = NSAlert()
        alert.messageText = "Edit display name"
        alert.informativeText = "This does not rename the PDF file. Leave it blank to use: \(automaticName)"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = paper.displayAlias ?? ""
        field.placeholderString = automaticName
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mutate { store in
            try await store.setPaperDisplayAlias(id, to: field.stringValue)
        }
    }

    @objc private func removePapers(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? LibraryPaperSelection else { return }
        mutate { store in
            for id in selection.ids { try await store.removePaper(id) }
        }
    }

    private func selectedItem() -> LibraryTreeItem? {
        guard outlineView.selectedRow >= 0 else { return nil }
        return outlineView.item(atRow: outlineView.selectedRow) as? LibraryTreeItem
    }

    private func selectedPapers() -> [PaperLibraryPaper] {
        outlineView.selectedRowIndexes.compactMap { row in
            (outlineView.item(atRow: row) as? LibraryTreeItem)?.paper
        }
    }

    private func mutate(_ operation: @escaping (PaperLibraryStore) async throws -> Void) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await operation(store)
                NotificationCenter.default.post(name: .paperLibraryDidChange, object: nil)
            } catch {
                present(error)
            }
        }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

private final class LibraryPaperSelection: NSObject {
    let ids: [String]

    init(ids: [String]) {
        self.ids = ids
    }
}

private final class LibraryPaperMove: NSObject {
    let ids: [String]
    let destinationID: String?

    init(ids: [String], destinationID: String?) {
        self.ids = ids
        self.destinationID = destinationID
    }
}

private final class LibraryTreeItem {
    enum VirtualKind {
        case recent
        case unfiled
    }

    let collection: PaperLibraryCollection?
    let paper: PaperLibraryPaper?
    let title: String
    let virtualKind: VirtualKind?
    let children: [LibraryTreeItem]

    private init(
        collection: PaperLibraryCollection?,
        paper: PaperLibraryPaper?,
        title: String,
        virtualKind: VirtualKind?,
        children: [LibraryTreeItem]
    ) {
        self.collection = collection
        self.paper = paper
        self.title = title
        self.virtualKind = virtualKind
        self.children = children
    }

    static func collection(_ collection: PaperLibraryCollection, children: [LibraryTreeItem]) -> LibraryTreeItem {
        LibraryTreeItem(collection: collection, paper: nil, title: collection.name, virtualKind: nil, children: children)
    }

    static func paper(_ paper: PaperLibraryPaper) -> LibraryTreeItem {
        LibraryTreeItem(
            collection: nil,
            paper: paper,
            title: paper.displayTitle,
            virtualKind: nil,
            children: []
        )
    }

    static func virtualUnfiled(children: [LibraryTreeItem]) -> LibraryTreeItem {
        LibraryTreeItem(collection: nil, paper: nil, title: "Unfiled", virtualKind: .unfiled, children: children)
    }

    static func virtualRecent(children: [LibraryTreeItem]) -> LibraryTreeItem {
        LibraryTreeItem(collection: nil, paper: nil, title: "Recent", virtualKind: .recent, children: children)
    }

    var isVirtual: Bool { virtualKind != nil }
    var isExpandable: Bool { !children.isEmpty }
}

@MainActor
private final class LibraryOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
            return
        }
        super.keyDown(with: event)
    }
}

private enum PaperLibraryUIError: LocalizedError {
    case missingFile(String)

    var errorDescription: String? {
        switch self {
        case let .missingFile(path): "The PDF has moved or is unavailable:\n\(path)"
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let libraryColumn = NSUserInterfaceItemIdentifier("PDFlightLibraryColumn")
    static let libraryCell = NSUserInterfaceItemIdentifier("PDFlightLibraryCell")
}
