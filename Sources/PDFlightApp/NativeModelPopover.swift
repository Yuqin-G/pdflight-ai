import AppKit
import PDFlightAI

/// AppKit counterpart of Harness's two-level, searchable model picker.
@MainActor
final class NativeModelPopover: NSViewController, NSSearchFieldDelegate {
    private enum Pane { case root, models, effort }
    private let routes: [HarnessModelImport.Route]
    private let selectedID: String?
    private let effort: String?
    private let customTitle: String?
    private let chooseModel: (String) -> Void
    private let chooseEffort: (String?) -> Void
    private let dismiss: () -> Void
    private let stack = NSStackView()
    private let search = NSSearchField()
    private let list = NativeModelList()
    private let scroll = NSScrollView()
    private var pane: Pane = .root
    private var modelRows: [NativeModelRow] = []
    private var highlightedIndex = 0

    init(routes: [HarnessModelImport.Route], selectedID: String?, effort: String?, customTitle: String?,
         chooseModel: @escaping (String) -> Void, chooseEffort: @escaping (String?) -> Void, dismiss: @escaping () -> Void) {
        self.routes = routes; self.selectedID = selectedID; self.effort = effort; self.customTitle = customTitle
        self.chooseModel = chooseModel; self.chooseEffort = chooseEffort; self.dismiss = dismiss
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 42))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.layer?.cornerRadius = 9
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        stack.orientation = .vertical; stack.alignment = .width; stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: view.topAnchor), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     stack.leadingAnchor.constraint(equalTo: view.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        showRoot()
    }

    private var current: HarnessModelImport.Route? { routes.first { $0.id == selectedID } }
    private func clear() { stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() } }
    private func showRoot() {
        pane = .root; clear()
        let title = current?.name ?? customTitle ?? "选择模型"
        let modelRow = row("模型", value: title, action: #selector(showModels))
        stack.addArrangedSubview(modelRow); modelRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        if !(current?.reasoningEfforts ?? []).isEmpty {
            let effortRow = row("推理等级", value: effort ?? "默认", action: #selector(showEfforts))
            stack.addArrangedSubview(effortRow); effortRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }
        preferredContentSize = NSSize(width: 260, height: current?.reasoningEfforts?.isEmpty == false ? 76 : 42)
    }

    @objc private func showModels() {
        pane = .models; search.stringValue = ""
        clear()
        if routes.count > 4 {
            search.placeholderString = "搜索模型…"; search.isBordered = false; search.focusRingType = .none; search.font = .systemFont(ofSize: 12)
            (search.cell as? NSSearchFieldCell)?.searchButtonCell = nil
            search.delegate = self; search.heightAnchor.constraint(equalToConstant: 30).isActive = true
            stack.addArrangedSubview(search)
        }
        list.orientation = .vertical; list.alignment = .width; list.spacing = 0
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = list; list.translatesAutoresizingMaskIntoConstraints = false
        list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        stack.addArrangedSubview(scroll)
        refreshModels()
        if routes.count > 4 { view.window?.makeFirstResponder(search) }
    }
    private func refreshModels() {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        modelRows.removeAll(); highlightedIndex = 0
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = routes.sorted { a, b in
            func order(_ id: String) -> Int { switch id { case "magpie": return 0; case "magpie-responses": return 1; case "magpie-anthropic": return 2; default: return 3 } }
            let x = order(a.provider), y = order(b.provider)
            return x == y ? (a.provider == b.provider ? false : a.provider < b.provider) : x < y
        }
        var lastProvider: String?
        for route in sorted where query.isEmpty || route.name.localizedCaseInsensitiveContains(query) || route.provider.localizedCaseInsensitiveContains(query) {
            if lastProvider != route.provider {
                let fallback = ["magpie": "Magpie", "magpie-responses": "Magpie · Responses", "magpie-anthropic": "Magpie · Anthropic"]
                let label = NSTextField(labelWithString: route.providerName ?? fallback[route.provider] ?? route.provider)
                label.font = .systemFont(ofSize: 11); label.textColor = NativeHarnessStyle.secondary
                let wrap = NSView(); wrap.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8), label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor), wrap.heightAnchor.constraint(equalToConstant: 26)])
                list.addArrangedSubview(wrap); lastProvider = route.provider
            }
            let button = row(route.name, value: route.id == selectedID ? "✓" : "", action: #selector(pickModel(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(route.id); button.isEnabled = route.isSupported
            list.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            if button.isEnabled, let modelRow = button as? NativeModelRow { modelRows.append(modelRow) }
        }
        if selectedID == NativePaperChatSidebar.customRouteID, let customTitle {
            let button = row(customTitle, value: "✓", action: #selector(pickModel(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(NativePaperChatSidebar.customRouteID); list.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if list.arrangedSubviews.isEmpty {
            let empty = NSTextField(labelWithString: "没有找到模型"); empty.textColor = .secondaryLabelColor; empty.font = .systemFont(ofSize: 12)
            list.addArrangedSubview(empty)
        }
        let height = min(360, max(75, CGFloat(list.arrangedSubviews.count * 34 + (routes.count > 4 ? 38 : 8))))
        preferredContentSize = NSSize(width: 280, height: height)
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    func controlTextDidChange(_ obj: Notification) { if pane == .models { refreshModels() } }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard pane == .models else { return false }
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !modelRows.isEmpty else { return true }
            modelRows[highlightedIndex].keyboardHighlighted = false
            let delta = commandSelector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            highlightedIndex = (highlightedIndex + delta + modelRows.count) % modelRows.count
            modelRows[highlightedIndex].keyboardHighlighted = true; modelRows[highlightedIndex].scrollToVisible(modelRows[highlightedIndex].bounds)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
            if modelRows.indices.contains(highlightedIndex) { pickModel(modelRows[highlightedIndex]) }
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { showRoot(); return true }
        return false
    }
    @objc private func showEfforts() {
        pane = .effort; clear()
        for value in ["默认"] + (current?.reasoningEfforts ?? []) {
            let button = row(value, value: (value == (effort ?? "默认")) ? "✓" : "", action: #selector(pickEffort(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(value); stack.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }
        preferredContentSize = NSSize(width: 260, height: CGFloat(stack.arrangedSubviews.count * 34 + 8))
    }
    private func row(_ title: String, value: String, action: Selector) -> NSButton {
        let button = NativeModelRow(title: title, value: value + (action == #selector(showModels) || action == #selector(showEfforts) ? "  ›" : ""), target: self, action: action)
        button.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return button
    }
    @objc private func pickModel(_ button: NSButton) { if let id = button.identifier?.rawValue { chooseModel(id); dismiss() } }
    @objc private func pickEffort(_ button: NSButton) { let value = button.identifier?.rawValue; chooseEffort(value == "默认" ? nil : value); dismiss() }
    override func cancelOperation(_ sender: Any?) { if pane == .root { dismiss() } else { showRoot() } }
}

private final class NativeModelList: NSStackView { override var isFlipped: Bool { true } }

private final class NativeModelRow: NSButton {
    private let value: String
    private var hovered = false
    var keyboardHighlighted = false { didSet { needsDisplay = true } }
    init(title: String, value: String, target: AnyObject, action: Selector) {
        self.value = value
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action; isBordered = false
        setAccessibilityLabel(title)
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
        if (hovered || keyboardHighlighted) && isEnabled { NSColor.selectedContentBackgroundColor.withAlphaComponent(0.09).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill() }
        let font = NSFont.systemFont(ofSize: 13), paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let textColor = isEnabled ? NativeHarnessStyle.primary : NSColor.disabledControlTextColor
        let valueWidth = min(bounds.width * 0.68, (value as NSString).size(withAttributes: [.font: font]).width + 4)
        let textRect = NSRect(x: 8, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 20 - valueWidth), height: 18)
        (title as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph])
        paragraph.alignment = .right
        (value as NSString).draw(in: NSRect(x: bounds.width - valueWidth - 8, y: textRect.minY, width: valueWidth, height: 18), withAttributes: [.font: font, .foregroundColor: NativeHarnessStyle.secondary, .paragraphStyle: paragraph])
    }
}
