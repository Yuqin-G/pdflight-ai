import AppKit
import Foundation
import WebKit

/// A single renderer can be moved between paper sidebars. Each sidebar remains
/// responsible for saving and restoring its own session and draft before use.
/// This is not yet connected to the production sidebar.
@MainActor
final class HarnessChatWebViewPool {
    static let shared = HarnessChatWebViewPool()

    private var webView: WKWebView?
    private weak var owner: NSView?
    private var generation: UInt64 = 0
    private var attachmentConstraints: [NSLayoutConstraint] = []
    private var saveBeforeDetach: (() async throws -> Void)?
    private var isTransferring = false

    init() {}

    enum TransferError: Error { case superseded, transferInProgress }

    /// Flush the old editor before moving its renderer; a failed flush leaves
    /// it attached. State belongs to the old sidebar, so it supplies the save.
    func attach(
        to host: NSView,
        makeWebView: () -> WKWebView,
        saveBeforeDetach: @escaping () async throws -> Void
    ) async throws -> Lease {
        guard !isTransferring else { throw TransferError.transferInProgress }
        isTransferring = true
        defer { isTransferring = false }
        if owner != nil, let save = self.saveBeforeDetach {
            let expectedGeneration = generation
            try await save()
            guard generation == expectedGeneration else { throw TransferError.superseded }
        }
        let renderer = webView ?? makeWebView()
        webView = renderer
        generation &+= 1
        NSLayoutConstraint.deactivate(attachmentConstraints)
        attachmentConstraints.removeAll()
        renderer.removeFromSuperview()
        renderer.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(renderer)
        attachmentConstraints = [
            renderer.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            renderer.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            renderer.topAnchor.constraint(equalTo: host.topAnchor),
            renderer.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ]
        NSLayoutConstraint.activate(attachmentConstraints)
        owner = host
        self.saveBeforeDetach = saveBeforeDetach
        return Lease(generation: generation, webView: renderer)
    }

    /// A stale paper may not release a renderer after another paper acquired it.
    func detach(_ lease: Lease) async throws {
        guard isCurrent(lease) else { return }
        guard !isTransferring else { throw TransferError.transferInProgress }
        isTransferring = true
        defer { isTransferring = false }
        try await saveBeforeDetach?()
        guard isCurrent(lease) else { throw TransferError.superseded }
        generation &+= 1
        NSLayoutConstraint.deactivate(attachmentConstraints)
        attachmentConstraints.removeAll()
        webView?.removeFromSuperview()
        owner = nil
        saveBeforeDetach = nil
    }

    func isCurrent(_ lease: Lease) -> Bool {
        guard let leasedView = lease.webView else { return false }
        return generation == lease.generation && webView === leasedView && owner != nil
    }

    /// Release WebKit when there is no active paper. Unsaved drafts and running
    /// requests must already belong to the native session, not to this view.
    func discardDetachedRenderer() {
        guard owner == nil, !isTransferring else { return }
        webView?.stopLoading()
        webView = nil
    }

    struct Lease {
        fileprivate let generation: UInt64
        /// A stale lease must not keep an inactive WebKit renderer alive.
        fileprivate(set) weak var webView: WKWebView?
    }
}
