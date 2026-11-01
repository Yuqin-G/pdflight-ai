import AppKit
import PDFlightAI

/// AppKit counterpart of Harness's two-level, searchable model picker.
@MainActor
final class NativeModelPopover: NSViewController, NSSearchFieldDelegate {
    static func selfCheck() throws {
        let data = #"[{"provider":"magpie","model":"qwen","name":"qwen · Web API","api":"openai-completions","baseURL":"http://localhost"},{"provider":"magpie","model":"long","name":"DeepSeek-V4.1-Flash · WorkBuddy","api":"openai-completions","baseURL":"http://localhost"},{"provider":"deepseek-account","model":"deepseek-flash","name":"DeepSeek-V4.1-Flash","api":"openai-completions","baseURL":"http://localhost"},{"provider":"magpie","model":"third","name":"chatgpt.com · Web API","api":"openai-completions","baseURL":"http://localhost"},{"provider":"magpie","model":"fourth","name":"aistudio.google.com · Web API","api":"openai-completions","baseURL":"http://localhost"}]"#.data(using: .utf8)!
        let routes = try JSONDecoder().decode([HarnessModelImport.Route].self, from: data)
        let picker = NativeModelPopover(routes: routes, selectedID: "magpie/qwen", effort: nil, customTitle: nil, chooseModel: { _ in }, chooseEffort: { _ in }, dismiss: {})
        _ = picker.view
        picker.showModels()
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "NativeModelPopoverSelfCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try require(picker.modelRows.first?.identifier?.rawValue == "deepseek-account/deepseek-flash", "账号分组应排在 Magpie 之前")
        try require(picker.modelRows.first?.badge == "1017", "官方 Flash 模型应显示 1017 徽标")
        try require(picker.modelRows.first(where: { $0.identifier?.rawValue == "magpie/long" })?.badge == nil, "第三方模型不能显示官方徽标")
        try require(picker.modelRows.filter(\.keyboardHighlighted).count == 1, "初始状态只能高亮一个模型")
        picker.highlight(picker.modelRows[0]); picker.highlight(picker.modelRows[1])
        try require(picker.modelRows.filter(\.keyboardHighlighted).count == 1 && picker.modelRows[1].keyboardHighlighted, "切换悬停时不得留下多个高亮")
        let minimumWidth = ("DeepSeek-V4.1-Flash · WorkBuddy" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width + 45
        try require(picker.preferredContentSize.width >= minimumWidth && picker.preferredContentSize.height <= 360, "菜单尺寸必须容纳模型名称并限制高度")
        picker.view.setFrameSize(picker.preferredContentSize); picker.view.layoutSubtreeIfNeeded()
        try require(abs(picker.scroll.frame.width - (picker.view.frame.width - 8)) < 1 && abs(picker.scroll.frame.minX - 4) < 1, "模型列表应占满菜单宽度，不得意外缩进")
        picker.search.stringValue = "chatgpt"; picker.refreshModels()
        try require(picker.modelRows.count == 1 && picker.modelRows[0].identifier?.rawValue == "magpie/third", "模型搜索必须过滤列表")
        picker.showRoot(); picker.showModels()
        try require(picker.modelRows.count == routes.count, "重新打开模型列表应恢复全部选项")
    }
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
    private let searchContainer = NSView()
    private let list = NativeModelList()
    private let scroll = NSScrollView()
    private var pane: Pane = .root
    private var modelRows: [NativeModelRow] = []
    private var highlightedIndex = 0
    private var observingScroll = false
    private var configuredModelsLayout = false
    var onResize: ((NSSize) -> Void)?

    private func resize(to size: NSSize) {
        preferredContentSize = size
        onResize?(size)
    }

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
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.layer?.backgroundColor = NativeHarnessStyle.menu.cgColor }
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
        resize(to: NSSize(width: 260, height: current?.reasoningEfforts?.isEmpty == false ? 76 : 42))
    }

    @objc private func showModels() {
        pane = .models; search.stringValue = ""
        clear()
        if routes.count > 4 {
            search.placeholderString = "搜索模型…"; search.isBordered = false; search.focusRingType = .none; search.font = .systemFont(ofSize: 12)
            (search.cell as? NSSearchFieldCell)?.searchButtonCell = nil
            search.delegate = self
            if !configuredModelsLayout {
                search.translatesAutoresizingMaskIntoConstraints = false
                searchContainer.addSubview(search)
                NSLayoutConstraint.activate([
                    searchContainer.heightAnchor.constraint(equalToConstant: 30),
                    search.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 7),
                    search.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -7),
                    search.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor)
                ])
            }
            stack.addArrangedSubview(searchContainer)
            searchContainer.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        }
        list.orientation = .vertical; list.alignment = .width; list.spacing = 0
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.contentView.postsBoundsChangedNotifications = true
        if !observingScroll {
            NotificationCenter.default.addObserver(self, selector: #selector(scrollDidChange), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            observingScroll = true
        }
        scroll.documentView = list; list.translatesAutoresizingMaskIntoConstraints = false
        if !configuredModelsLayout {
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
            configuredModelsLayout = true
        }
        stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -8).isActive = true
        refreshModels()
        if routes.count > 4 { view.window?.makeFirstResponder(search) }
    }
    private func refreshModels() {
        list.arrangedSubviews.forEach { list.removeArrangedSubview($0); $0.removeFromSuperview() }
        modelRows.removeAll(); highlightedIndex = 0
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = routes.sorted { a, b in
            func order(_ id: String) -> Int { switch id { case "deepseek-account": return 0; case "magpie": return 1; case "magpie-responses": return 2; case "magpie-anthropic": return 3; default: return 4 } }
            let x = order(a.provider), y = order(b.provider)
            return x == y ? (a.provider == b.provider ? false : a.provider < b.provider) : x < y
        }
        var lastProvider: String?
        for route in sorted where query.isEmpty || route.name.localizedCaseInsensitiveContains(query) || route.provider.localizedCaseInsensitiveContains(query) {
            if lastProvider != route.provider {
                let fallback = ["deepseek-account": "DeepSeek 账号", "magpie": "Magpie", "magpie-responses": "Magpie · Responses", "magpie-anthropic": "Magpie · Anthropic"]
                let label = NSTextField(labelWithString: route.providerName ?? fallback[route.provider] ?? route.provider)
                label.font = .systemFont(ofSize: 11); label.textColor = NativeHarnessStyle.secondary
                let wrap = NSView(); wrap.addSubview(label); label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 8), label.centerYAnchor.constraint(equalTo: wrap.centerYAnchor), wrap.heightAnchor.constraint(equalToConstant: 26)])
                list.addArrangedSubview(wrap); lastProvider = route.provider
            }
            let button = row(route.name, value: route.id == selectedID ? "✓" : "", action: #selector(pickModel(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(route.id); button.isEnabled = route.isSupported
            list.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
            if button.isEnabled, let modelRow = button as? NativeModelRow {
                if ["deepseek-account", "deepseek-official"].contains(route.provider), route.model == "deepseek-flash", route.name == "DeepSeek-V4.1-Flash" {
                    modelRow.badge = "1017"
                }
                modelRow.tracksListHighlight = true
                modelRow.pointerEntered = { [weak self, weak modelRow] in
                    guard let self, let modelRow else { return }
                    self.highlight(modelRow)
                }
                modelRows.append(modelRow)
            }
        }
        if selectedID == NativePaperChatSidebar.customRouteID, let customTitle {
            let button = row(customTitle, value: "✓", action: #selector(pickModel(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(NativePaperChatSidebar.customRouteID); list.addArrangedSubview(button); button.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        }
        if list.arrangedSubviews.isEmpty {
            let empty = NSTextField(labelWithString: "没有找到模型"); empty.textColor = .secondaryLabelColor; empty.font = .systemFont(ofSize: 12)
            list.addArrangedSubview(empty)
        }
        if !modelRows.isEmpty {
            highlightedIndex = modelRows.firstIndex(where: { $0.identifier?.rawValue == selectedID }) ?? 0
            modelRows[highlightedIndex].keyboardHighlighted = true
        }
        let height = min(360, max(75, CGFloat(list.arrangedSubviews.count * 34 + (routes.count > 4 ? 38 : 8))))
        let font = NSFont.systemFont(ofSize: 13)
        let textWidth = modelRows.map { ($0.title as NSString).size(withAttributes: [.font: font]).width + ($0.badge == nil ? 0 : 45) }.max() ?? 0
        resize(to: NSSize(width: min(420, max(240, ceil(textWidth) + 55)), height: height))
        scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
    }
    private func highlight(_ row: NativeModelRow) {
        guard let index = modelRows.firstIndex(of: row) else { return }
        highlightedIndex = index
        for item in modelRows { item.keyboardHighlighted = item === row }
    }
    private func highlightPointerRowIfPresent() {
        guard let row = modelRows.first(where: { $0.pointerIsInside }) else { return }
        highlight(row)
    }
    @objc private func scrollDidChange() { highlightPointerRowIfPresent() }
    func controlTextDidChange(_ obj: Notification) { if pane == .models { refreshModels() } }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard pane == .models else { return false }
        if commandSelector == #selector(NSResponder.moveDown(_:)) || commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !modelRows.isEmpty else { return true }
            modelRows.forEach { $0.keyboardHighlighted = false }
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
        resize(to: NSSize(width: 260, height: CGFloat(stack.arrangedSubviews.count * 34 + 8)))
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

/// A borderless child panel matches Harness's floating menu while retaining
/// AppKit focus, keyboard navigation and dismissal behavior.
@MainActor
final class NativeModelPanel: NSPanel {
    private weak var owner: NSWindow?
    private weak var anchor: NSView?
    private var clickMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    var onDismiss: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { dismiss() }
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let menu = contentViewController as? NativeComposerMenu, menu.handleKey(event) { return }
        if event.type == .keyDown, event.keyCode == 53, !(firstResponder is NSTextView) {
            dismiss(); return
        }
        super.sendEvent(event)
    }

    init(controller: NSViewController, parent: NSWindow, anchor: NSView) {
        owner = parent; self.anchor = anchor
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear
        hasShadow = true; animationBehavior = .none
        contentViewController = controller
        (controller as? NativeModelPopover)?.onResize = { [weak self] size in self?.position(size) }
    }

    func present(activate: Bool = true) {
        guard let owner, let controller = contentViewController else { return }
        _ = controller.view
        position(controller.preferredContentSize)
        owner.addChildWindow(self, ordered: .above)
        if activate { makeKeyAndOrderFront(nil) } else { orderFront(nil) }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window !== self else { return event }
            let clickedAnchor = event.window === self.owner && self.anchor.map {
                $0.bounds.contains($0.convert(event.locationInWindow, from: nil))
            } == true
            self.dismiss()
            return clickedAnchor && activate ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    private func position(_ size: NSSize) {
        guard let owner, let anchor, size.width > 0, size.height > 0 else { return }
        let frame = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = owner.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let x = min(max(visible.minX + 4, frame.maxX + 8 - size.width), visible.maxX - size.width - 4)
        let y = min(max(visible.minY + 4, frame.maxY + 8), visible.maxY - size.height - 4)
        setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }

    func dismiss() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        owner?.removeChildWindow(self); orderOut(nil)
        let callback = onDismiss; onDismiss = nil; callback?()
    }
}

private final class NativeModelRow: NSButton {
    private let value: String
    var badge: String?
    var pointerEntered: (() -> Void)?
    var tracksListHighlight = false
    var keyboardHighlighted = false { didSet { needsDisplay = true } }
    var pointerIsInside: Bool {
        window.map { $0.isKeyWindow && visibleRect.contains(convert($0.mouseLocationOutsideOfEventStream, from: nil)) } ?? false
    }
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
    override func mouseEntered(with event: NSEvent) { pointerEntered?(); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let highlighted = tracksListHighlight ? keyboardHighlighted : (pointerIsInside || keyboardHighlighted)
        if highlighted && isEnabled { NSColor.labelColor.withAlphaComponent(0.06).setFill(); NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill() }
        let font = NSFont.systemFont(ofSize: 13), paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        let textColor = isEnabled ? NativeHarnessStyle.primary : NSColor.disabledControlTextColor
        let valueWidth = min(bounds.width * 0.68, (value as NSString).size(withAttributes: [.font: font]).width + 4)
        let badgeWidth: CGFloat = badge == nil ? 0 : 44
        let textRect = NSRect(x: 8, y: (bounds.height - 18) / 2, width: max(0, bounds.width - 20 - valueWidth - badgeWidth), height: 18)
        (title as NSString).draw(in: textRect, withAttributes: [.font: font, .foregroundColor: textColor, .paragraphStyle: paragraph])
        if let badge {
            let titleWidth = min(textRect.width, (title as NSString).size(withAttributes: [.font: font]).width)
            let badgeRect = NSRect(x: textRect.minX + titleWidth + 4, y: (bounds.height - 19) / 2, width: 40, height: 19)
            NSColor.systemOrange.withAlphaComponent(0.10).setFill()
            NSBezierPath(roundedRect: badgeRect, xRadius: 9, yRadius: 9).fill()
            let badgeStyle = NSMutableParagraphStyle(); badgeStyle.alignment = .center
            (badge as NSString).draw(in: badgeRect.insetBy(dx: 0, dy: 2), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange, .paragraphStyle: badgeStyle])
        }
        paragraph.alignment = .right
        (value as NSString).draw(in: NSRect(x: bounds.width - valueWidth - 8, y: textRect.minY, width: valueWidth, height: 18), withAttributes: [.font: font, .foregroundColor: NativeHarnessStyle.secondary, .paragraphStyle: paragraph])
    }
}
