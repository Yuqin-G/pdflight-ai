import AppKit
import Foundation
import WebKit

/// Hosts the actual PDF-reading surface supplied by the running Harness Desktop.
@MainActor
final class HarnessChatSidebarView: NSView, WKNavigationDelegate, WKUIDelegate {
    var onResizeBy: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?

    private struct Marker: Decodable {
        let url: URL
    }
    private struct PaperResult: Decodable {
        let paperId: String
        let migration: String
        let chatZoom: Double?
    }
    private let documentURL: URL
    private let loadingLabel = NSTextField(wrappingLabelWithString: "正在连接 DeepSeek Harness…")
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let openHarnessButton = NSButton(title: "打开 DeepSeek Harness", target: nil, action: nil)
    private let installBridgeButton = NSButton(title: "安装连接插件", target: nil, action: nil)
    private let migrationNotice = NSButton(title: "旧对话提示", target: nil, action: nil)
    private let statusStack = NSStackView()
    private let resizeHandle = HarnessSidebarResizeHandle()
    private var webView: WKWebView?
    private var connectTask: Task<Void, Never>?
    private var pendingPrefill: String?
    private var connectedOrigin: URL?
    private var isLoaded = false

    init(documentURL: URL) {
        self.documentURL = documentURL.standardizedFileURL
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        loadingLabel.alignment = .center
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.font = .systemFont(ofSize: 12)
        retryButton.target = self
        retryButton.action = #selector(retryConnection)
        openHarnessButton.target = self
        openHarnessButton.action = #selector(openHarness)
        installBridgeButton.target = self
        installBridgeButton.action = #selector(installBridge)
        migrationNotice.target = self
        migrationNotice.action = #selector(showMigrationNotice)
        migrationNotice.controlSize = .small
        migrationNotice.isHidden = true
        migrationNotice.translatesAutoresizingMaskIntoConstraints = false
        statusStack.orientation = .vertical
        statusStack.alignment = .centerX
        statusStack.spacing = 12
        statusStack.addArrangedSubview(loadingLabel)
        statusStack.addArrangedSubview(retryButton)
        statusStack.addArrangedSubview(openHarnessButton)
        statusStack.addArrangedSubview(installBridgeButton)
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusStack)
        addSubview(migrationNotice)
        resizeHandle.onDrag = { [weak self] in self?.onResizeBy?($0) }
        resizeHandle.onDragEnded = { [weak self] in self?.onResizeEnded?() }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.setAccessibilityElement(true)
        resizeHandle.setAccessibilityRole(.splitter)
        resizeHandle.setAccessibilityLabel("Resize Ask PDF sidebar")
        addSubview(resizeHandle, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            statusStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            migrationNotice.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            migrationNotice.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
            resizeHandle.topAnchor.constraint(equalTo: topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 18)
        ])
        retryButton.isHidden = true
        openHarnessButton.isHidden = true
        installBridgeButton.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if point.x >= 0, point.x <= 18, bounds.contains(point) { return resizeHandle }
        return super.hitTest(point)
    }

    func activate() {
        guard webView == nil, connectTask == nil else { return }
        loadingLabel.stringValue = "正在连接 DeepSeek Harness…"
        retryButton.isHidden = true
        openHarnessButton.isHidden = true
        installBridgeButton.isHidden = true
        statusStack.isHidden = false
        connectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let marker = try await waitForHarness()
                let result = try await resolvePaper(using: marker.url)
                guard !Task.isCancelled else { return }
                installWebView(url: marker.url, paperID: result.paperId, chatZoom: result.chatZoom)
                if result.migration == "retained" {
                    migrationNotice.isHidden = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                loadingLabel.stringValue = error.localizedDescription
                retryButton.isHidden = false
                openHarnessButton.isHidden = false
                installBridgeButton.isHidden = false
                statusStack.isHidden = false
            }
            connectTask = nil
        }
    }

    func prefill(_ text: String) {
        pendingPrefill = text
        sendPendingPrefill(attemptsRemaining: 40)
    }

    func focusComposer() {
        webView?.window?.makeFirstResponder(webView)
        webView?.evaluateJavaScript("document.querySelector('[contenteditable=true][data-lexical-editor]')?.focus()")
    }

    func close() {
        connectTask?.cancel()
        connectTask = nil
        webView?.stopLoading()
    }

    @objc private func retryConnection() {
        webView?.removeFromSuperview()
        webView = nil
        isLoaded = false
        activate()
    }

    @objc func openHarness() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh") else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: .init())
    }

    @objc private func installBridge() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh"),
              let resources = Bundle.main.resourceURL else {
            loadingLabel.stringValue = "请先安装 DeepSeek Harness。"
            return
        }
        let node = application.appendingPathComponent("Contents/Resources/runtime/primary-runtime/dependencies/node/bin/node")
        let script = resources.appendingPathComponent("install-harness-bridge.mjs")
        let plugin = resources.appendingPathComponent("harness-chat")
        let process = Process()
        process.executableURL = node
        process.arguments = [script.path, plugin.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        installBridgeButton.isEnabled = false
        loadingLabel.stringValue = "正在安装 Harness 连接插件…"
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.installBridgeButton.isEnabled = true
                if process.terminationStatus == 0 { self.retryConnection() }
                else { self.loadingLabel.stringValue = "插件安装失败，请检查 Harness 的 PDF 阅读插件是否已启用。" }
            }
        }
        do { try process.run() }
        catch {
            installBridgeButton.isEnabled = true
            loadingLabel.stringValue = "无法启动插件安装：\(error.localizedDescription)"
        }
    }

    @objc private func showMigrationNotice() {
        let alert = NSAlert()
        alert.messageText = "部分旧对话未自动迁移"
        alert.informativeText = "这些记录包含无法完整转换的内容。PDFlight 原始对话文件仍然保留在 ai-chats 文件夹。"
        alert.addButton(withTitle: "查看文件夹")
        alert.addButton(withTitle: "关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/dev.pdflight.reader/ai-chats")
            NSWorkspace.shared.open(directory)
        }
    }

    private func waitForHarness() async throws -> Marker {
        let supportDirectory = ProcessInfo.processInfo.environment["PDFLIGHT_HARNESS_SUPPORT_DIRECTORY"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/dev.pdflight.reader")
        let markerURL = supportDirectory.appendingPathComponent("harness-bridge/desktop.json")
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: "com.deepseek.dsh").isEmpty
        if !running { openHarness() }
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: markerURL),
               let marker = try? JSONDecoder().decode(Marker.self, from: data),
               marker.url.scheme == "http", marker.url.host == "127.0.0.1", marker.url.port != nil,
               marker.url.path == "/", marker.url.user == nil, marker.url.password == nil {
                return marker
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: "PDFlight.Harness", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "未找到 Harness 连接插件。请安装 PDFlight Harness 插件并重新打开 DeepSeek Harness，然后重试。"])
    }

    private func resolvePaper(using launchURL: URL) async throws -> PaperResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (_, loginResponse) = try await session.data(from: launchURL)
        guard (loginResponse as? HTTPURLResponse)?.statusCode == 200,
              let origin = URL(string: "http://127.0.0.1:\(launchURL.port!)/") else {
            throw NSError(domain: "PDFlight.Harness", code: 2, userInfo: [NSLocalizedDescriptionKey: "无法连接 Harness，请重试。"])
        }
        var request = URLRequest(url: origin.appendingPathComponent("pdflight-bridge/paper"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("http://127.0.0.1:\(launchURL.port!)", forHTTPHeaderField: "Origin")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["path": documentURL.path])
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let value = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            throw NSError(domain: "PDFlight.Harness", code: 3, userInfo: [NSLocalizedDescriptionKey: value?["error"] ?? "无法打开论文对话。"])
        }
        return try JSONDecoder().decode(PaperResult.self, from: data)
    }

    private func installWebView(url: URL, paperID: String, chatZoom: Double?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let encodedID = String(data: try! JSONEncoder().encode(paperID), encoding: .utf8)!
        let zoom = chatZoom.flatMap { $0.isFinite && (0.8...2.4).contains($0) ? $0 : nil }
        let zoomScript = zoom.map { "localStorage.setItem('pdf-reading-chat-zoom','\($0)');" } ?? ""
        let script = "window.__PDFLIGHT_EMBED__=true;localStorage.setItem('pr.last',\(encodedID));\(zoomScript)"
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view, positioned: .below, relativeTo: resizeHandle)
        addSubview(statusStack, positioned: .above, relativeTo: view)
        addSubview(migrationNotice, positioned: .above, relativeTo: view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        connectedOrigin = URL(string: "http://127.0.0.1:\(url.port!)/")
        webView = view
        view.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoaded = true
        statusStack.isHidden = true
        sendPendingPrefill(attemptsRemaining: 40)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadingLabel.stringValue = "Harness 对话连接失败：\(error.localizedDescription)"
        retryButton.isHidden = false
        openHarnessButton.isHidden = false
        installBridgeButton.isHidden = false
        statusStack.isHidden = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "http", url.host == connectedOrigin?.host, url.port == connectedOrigin?.port {
            decisionHandler(.allow)
        } else {
            if navigationAction.navigationType == .linkActivated, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window else { completionHandler(nil); return }
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }

    private func sendPendingPrefill(attemptsRemaining: Int) {
        guard isLoaded, let webView, let text = pendingPrefill, attemptsRemaining > 0,
              let encoded = try? JSONEncoder().encode(text), let literal = String(data: encoded, encoding: .utf8) else { return }
        let script = "(()=>{const e=document.querySelector('[contenteditable=true][data-lexical-editor]');if(!e)return false;e.focus();return document.execCommand('insertText',false,\(literal));})()"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self, self.pendingPrefill == text else { return }
                if result as? Bool == true { self.pendingPrefill = nil }
                else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.sendPendingPrefill(attemptsRemaining: attemptsRemaining - 1) } }
            }
        }
    }
}

private final class HarnessSidebarResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    private var previousX: CGFloat?
    override func resetCursorRects() { super.resetCursorRects(); addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) { NSColor.separatorColor.withAlphaComponent(0.65).setFill(); NSRect(x: 0, y: bounds.minY, width: 1, height: bounds.height).fill() }
    override func mouseDown(with event: NSEvent) { previousX = event.locationInWindow.x }
    override func mouseDragged(with event: NSEvent) { guard let previousX else { return }; self.previousX = event.locationInWindow.x; onDrag?(event.locationInWindow.x - previousX) }
    override func mouseUp(with event: NSEvent) { previousX = nil; onDragEnded?() }
}
