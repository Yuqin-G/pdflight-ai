import AppKit
import WebKit

@main
@MainActor
struct PoolCheck {
    static func main() async throws {
        _ = NSApplication.shared
        let pool = HarnessChatWebViewPool.shared
        let hosts = (0..<9).map { _ in NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 700)) }
        var instances = 0
        var saved: [Int] = []
        var first: HarnessChatWebViewPool.Lease?
        var last: HarnessChatWebViewPool.Lease?
        for index in hosts.indices {
            let lease = try await pool.attach(to: hosts[index], makeWebView: {
                instances += 1
                return WKWebView(frame: .zero)
            }, saveBeforeDetach: { saved.append(index) })
            if first == nil { first = lease }
            if let first, first.webView !== lease.webView { fatalError("renderer was not reused") }
            last = lease
        }
        guard instances == 1, saved == Array(0..<8), let first, let last else {
            fatalError("incorrect renderer reuse or save ordering")
        }
        try await pool.detach(first)
        guard pool.isCurrent(last) else { fatalError("stale lease detached active paper") }
        try await pool.detach(last)
        guard saved == Array(0..<9), !pool.isCurrent(last) else { fatalError("final draft was not saved") }
        pool.discardDetachedRenderer()
        try await Task.sleep(for: .milliseconds(100))
        guard last.webView == nil else { fatalError("a stale lease retained the discarded WebView") }

        enum TestError: Error { case failedSave }
        let retained = try await pool.attach(to: hosts[0], makeWebView: { WKWebView(frame: .zero) }, saveBeforeDetach: { throw TestError.failedSave })
        do {
            _ = try await pool.attach(to: hosts[1], makeWebView: { WKWebView(frame: .zero) }, saveBeforeDetach: {})
            fatalError("transfer must stop when draft save fails")
        } catch TestError.failedSave {}
        guard pool.isCurrent(retained), retained.webView?.superview === hosts[0] else {
            fatalError("failed save lost the original owner")
        }
        print("PASS: nine paper hosts reused one view; saves and stale leases were handled")
    }
}
