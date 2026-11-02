import AppKit
import WebKit

private final class LocalResources: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "local" else {
            task.didFailWithError(NSError(domain: "ProbeURL", code: 1))
            return
        }
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "ProbeFile", code: 2))
            return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "woff2": "font/woff2", "svg": "image/svg+xml", "json": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*"])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@main
private final class ManualViewer: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let handler: LocalResources
    private var window: NSWindow!
    private var webView: WKWebView!

    init(root: URL) { handler = LocalResources(root: root) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 150, y: 100, width: 680, height: 950), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "EOPSA · Harness 聊天缩放验证（独立原型）"
        window.delegate = self
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: "pdflight")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(webView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        webView.load(URLRequest(url: URL(string: "pdflight://local/probe.html")!))
    }

    func windowWillClose(_ notification: Notification) { NSApplication.shared.terminate(nil) }

    static func main() {
        guard CommandLine.arguments.count == 2 else { print("Usage: viewer <probe directory>"); return }
        let app = NSApplication.shared
        let delegate = ManualViewer(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL)
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
