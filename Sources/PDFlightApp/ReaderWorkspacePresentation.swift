import AppKit

/// One native window for the workspace. Document views stay attached to it while
/// hidden, so switching does not recreate a window, full-screen space or WebView.
@MainActor
final class ReaderWorkspaceWindow: NSWindow {
    var onCloseDocument: (() -> Void)?
    var onPageKeyAction: ((ReaderPageKeyAction) -> Void)?

    override func performClose(_ sender: Any?) { onCloseDocument?() }
    override func close() { onCloseDocument?() }
    func closeWorkspace() { super.close() }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           let action = ReaderPageKeyRouting.action(keyCode: event.keyCode,
                modifiers: event.modifierFlags, isEditingText: firstResponder is NSTextView) {
            onPageKeyAction?(action)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ReaderWorkspacePresentation {
    @MainActor
    private final class Entry {
        let controller: NSWindowController
        let parkingWindow: NSWindow
        let root: NSView
        weak var responder: NSResponder?
        init(_ controller: NSWindowController) {
            self.controller = controller
            parkingWindow = controller.window!
            root = parkingWindow.contentView!
        }
    }

    let window = ReaderWorkspaceWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 780),
        styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var selected: Entry?

    init() {
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 620, height: 400)
        window.contentView = NSView()
    }

    func show(_ controller: NSWindowController) {
        guard selected?.controller !== controller else {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let identity = ObjectIdentifier(controller)
        let entry: Entry
        if let existing = entries[identity] { entry = existing }
        else {
            entry = Entry(controller)
            entries[identity] = entry
            if entries.count == 1 { window.setFrame(entry.parkingWindow.frame, display: false) }
            entry.parkingWindow.tabbingMode = .disallowed
            entry.parkingWindow.contentView = NSView()
            entry.root.translatesAutoresizingMaskIntoConstraints = true
            entry.root.autoresizingMask = [.width, .height]
            entry.root.isHidden = true
            window.contentView!.addSubview(entry.root)
        }
        if let old = selected {
            old.responder = window.firstResponder
            window.makeFirstResponder(nil)
            (old.controller as? ReaderWindowController)?.windowDidResignKey(
                Notification(name: NSWindow.didResignKeyNotification, object: window))
            let title = window.title
            let edited = window.isDocumentEdited
            old.controller.window = old.parkingWindow
            old.parkingWindow.title = title
            old.parkingWindow.isDocumentEdited = edited
            old.root.isHidden = true
        }
        selected = entry
        let title = entry.parkingWindow.title
        let edited = entry.parkingWindow.isDocumentEdited
        controller.window = window
        window.delegate = entry.parkingWindow.delegate
        window.title = title
        window.isDocumentEdited = edited
        entry.root.frame = window.contentView!.bounds
        entry.root.isHidden = false
        entry.root.layoutSubtreeIfNeeded()
        if let reader = controller as? ReaderWindowController {
            window.onPageKeyAction = { [weak reader] action in
                switch action {
                case .previous: reader?.previousPage(nil)
                case .next: reader?.nextPage(nil)
                case .highlightSelection: reader?.highlightSelectionFromKey()
                }
            }
        } else { window.onPageKeyAction = nil }
        let wasKey = window.isKeyWindow
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(entry.responder ?? entry.root)
        // The native window stays key when its selected document changes.
        if wasKey {
            window.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        }
    }

    /// Restore the document's private window before its existing close/save
    /// lifecycle runs. Never close the workspace window to close a document.
    func remove(_ controller: NSWindowController) {
        guard let entry = entries.removeValue(forKey: ObjectIdentifier(controller)) else { return }
        let edited = selected === entry ? window.isDocumentEdited : entry.parkingWindow.isDocumentEdited
        let title = selected === entry ? window.title : entry.parkingWindow.title
        if selected === entry {
            window.makeFirstResponder(nil)
            window.delegate = nil
            selected = nil
        }
        controller.window = entry.parkingWindow
        entry.parkingWindow.title = title
        entry.parkingWindow.isDocumentEdited = edited
        entry.root.removeFromSuperview()
        entry.parkingWindow.contentView = entry.root
    }

    var selectedController: NSWindowController? { selected?.controller }
}
