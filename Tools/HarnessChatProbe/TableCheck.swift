import AppKit
import WebKit

private final class TableResources: NSObject, WKURLSchemeHandler {
    let root: URL

    init(root: URL) { self.root = root }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "local" else {
            task.didFailWithError(NSError(domain: "TableCheckURL", code: 1))
            return
        }
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "TableCheckFile", code: 2))
            return
        }
        let mime = ["html": "text/html", "js": "text/javascript", "css": "text/css", "woff2": "font/woff2"]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Type": mime[file.pathExtension] ?? "application/octet-stream",
            "Access-Control-Allow-Origin": "*"
        ])!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Exercises the bundled production preview in isolated WebKit storage using
/// synthetic Markdown only. No Harness installation or conversation is read.
@main
private final class TableCheck: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let resources: TableResources
    var window: NSWindow!
    var webView: WKWebView!

    init(root: URL) { resources = TableResources(root: root) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 700),
                          styleMask: [.titled], backing: .buffered, defer: false)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: "pdflight")
        webView = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        window.contentView!.addSubview(webView)
        window.orderFront(nil)
        webView.load(URLRequest(url: URL(string: "pdflight://local/preview.html")!))
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            self.fail("Timed out waiting for bundled preview/table checks")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                for width in [420, 1100] {
                    window.setContentSize(NSSize(width: width, height: 700))
                    window.contentView?.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(150))
                    let result: Any? = try await withCheckedThrowingContinuation { continuation in
                        webView.callAsyncJavaScript(Self.check, arguments: [:], in: nil, in: .page) { result in
                            continuation.resume(with: result.map { Optional($0) })
                        }
                    }
                    print("PASS: table layout at \(width)px: \(result ?? "nil")")
                }
                NSApplication.shared.terminate(nil)
            } catch {
                let details = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                fail(details ?? error.localizedDescription)
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error.localizedDescription)
    }

    private func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(EXIT_FAILURE)
    }

    private static let check = #"""
    const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
    const assert = (condition, message) => { if (!condition) throw new Error(message); };
    for (let i = 0; i < 100 && (!window.PDFlightReplaceMessages || !window.__setChatZoom); i++) await delay(20);
    assert(window.PDFlightReplaceMessages && window.__setChatZoom, 'Production preview did not initialize');
    const columns = ['模型 Model', 'Harmful Queries 有害查询长标题', '防御成功率', '序列 Token Reward 的解释', '评估 Evaluation'];
    const markdown = '# 表格测试 Heading\n\n正文内容 Normal body text。\n\n---\n\n## 2. 方法设计\n\n'
      + '| ' + columns.join(' | ') + ' |\n| ' + columns.map(() => '---').join(' | ') + ' |\n| '
      + ['GRPO', 'Llama Guard generates sequence rewards and cannot identify individual unsafe tokens',
         '95.2%', '$\\mathcal{S}=\\{128,256,1024\\}$', 'LongUnbrokenIdentifier'.repeat(10)].join(' | ') + ' |\n| '
      + columns.map(value => value + '文本').join(' | ') + ' |';
    window.PDFlightReplaceMessages([{id: 'synthetic-table', role: 'assistant', content: markdown, createdAt: '2026-11-02T00:00:00Z'}]);
    await delay(250);
    const measurements = [];
    for (const zoom of [.8, 1, 1.6, 2.4]) {
      window.__setChatZoom(zoom);
      await delay(150);
      const heading = document.querySelector('h1');
      const paragraph = document.querySelector('p');
      const table = document.querySelector('table');
      const rule = document.querySelector('hr');
      const sectionHeading = document.querySelector('h2');
      assert(sectionHeading && getComputedStyle(sectionHeading).marginTop === '16px', 'Heading after divider should use the compact 16px gap');
      assert(rule && getComputedStyle(rule).marginTop === '16px' && getComputedStyle(rule).marginBottom === '16px', 'Section divider spacing should be 16px');
      assert(heading && paragraph && table, `Markdown structure missing at ${zoom}`);
      assert(table.rows.length === 3 && table.rows[0].cells.length === columns.length, 'Table cells were lost');
      for (const element of [heading, paragraph, table.querySelector('th')]) {
        const style = getComputedStyle(element);
        assert(parseFloat(style.fontSize) > 0 && parseFloat(style.lineHeight) > 0, `Unresolved ${element.tagName} typography`);
      }
      const paragraphBounds = paragraph.getBoundingClientRect();
      const areaBounds = document.getElementById('chat-body').getBoundingClientRect();
      assert(paragraphBounds.left > areaBounds.left + 1, `Missing left gutter at ${zoom}`);
      const rightGutter = areaBounds.right - paragraphBounds.right;
      assert(rightGutter > 1, `Missing right gutter at ${zoom}`);
      assert(document.documentElement.scrollWidth <= innerWidth + 1 && document.body.scrollWidth <= innerWidth + 1, `Page horizontally overflowed at ${zoom}`);
      const wrapper = table.parentElement;
      // Harness reveals wide-table scrolling for keyboard focus or hover;
      // its wrapper may break out of the centered message column.
      wrapper.focus();
      await delay(30);
      const bounds = wrapper.getBoundingClientRect();
      assert(bounds.left >= areaBounds.left - 1 && bounds.right <= areaBounds.right + 1, `Table escaped the reading viewport at ${zoom}`);
      assert(['auto', 'scroll', 'hidden'].includes(getComputedStyle(wrapper).overflowX), 'Wide table has no scroll container');
      wrapper.scrollLeft = 0;
      const tableLeft = table.getBoundingClientRect().left;
      assert(tableLeft >= bounds.left - 1 && tableLeft < bounds.right, `First column inaccessible at ${zoom}`);
      wrapper.scrollLeft = wrapper.scrollWidth;
      const tableRight = table.getBoundingClientRect().right;
      // CSSOM scrollWidth/scrollLeft round to layout pixels before the host
      // scales them, so the final edge can differ by one unscaled CSS pixel.
      assert(tableRight <= bounds.right + Math.max(1, zoom), `Last column inaccessible at ${zoom}: ${tableRight} > ${bounds.right}`);
      if (wrapper.scrollWidth > wrapper.clientWidth + 1) assert(wrapper.scrollLeft > 0, `Wide table cannot scroll at ${zoom}`);
      measurements.push({zoom, leftGutter: +(paragraphBounds.left - areaBounds.left).toFixed(2), rightGutter: +rightGutter.toFixed(2), horizontalRange: wrapper.scrollLeft});
      wrapper.scrollLeft = 0;
      wrapper.blur();
    }
    // Exercise the real React projection and selection after repeated updates;
    // hanging-space compatibility must never rewrite the user's literal text.
    for (const literal of ['  leading  double   spaces  ', '\nfirst line\n    indented\nlast\n', 'tabs\tremain\t\tliteral', 'Explain this table.', '请解释表格与方法。 Explain this table.']) {
      window.PDFlightReplaceMessages([{id:'literal-user',role:'user',content:literal,createdAt:'2026-11-02T00:01:00Z'}]);
      await delay(80);
      const bubble=document.querySelector('[class*="_bubble"]');
      assert(bubble?.textContent===literal, 'User whitespace changed in the DOM');
      const range=document.createRange();range.selectNodeContents(bubble);
      const selection=getSelection();selection.removeAllRanges();selection.addRange(range);
      assert(selection.toString()===literal, 'User whitespace changed in copied selection');
      selection.removeAllRanges();
    }
    assert(!window.__errors?.length, 'Preview errors: ' + JSON.stringify(window.__errors));
    return JSON.stringify(measurements);
    """#

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: table-check <production HarnessChat directory>\n", stderr)
            exit(EXIT_FAILURE)
        }
        let application = NSApplication.shared
        let delegate = TableCheck(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
