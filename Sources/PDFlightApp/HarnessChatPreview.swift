import AppKit
import PDFlightAI
import WebKit

enum HarnessChatResourceLocator {
    static let requiredFiles = ["preview.html", "preview.js", "assets/pdflight-static.js", "harness-chat-zoom.js",
                                "harness-webkit-compat.js", "dsh-client-ui-chat.js", "dsh-client-ui-model-selection.js",
                                "dsh-client-ui-conversation.js", "claude-warm-theme-client.js"]

    static func resolve(bundleResources: URL?, executable: URL?) -> URL? {
        func complete(_ root: URL) -> Bool {
            requiredFiles.allSatisfy { FileManager.default.isReadableFile(atPath: root.appendingPathComponent($0).path) }
        }
        if let root = bundleResources?.appendingPathComponent("HarnessChat", isDirectory: true), complete(root) {
            return root.resolvingSymlinksInPath().standardizedFileURL
        }
        guard let executable = executable?.resolvingSymlinksInPath().standardizedFileURL,
              !executable.pathComponents.contains(where: { $0.hasSuffix(".app") }) else { return nil }
        var parent = executable.deletingLastPathComponent()
        while parent.path != "/" {
            if FileManager.default.isReadableFile(atPath: parent.appendingPathComponent("Package.swift").path) {
                let root = parent.appendingPathComponent("Resources/HarnessChat", isDirectory: true)
                return complete(root) ? root : nil
            }
            parent.deleteLastPathComponent()
        }
        return nil
    }
}

/// Bundled reading renderer; native input, history and execution stay local.
/// The native sidebar remains responsible for input, history and execution.
@MainActor
final class HarnessChatPreview: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    private var webView: WKWebView?
    private let relay = HarnessPreviewRelay()
    private var isActive = false
    private var savedScroll: [String: Any]?
    private var activationGeneration: UInt64 = 0
    private var isClosed = false
    private var isActivating = false
    private var isReady = false
    private var requestedZoom: CGFloat = 1
    var onZoomChanged: ((CGFloat) -> Void)?
    var onRenderingStateChanged: ((Bool, String?) -> Void)?
    private var messages: [AIChatMessage] = []
    private var messageRevision: UInt64 = 0
    private var renderedRevision: UInt64?
    private var refreshWork: DispatchWorkItem?
    private let provider: HarnessPreviewResources
    private let resourceRoot: URL?
    private var readinessWatchdog: DispatchWorkItem?
    var hasRenderingFailure: Bool { renderingFailure != nil }
    private var renderingFailure: String?

    override convenience init(frame: NSRect) {
        self.init(frame: frame, resourceRoot: HarnessChatResourceLocator.resolve(
            bundleResources: Bundle.main.resourceURL,
            executable: Bundle.main.executableURL ?? CommandLine.arguments.first.map { URL(fileURLWithPath: $0) }))
    }

    init(frame: NSRect, resourceRoot: URL?) {
        self.resourceRoot = resourceRoot
        provider = HarnessPreviewResources(root: resourceRoot)
        super.init(frame: frame)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func activate() {
        guard !isClosed, !isActivating, renderingFailure == nil else { return }
        guard let resourceRoot, HarnessChatResourceLocator.requiredFiles.allSatisfy({ FileManager.default.isReadableFile(atPath: resourceRoot.appendingPathComponent($0).path) }) else {
            renderingFailed("聊天显示资源缺失或不完整，已显示本地原生消息；历史记录和草稿未改动。")
            return
        }
        isActive = true
        if webView != nil {
            if renderedRevision != messageRevision { refresh() }
            return
        }
        isActivating = true
        activationGeneration &+= 1
        onRenderingStateChanged?(false, "聊天显示正在加载，暂用本地原生消息。")
        let generation = activationGeneration
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, !isClosed, activationGeneration == generation else { return }
            renderingFailed("聊天网页初始化超时，已切回本地原生消息。")
        }
        readinessWatchdog?.cancel()
        readinessWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(provider, forURLScheme: "pdflight-chat")
        relay.target = self
        for name in ["harnessReady", "harnessZoom", "harnessFailure", "harnessScroll"] {
            configuration.userContentController.add(relay, name: name)
        }
        configuration.userContentController.addUserScript(WKUserScript(source: """
            (() => {
              const fail = () => window.webkit?.messageHandlers?.harnessFailure?.postMessage('renderer-error');
              window.addEventListener('error', fail, true);
              window.addEventListener('unhandledrejection', fail);

            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        webView = view
        view.navigationDelegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        view.load(URLRequest(url: URL(string: "pdflight-chat://local/preview.html")!))
        isActivating = false
    }

    func deactivate() {
        isActive = false
        refreshWork?.cancel()
    }

    /// Only the renderer is disposable. Messages, zoom and scroll belong to
    /// this lightweight paper view; draft and stream ownership stays native.
    func discardRenderer() {
        activationGeneration &+= 1
        refreshWork?.cancel()
        readinessWatchdog?.cancel()
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        relay.target = nil
        isReady = false
        renderedRevision = nil
        isActivating = false
        renderingFailure = nil
    }

    func close() {
        isClosed = true
        isActive = false
        discardRenderer()
        onZoomChanged = nil
        onRenderingStateChanged = nil
    }

    func replace(_ values: [AIChatMessage]) { savedScroll = nil; messages = values; scheduleRefresh() }
    func append(_ message: AIChatMessage) { messages.append(message); scheduleRefresh() }
    func update(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
        scheduleRefresh()
    }
    func updateReasoning(id: String, content: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].reasoning = content
        scheduleRefresh()
    }
    func updateTool(id: String, event: AIChatToolEvent) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].toolEvent = event
        scheduleRefresh()
    }
    func remove(id: String) { messages.removeAll { $0.id == id }; scheduleRefresh() }

    private func scheduleRefresh() {
        messageRevision &+= 1
        guard isActive, webView != nil else { return }
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func refresh() {
        guard isActive, isReady, let view = webView else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            renderingFailed("聊天消息无法交给网页显示，已切回本地原生消息。")
            return
        }
        let generation = activationGeneration
        let revision = messageRevision
        view.callAsyncJavaScript("if (typeof window.PDFlightReplaceMessages !== 'function') return false; window.PDFlightReplaceMessages(messages, position); return true;", arguments: ["messages": object, "position": savedScroll as Any? ?? NSNull()], in: nil, in: .page) { result in
            guard !self.isClosed, self.activationGeneration == generation, self.isReady else { return }
            switch result {
            case .success(let value) where value as? Bool == true:
                self.renderedRevision = revision
                self.readinessWatchdog?.cancel()
                self.onRenderingStateChanged?(true, nil)
            default:
                self.renderingFailed("聊天网页消息接口未正确初始化，已切回本地原生消息。")
            }
        }
    }

    func renderingFailed(_ explanation: String) {
        guard !isClosed else { return }
        discardRenderer()
        renderingFailure = explanation
        onRenderingStateChanged?(false, explanation)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isClosed, renderingFailure == nil, message.webView === webView else { return }
        if message.name == "harnessReady" {
            isReady = true
            applyZoom()
            refresh()
        } else if message.name == "harnessScroll", isActive, renderedRevision != nil,
                  let body = message.body as? [String: Any] {
            savedScroll = body["position"] as? [String: Any]
        } else if message.name == "harnessFailure" {
            renderingFailed("聊天网页脚本或资源加载失败，已切回本地原生消息。")
        } else if message.name == "harnessZoom",
                  let body = message.body as? [String: Any], let value = body["zoom"] as? Double,
                  value.isFinite, (0.8...2.4).contains(value) {
            requestedZoom = CGFloat(value)
            onZoomChanged?(requestedZoom)
        }
    }
    func setZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        let next = min(2.4, max(0.8, value))
        guard abs(next - requestedZoom) >= 0.001 else { return }
        requestedZoom = next
        applyZoom()
    }

    private func applyZoom() {
        guard isActive, isReady, let view = webView else { return }
        view.callAsyncJavaScript("window.__setChatZoom?.(zoom)", arguments: ["zoom": Double(requestedZoom)], in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("Harness preview zoom failed: %@", error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "pdflight-chat" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        renderingFailed("聊天网页导航失败，已切回本地原生消息。")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        renderingFailed("聊天网页资源无法载入，已切回本地原生消息。")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        renderingFailed("聊天网页进程已停止，已切回本地原生消息。")
    }
}

@MainActor
private final class HarnessPreviewRelay: NSObject, WKScriptMessageHandler {
    weak var target: HarnessChatPreview?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

private final class HarnessPreviewResources: NSObject, WKURLSchemeHandler {
    let root: URL?
    init(root: URL?) { self.root = root?.resolvingSymlinksInPath().standardizedFileURL }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let root, let url = task.request.url, url.host == "local" else {
            task.didFailWithError(NSError(domain: "HarnessPreviewURL", code: 1)); return
        }
        let file = root.appendingPathComponent(url.path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "HarnessPreviewFile", code: 2)); return
        }
        let types = ["html":"text/html", "js":"text/javascript", "css":"text/css", "woff2":"font/woff2", "svg":"image/svg+xml", "json":"application/json"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*"])!
        task.didReceive(response); task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@MainActor
extension HarnessChatPreview {
    /// Integration probe: use the live renderer and DOM, not just resource paths.
    func workspaceRenderingSelfCheck(expectedText: String) async throws -> ObjectIdentifier {
        for _ in 0..<120 {
            if let renderingFailure {
                throw NSError(domain: "WorkspaceChatCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: renderingFailure])
            }
            if isReady, let view = webView,
               let text = try? await view.evaluateJavaScript("document.body.innerText") as? String,
               text.contains(expectedText) {
                guard view.window === window, window != nil, !isHidden else {
                    throw NSError(domain: "WorkspaceChatCheck", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Live chat renderer must remain attached and visible"])
                }
                return ObjectIdentifier(view)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "WorkspaceChatCheck", code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Live renderer did not display the synthetic saved answer"])
    }
}

@MainActor
extension HarnessChatPreview {
    var savedPositionForSelfCheck: [String: Any]? { savedScroll }
    var hasSavedScrollForSelfCheck: Bool { savedScroll != nil }
    var rendererIdentityForSelfCheck: ObjectIdentifier? { webView.map(ObjectIdentifier.init) }

    /// Pump only the isolated check's run loop; production never blocks for JS.
    func waitForSelfCheck(_ script: String, matches: (Any?) -> Bool) throws {
        let deadline = Date().addingTimeInterval(12)
        var pending = false
        var result: Result<Any, Error>?
        while Date() < deadline {
            if let renderingFailure {
                throw NSError(domain: "ChatWebCacheCheck", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: renderingFailure])
            }
            if let result {
                switch result {
                case .success(let value): if matches(value) { return }
                case .failure(let error): throw error
                }
            }
            if isReady, !pending, let webView {
                pending = true
                result = nil
                webView.evaluateJavaScript(script) { value, error in
                    result = error.map { .failure($0) } ?? .success(value ?? NSNull())
                    pending = false
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        throw NSError(domain: "ChatWebCacheCheck", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for synthetic renderer state: \(script); last result: \(String(describing: result)); scroll: \(String(describing: savedScroll))"])
    }
}
