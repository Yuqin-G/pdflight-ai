import Cocoa
import WebKit
final class LocalResources: NSObject, WKURLSchemeHandler {
 let root: URL
 init(root: URL) { self.root = root }
 func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
  guard let url=task.request.url, url.host == "local" else { task.didFailWithError(NSError(domain:"url",code:1)); return }
  let f=root.appendingPathComponent(url.path).standardizedFileURL
  guard f.path.hasPrefix(root.path+"/"),let data=try? Data(contentsOf:f) else {task.didFailWithError(NSError(domain:"file",code:2));return}
  let types=["html":"text/html","js":"text/javascript","css":"text/css","woff2":"font/woff2","svg":"image/svg+xml","json":"application/json"]
  let mime=types[f.pathExtension] ?? "application/octet-stream"; let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Type":mime,"Access-Control-Allow-Origin":"*"])!
  task.didReceive(response);task.didReceive(data);task.didFinish()
 }
 func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}
@main final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate {
 var window: NSWindow!; var web: WKWebView!;let handler: LocalResources;let composer: Bool
 init(root: URL, composer: Bool) { handler = LocalResources(root: root); self.composer = composer }
 func applicationDidFinishLaunching(_ note: Notification) {
  window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 680, height: 950), styleMask: [.titled,.closable], backing: .buffered, defer: false)
  let config=WKWebViewConfiguration();config.setURLSchemeHandler(handler,forURLScheme:"pdflight");web = WKWebView(frame: window.contentView!.bounds,configuration:config); web.autoresizingMask = [.width,.height]; web.navigationDelegate = self; window.contentView!.addSubview(web); window.makeKeyAndOrderFront(nil)
  web.load(URLRequest(url:URL(string: composer ? "pdflight://local/composer.html" : "pdflight://local/probe.html")!))
 }
 func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
  if composer {
   DispatchQueue.main.asyncAfter(deadline:.now()+3) {
    self.web.callAsyncJavaScript("return await window.__checkLiteralSubmission()", arguments: [:], in: nil, in: .page, completionHandler: { result in
     switch result { case .success(let value): print("LITERAL SUBMISSION: \(value)"); case .failure(let error): print("LITERAL SUBMISSION FAILED: \(error.localizedDescription)") }
     NSApplication.shared.terminate(nil)
    })
   }
   return
  }
  DispatchQueue.main.asyncAfter(deadline:.now()+3) { self.web.evaluateJavaScript("JSON.stringify({text:document.body.innerText.length,katex:document.querySelectorAll('.katex').length,rows:document.querySelectorAll('[data-chat-node-key]').length,zoom:CSS.supports('zoom','1.1'),errors:window.__errors})") { value,error in
    if let error { print("FAILED: \(error.localizedDescription)"); NSApplication.shared.terminate(nil) } else {
      print("WEBKIT: \(value ?? "nil")")
      self.web.callAsyncJavaScript("return await window.__runZoomBenchmark()", arguments: [:], in: nil, in: .page, completionHandler: { result in
       switch result { case .success(let value): print("ZOOM: \(value)"); case .failure(let error): print("ZOOM FAILED: \(error.localizedDescription)") }
       self.web.callAsyncJavaScript("return await window.__boundsCheck()", arguments: [:], in: nil, in: .page, completionHandler: { result in
        switch result { case .success(let value): print("BOUNDS: \(value)"); case .failure(let error): print("BOUNDS FAILED: \(error.localizedDescription)") }
        NSApplication.shared.terminate(nil)
       })
      })
    }
   }
  }
 }
 func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { print("FAILED: \(error)"); NSApplication.shared.terminate(nil) }
 static func main(){let app=NSApplication.shared;guard (2...3).contains(CommandLine.arguments.count) else { print("Usage: runner <probe directory> [composer]"); return };let delegate=Probe(root: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL, composer: CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "composer");app.delegate=delegate;app.setActivationPolicy(.regular);app.run();withExtendedLifetime(delegate) {}}
}
