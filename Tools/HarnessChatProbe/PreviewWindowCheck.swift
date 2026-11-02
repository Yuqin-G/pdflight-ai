import AppKit
import WebKit
import PDFlightAI

@main @MainActor struct PreviewWindowCheck {
 static func main() async throws {
  _ = NSApplication.shared
  let first = HarnessChatPreview(frame: NSRect(x: 0,y: 0,width: 440,height: 700))
  let second = HarnessChatPreview(frame: NSRect(x: 0,y: 0,width: 600,height: 800))
  let firstWindow = NSWindow(contentRect: first.frame, styleMask: [.titled], backing: .buffered, defer: false)
  let secondWindow = NSWindow(contentRect: second.frame, styleMask: [.titled], backing: .buffered, defer: false)
  firstWindow.contentView = first; secondWindow.contentView = second
  defer { firstWindow.contentView = nil; secondWindow.contentView = nil }
  first.activate()
  first.activate() // Duplicate key-window notifications must be harmless.
  try await Task.sleep(for: .milliseconds(100))
  guard let firstRenderer = first.subviews.first as? WKWebView else { fatalError("first preview did not attach") }
  second.activate()
  try await Task.sleep(for: .milliseconds(100))
  guard firstRenderer.superview === first else { fatalError("Switching to the second window removed the first window's chat") }
  guard let secondRenderer = second.subviews.first as? WKWebView, secondRenderer !== firstRenderer else { fatalError("Two visible windows share a mutable chat renderer") }
  first.activate()
  try await Task.sleep(for: .milliseconds(100))
  guard first.subviews.first === firstRenderer, secondRenderer.superview === second else { fatalError("Reactivation changed either window's renderer") }
  if CommandLine.arguments.contains("--rendered") {
   firstWindow.contentView?.layoutSubtreeIfNeeded()
   secondWindow.contentView?.layoutSubtreeIfNeeded()
   first.replace([AIChatMessage(role: .assistant, content: "First window fixture\n\n## 窗口独立显示检查\n\n" + Array(repeating: "切换窗口后，对话内容、缩放和滚动位置应保持稳定。", count: 35).joined(separator: "\n\n"))])
   second.replace([AIChatMessage(role: .assistant, content: "Second window fixture")])
   first.setZoom(0.8); second.setZoom(1.4)
   for _ in 0..<100 {
    let ready1 = (try? await firstRenderer.evaluateJavaScript("typeof window.__setChatZoom === 'function'")) as? Bool ?? false
    let ready2 = (try? await secondRenderer.evaluateJavaScript("typeof window.__setChatZoom === 'function'")) as? Bool ?? false
    if ready1 && ready2 { break }
    try await Task.sleep(for: .milliseconds(100))
   }
   try await Task.sleep(for: .milliseconds(200))
   let firstZoom = try await firstRenderer.evaluateJavaScript("Number(document.querySelector('#chat-body').dataset.chatZoom)") as? Double
   let secondZoom = try await secondRenderer.evaluateJavaScript("Number(document.querySelector('#chat-body').dataset.chatZoom)") as? Double
   guard firstZoom == 0.8, secondZoom == 1.4 else { fatalError("Each preview must apply its own requested zoom: \(String(describing:firstZoom)), \(String(describing:secondZoom))") }
   var reportedZoom: CGFloat?
   first.onZoomChanged = { reportedZoom = $0 }
   _ = try await firstRenderer.evaluateJavaScript("window.__setChatZoom(1.2)")
   try await Task.sleep(for: .milliseconds(100))
   guard reportedZoom == 1.2 else { fatalError("Web zoom did not reach the native controls") }
   let firstScroll = try await firstRenderer.evaluateJavaScript("(() => { const s = [...document.querySelectorAll('#chat-body *')].find(e => e.scrollHeight > e.clientHeight + 20 && getComputedStyle(e).overflowY !== 'visible'); if (!s) return null; s.scrollTop = 100; window.__windowCheckScroller = s; return s.scrollTop; })()") as? Double
   guard let firstScroll, firstScroll > 0 else { fatalError("Scrolling fixture did not produce overflow") }
   first.activate(); second.activate()
   let restoredScroll = try await firstRenderer.evaluateJavaScript("window.__windowCheckScroller.scrollTop") as? Double
   guard restoredScroll == firstScroll else { fatalError("Window activation reset the previous scroll position") }
   let firstText = try await firstRenderer.evaluateJavaScript("document.body.innerText.includes('First window fixture')") as? Bool
   let secondText = try await secondRenderer.evaluateJavaScript("document.body.innerText.includes('Second window fixture')") as? Bool
   guard firstText == true, secondText == true else { fatalError("Window activation changed the rendered conversation") }
   if CommandLine.arguments.contains("--snapshot") {
    let image = try await firstRenderer.takeSnapshot(configuration: nil)
    if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
     try png.write(to: URL(fileURLWithPath: "/tmp/pdflight-window-check.png"))
    }
   }
   print("PASS: real bundled chat keeps each window's content and zoom; WebKit zoom reports to native")
  }
  first.close(); second.close()
  try await Task.sleep(for: .milliseconds(100))
  guard first.subviews.isEmpty, second.subviews.isEmpty else { fatalError("Close retained the renderer") }
  let closing = HarnessChatPreview(frame: NSRect(x: 0, y: 0, width: 400, height: 700))
  closing.activate(); closing.close()
  try await Task.sleep(for: .milliseconds(100))
  guard closing.subviews.isEmpty else { fatalError("Closing before activation completed leaked a renderer") }
  closing.activate()
  try await Task.sleep(for: .milliseconds(100))
  guard closing.subviews.isEmpty else { fatalError("Closed preview was reactivated") }
  print("PASS: two previews retain independent renderers across window activation and release on close, including close before ready")
 }
}
