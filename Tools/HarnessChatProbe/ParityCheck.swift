import AppKit
import WebKit

private final class ParityResources: NSObject, WKURLSchemeHandler {
    let roots: [String: URL]
    init(production: URL, reference: URL) { roots = ["production": production, "reference": reference] }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let root = roots[url.host ?? ""] else { return }
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "ParityFile", code: 1)); return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "woff2": "font/woff2", "svg": "image/svg+xml"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Compares the migrated renderer with separately extracted, original Harness
/// components and reading/theme styles. All displayed conversation data is synthetic.
@main
private final class ParityCheck: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let resources: ParityResources
    let output: URL
    let chromiumReference: URL?
    var windows: [NSWindow] = []
    var views: [WKWebView] = []
    var loaded = 0

    init(production: URL, reference: URL, output: URL, chromiumReference: URL?) {
        resources = ParityResources(production: production, reference: reference)
        self.output = output
        self.chromiumReference = chromiumReference
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (index, page) in ["production/preview.html", "reference/reference.html"].enumerated() {
            let window = NSWindow(contentRect: NSRect(x: 100 + index * 30, y: 100, width: 420, height: 900), styleMask: [.titled], backing: .buffered, defer: false)
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.setURLSchemeHandler(resources, forURLScheme: "parity")
            let view = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
            view.autoresizingMask = [.width, .height]
            view.navigationDelegate = self
            window.contentView!.addSubview(view)
            window.orderFront(nil)
            windows.append(window); views.append(view)
            view.load(URLRequest(url: URL(string: "parity://" + page)!))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("FAIL: parity timed out"); exit(1) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded += 1
        guard loaded == 2 else { return }
        Task { @MainActor in
            do {
                for view in views { _ = try await evaluate(Self.fixture, view: view) }
                var failures: [String] = []
                for width in [420, 680, 1100] {
                    for window in windows { window.setContentSize(NSSize(width: width, height: 900)) }
                    for zoom in [0.8, 1.0, 1.6, 2.4] {
                        var samples: [Any] = []
                        for view in views {
                            let text = try await evaluate("window.__setChatZoom(\(zoom));\n" + Self.measure, view: view) as! String
                            samples.append(try JSONSerialization.jsonObject(with: Data(text.utf8)))
                        }
                        let label = "\(width)px-\(Int(zoom * 100))pct"
                        let expected: Any
                        if let chromiumReference {
                            let data = try Data(contentsOf: chromiumReference.appendingPathComponent("\(label)-reference.json"))
                            expected = try JSONSerialization.jsonObject(with: data)
                        } else {
                            expected = samples[1]
                        }
                        let differences = Self.differences(samples[0], expected, path: "layout", zoom: zoom,
                                                            pixelScale: Double(windows[0].backingScaleFactor))
                        for (index, view) in views.enumerated() {
                            let name = index == 0 ? "migrated" : "reference"
                            let data = try JSONSerialization.data(withJSONObject: samples[index], options: [.prettyPrinted, .sortedKeys])
                            try data.write(to: output.appendingPathComponent("\(label)-\(name).json"))
                            try await snapshot(view, to: output.appendingPathComponent("\(label)-\(name).png"))
                        }
                        if differences.isEmpty { print("PASS: Harness reading parity \(label) (\(chromiumReference == nil ? "same-engine" : "Chromium reference"))") }
                        else {
                            failures.append("\(label): \(differences.prefix(8).joined(separator: "; "))")
                            print("FAIL: \(failures.last!)")
                        }
                    }
                }
                print("Parity metrics and screenshots: \(output.path)")
                exit(failures.isEmpty ? 0 : 1)
            } catch {
                print("FAIL: \((error as NSError).userInfo)"); exit(1)
            }
        }
    }

    private func evaluate(_ script: String, view: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            view.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { continuation.resume(with: $0) }
        }
    }

    private func snapshot(_ view: WKWebView, to url: URL) async throws {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = view.bounds
        let image: NSImage = try await withCheckedThrowingContinuation { continuation in
            view.takeSnapshot(with: configuration) { image, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: image!) }
            }
        }
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try representation.representation(using: .png, properties: [:])!.write(to: url)
    }

    private static func differences(_ actual: Any, _ expected: Any, path: String, zoom: Double, pixelScale: Double) -> [String] {
        if let actual = actual as? [String: Any], let expected = expected as? [String: Any] {
            return Set(actual.keys).union(expected.keys).sorted().flatMap { key -> [String] in
                guard let a = actual[key], let e = expected[key] else { return ["\(path).\(key): missing key"] }
                return differences(a, e, path: path + "." + key, zoom: zoom, pixelScale: pixelScale)
            }
        }
        if let actual = actual as? [Any], let expected = expected as? [Any] {
            guard actual.count == expected.count else { return ["\(path): count \(actual.count) != \(expected.count)"] }
            return actual.indices.flatMap { differences(actual[$0], expected[$0], path: path + "[\($0)]", zoom: zoom, pixelScale: pixelScale) }
        }
        if let actual = actual as? NSNumber, let expected = expected as? NSNumber {
            if CFGetTypeID(actual) == CFBooleanGetTypeID() || CFGetTypeID(expected) == CFBooleanGetTypeID() {
                return actual.boolValue == expected.boolValue ? [] : ["\(path): \(actual) != \(expected)"]
            }
            let tolerance: Double
            if path.hasSuffix(".lineCount") { tolerance = 0 }
            else if path.contains(".tables[") && path.hasSuffix(".range") { tolerance = 1 }
            else if path.contains(".tables[") && path.hasSuffix(".tableRight") { tolerance = max(1, zoom) }
            else if path.hasSuffix(".top") || path.hasSuffix(".bottom") { tolerance = 3 }
            else if path.hasSuffix(".height") { tolerance = path.contains(".elements[0].") ? 3 : 2 }
            else { tolerance = 1 }
            let geometric = [".left", ".right", ".top", ".bottom", ".width", ".height", ".tableRight"].contains(where: path.hasSuffix)
            // Preserve raw metrics on disk, but compare bounds on the same
            // physical pixel grid used to display both screenshots.
            let a = geometric ? (actual.doubleValue * pixelScale).rounded() / pixelScale : actual.doubleValue
            let e = geometric ? (expected.doubleValue * pixelScale).rounded() / pixelScale : expected.doubleValue
            return abs(a - e) <= tolerance ? [] : ["\(path): \(actual) != \(expected)"]
        }
        if let actual = actual as? String, let expected = expected as? String {
            if path.hasSuffix(".fontFamily") {
                let normalize: (String) -> String = {
                    $0.replacingOccurrences(of: "BlinkMacSystemFont", with: "system-ui")
                        .replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                        .replacingOccurrences(of: "Harness WebKit CJK, ", with: "")
                }
                if normalize(actual) == normalize(expected) { return [] }
            }
            if actual.hasSuffix("px"), expected.hasSuffix("px"),
               let a = Double(actual.dropLast(2)), let e = Double(expected.dropLast(2)) {
                let tolerance = path.hasSuffix(".fontSize") || path.hasSuffix(".lineHeight") ? 0.02 : 1
                if abs(a - e) <= tolerance { return [] }
            }
        }
        return String(describing: actual) == String(describing: expected) ? [] : ["\(path): \(actual) != \(expected)"]
    }

    private static let fixture = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("parity-fixture.js"), encoding: .utf8)

    private static let measure = try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("parity-metrics.js"), encoding: .utf8)

    static func main() {
        guard (4...5).contains(CommandLine.arguments.count) else { print("Usage: parity-check <production resources> <prepared original Harness reference> <output directory> [Chromium reference metrics directory]"); exit(1) }
        let application = NSApplication.shared
        let delegate = ParityCheck(production: URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL, reference: URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL, output: URL(fileURLWithPath: CommandLine.arguments[3]).standardizedFileURL, chromiumReference: CommandLine.arguments.count == 5 ? URL(fileURLWithPath: CommandLine.arguments[4]).standardizedFileURL : nil)
        application.delegate=delegate; application.setActivationPolicy(.accessory); application.run(); withExtendedLifetime(delegate) {}
    }
}
