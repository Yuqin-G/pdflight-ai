import AppKit
import PDFlightAI
import WebKit

/// Bundled reading renderer; native input, history and execution stay local.
/// The native sidebar remains responsible for input, history and execution.
@MainActor
final class HarnessChatPreview: NSView, WKNavigationDelegate, WKScriptMessageHandler {
    // Keep the renderer with its window. Moving a singleton between two visible
    // sidebars blanks the previous window and carries the wrong scroll/zoom state.
    private let rendererPool = HarnessChatWebViewPool()
    private let relay = HarnessPreviewRelay()
    private var lease: HarnessChatWebViewPool.Lease?
    private var activationGeneration: UInt64 = 0
    private var isClosed = false
    private var isActivating = false
    private var isReady = false
    private var requestedZoom: CGFloat = 1
    var onZoomChanged: ((CGFloat) -> Void)?
    private var messages: [AIChatMessage] = []
    private var refreshWork: DispatchWorkItem?
    private let provider: HarnessPreviewResources

    override init(frame: NSRect) {
        let root = Bundle.main.resourceURL?.appendingPathComponent("HarnessChat", isDirectory: true)
            ?? URL(fileURLWithPath: "/nonexistent", isDirectory: true)
        provider = HarnessPreviewResources(root: root)
        super.init(frame: frame)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func activate() {
        guard !isClosed, !isActivating else { return }
        if let lease, rendererPool.isCurrent(lease) { return }
        isActivating = true
        activationGeneration &+= 1
        let generation = activationGeneration
        Task { [weak self] in
            guard let self else { return }
            defer { isActivating = false }
            guard !isClosed, activationGeneration == generation else { return }
            do {
                let next = try await rendererPool.attach(to: self, makeWebView: {
                    let configuration = WKWebViewConfiguration()
                    configuration.setURLSchemeHandler(self.provider, forURLScheme: "pdflight-chat")
                    self.relay.target = self
                    configuration.userContentController.add(self.relay, name: "harnessReady")
                    configuration.userContentController.add(self.relay, name: "harnessZoom")
                    let view = WKWebView(frame: .zero, configuration: configuration)
                    return view
                }, saveBeforeDetach: {})
                guard !isClosed, activationGeneration == generation else {
                    try? await rendererPool.detach(next)
                    rendererPool.discardDetachedRenderer()
                    return
                }
                lease = next
                next.webView?.navigationDelegate = self
                if next.webView?.url == nil {
                    next.webView?.load(URLRequest(url: URL(string: "pdflight-chat://local/preview.html")!))
                } else {
                    refresh()
                }
            } catch {
                NSLog("Harness preview could not activate: %@", error.localizedDescription)
            }
        }
    }

    func close() {
        isClosed = true
        activationGeneration &+= 1
        refreshWork?.cancel()
        relay.target = nil
        onZoomChanged = nil
        guard let lease else { return }
        let pool = rendererPool
        Task {
            try? await pool.detach(lease)
            pool.discardDetachedRenderer()
        }
        self.lease = nil
    }

    func replace(_ values: [AIChatMessage]) { messages = values; scheduleRefresh() }
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
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func refresh() {
        guard let lease, rendererPool.isCurrent(lease), let view = lease.webView else { return }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(messages),
              let object = try? JSONSerialization.jsonObject(with: data) else { return }
        view.callAsyncJavaScript("if (typeof window.PDFlightReplaceMessages !== 'function') return false; window.PDFlightReplaceMessages(messages); return true;", arguments: ["messages": object], in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("Harness preview refresh failed: %@", error.localizedDescription) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !isClosed else { return }
        if message.name == "harnessReady" {
            isReady = true
            applyZoom()
            refresh()
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
        guard isReady, let lease, rendererPool.isCurrent(lease), let view = lease.webView else { return }
        view.callAsyncJavaScript("window.__setChatZoom?.(zoom)", arguments: ["zoom": Double(requestedZoom)], in: nil, in: .page) { result in
            if case .failure(let error) = result { NSLog("Harness preview zoom failed: %@", error.localizedDescription) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "pdflight-chat" ? .allow : .cancel)
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
    let root: URL
    init(root: URL) { self.root = root.resolvingSymlinksInPath().standardizedFileURL }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "local" else {
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
