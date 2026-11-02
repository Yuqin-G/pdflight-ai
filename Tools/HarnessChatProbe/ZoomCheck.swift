import AppKit
import WebKit

/// Exercises the bundled production chat in WebKit using synthetic messages only.
private final class Resources: NSObject, WKURLSchemeHandler {
    let root: URL
    init(root: URL) { self.root = root }
    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didFailWithError(NSError(domain: "ZoomCheckFile", code: 1)); return
        }
        let types = ["html": "text/html", "js": "text/javascript", "css": "text/css", "woff2": "font/woff2", "svg": "image/svg+xml"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": types[file.pathExtension] ?? "application/octet-stream", "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(data); task.didFinish()
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@main
private final class ZoomCheck: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    let resources: Resources
    var window: NSWindow!
    var web: WKWebView!
    var failed = false
    init(root: URL) { resources = Resources(root: root) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            print("FAIL WebKit zoom: timed out waiting for the bundled chat")
            exit(1)
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(resources, forURLScheme: "pdflight-chat")
        window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 680, height: 950), styleMask: [.titled], backing: .buffered, defer: false)
        web = WKWebView(frame: window.contentView!.bounds, configuration: configuration)
        web.autoresizingMask = [.width, .height]; web.navigationDelegate = self
        window.contentView!.addSubview(web); window.orderFront(nil)
        web.load(URLRequest(url: URL(string: "pdflight-chat://local/preview.html")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            do {
                // Module execution and the ready callback occur after navigation.
                _ = try await evaluate("""
                for(let i=0;i<100 && !window.__setChatZoom;i++) await new Promise(r=>setTimeout(r,20));
                if(!window.__setChatZoom) throw new Error('chat zoom did not become ready');
                PDFlightReplaceMessages(Array.from({length:30},(_,i)=>({id:'fixture-'+i,role:'assistant',content:'Paragraph '+i+' '+ '缩放尺寸验证 test text. '.repeat(30),createdAt:'2026-01-01T00:00:00Z'})));
                await new Promise(r=>setTimeout(r,100));
                """)
                for size in [NSSize(width: 680, height: 950), NSSize(width: 340, height: 540), NSSize(width: 980, height: 700)] {
                    window.setContentSize(size)
                    let result = try await evaluate(Self.checkScript)
                    print("PASS WebKit zoom: \(result)")
                }
            } catch { failed = true; print("FAIL WebKit zoom: \((error as NSError).userInfo)") }
            exit(failed ? 1 : 0)
        }
    }

    private func evaluate(_ script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                continuation.resume(with: result)
            }
        }
    }

    private static let checkScript = """
    const wait=()=>new Promise(r=>setTimeout(r,100));
    const assert=(ok,message)=>{if(!ok)throw new Error(message)};
    const area=document.getElementById('chat-body');
    const paragraph=area.querySelector('[class*="_markdown_"] p');
    assert(!!paragraph,'missing rendered fixture');
    const text=paragraph.firstChild, range=document.createRange();
    range.setStart(text,0);range.setEnd(text,3);
    const cjkProbe=document.createElement('span');
    cjkProbe.textContent='缩放尺寸';cjkProbe.style.display='inline-block';cjkProbe.style.whiteSpace='nowrap';
    paragraph.appendChild(cjkProbe);
    const mediumProbe=document.createElement('span');
    mediumProbe.textContent='Safety 防御成功率';
    mediumProbe.style.cssText='display:inline-block;white-space:nowrap;font-size:13px;font-weight:500';
    paragraph.appendChild(mediumProbe);
    await document.fonts.load("14px 'Harness WebKit CJK'",'缩放尺寸');
    await document.fonts.load("500 13px 'Harness WebKit CJK'",'防御成功率');
    window.__setChatZoom(1);paragraph.scrollIntoView();await wait();
    const baseline=range.getBoundingClientRect().width;
    const typography=getComputedStyle(paragraph);
    assert(typography.fontSize==='14px','markdown font size '+typography.fontSize+' expected 14px');
    assert(typography.lineHeight==='24px','markdown line height '+typography.lineHeight+' expected 24px');
    const sizes=[];let previousGlyphWidth=0;
    for(const value of [.8,1,1.4,2.4]) {
      window.__setChatZoom(value);paragraph.scrollIntoView();await wait();
      const rect=area.getBoundingClientRect();
      assert(Math.abs(rect.height-innerHeight)<1,'zoom '+value+' height '+rect.height+' viewport '+innerHeight);
      assert(Math.abs(rect.width-innerWidth)<1,'zoom '+value+' width '+rect.width+' viewport '+innerWidth);
      assert(document.documentElement.scrollHeight<=innerHeight+1,'page overflow at zoom '+value);
      const glyphWidth=range.getBoundingClientRect().width;
      assert(glyphWidth>previousGlyphWidth,'text did not grow with zoom '+value);
      previousGlyphWidth=glyphWidth;
      const textScale=glyphWidth/baseline;
      const cjkWidth=cjkProbe.getBoundingClientRect().width;
      assert(Math.abs(cjkWidth-56*value)<.1,'CJK advance differs from Chromium at zoom '+value+': '+cjkWidth);
      const mediumWidth=mediumProbe.getBoundingClientRect().width;
      assert(Math.abs(mediumWidth-108.203125*value)<.1,'13px Medium mixed text differs from Chromium at zoom '+value+': '+mediumWidth);
      assert(Math.abs(textScale-value)<.02,'glyph scaling differs from effective zoom '+value);
      assert(Math.abs(Number(area.dataset.chatZoom)-value)<.001,'effective zoom differs from request');
      sizes.push({zoom:value,width:rect.width,height:rect.height,textScale,cjkWidth,mediumWidth});
    }
    window.__setChatZoom(1);
    const wheel=new WheelEvent('wheel',{ctrlKey:true,deltaY:-25,cancelable:true,bubbles:true});
    area.dispatchEvent(wheel);await wait();
    assert(wheel.defaultPrevented,'zoom wheel not consumed');
    assert(Math.abs(Number(area.dataset.chatZoom)-Math.exp(.1))<.001,'wheel sensitivity differs from Harness');
    const gesture=(type,scale)=>{const event=new Event(type,{cancelable:true});if(scale!==undefined)Object.defineProperty(event,'scale',{value:scale});area.dispatchEvent(event);assert(event.defaultPrevented,type+' not consumed')};
    gesture('gesturestart');gesture('gesturechange',2);await wait();
    assert(Math.abs(Number(area.dataset.chatZoom)-Math.exp(.1)*2)<.001,'pinch should multiply gesture starting zoom');
    gesture('gestureend');
    window.__setChatZoom(100);assert(Number(area.dataset.chatZoom)===2.4,'upper clamp');
    window.__setChatZoom(-100);assert(Number(area.dataset.chatZoom)===.8,'lower clamp');
    window.__setChatZoom(NaN);assert(Number(area.dataset.chatZoom)===.8,'invalid zoom corrupts state');
    assert(window.__errors.length===0,'runtime errors '+window.__errors.join(','));
    return JSON.stringify({viewport:[innerWidth,innerHeight],font:typography.fontSize,lineHeight:typography.lineHeight,sizes,gestures:true});
    """

    static func main() {
        guard CommandLine.arguments.count == 2 else { print("Usage: ZoomCheck <bundled HarnessChat directory>"); exit(2) }
        let app = NSApplication.shared
        let delegate = ZoomCheck(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL)
        app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
        if delegate.failed { exit(1) }
        withExtendedLifetime(delegate) {}
    }
}
