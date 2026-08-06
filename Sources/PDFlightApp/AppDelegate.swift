import AppKit
import PDFlightCore
import PDFlightMuPDF

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var readers: [ReaderWindowController] = []
    private let readingPositionStore = ReadingPositionStore(fileURL: AppDelegate.readingStateURL)

    private static var readingStateURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["PDFLIGHT_READING_STATE_FILE"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryName = Bundle.main.bundleIdentifier ?? "dev.pdflight.reader"
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("reading-state.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()

        let arguments = CommandLine.arguments.dropFirst().map(URL.init(fileURLWithPath:))
        let PDFs = arguments.filter { $0.pathExtension.lowercased() == "pdf" }
        if PDFs.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.readers.isEmpty else { return }
                self.openDocument(nil)
            }
        } else {
            PDFs.forEach(open)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        readers.forEach { $0.saveReadingPosition() }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames.map(URL.init(fileURLWithPath:)).forEach(open)
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    @objc func saveDocument(_ sender: Any?) {
        keyReader?.saveDocument(sender)
    }

    @objc func undoAnnotation(_ sender: Any?) {
        if let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView,
           editor.isFieldEditor {
            if editor.undoManager?.canUndo == true {
                editor.undoManager?.undo()
            } else {
                NSSound.beep()
            }
            return
        }
        keyReader?.undoLastAnnotation(sender)
    }

    @objc func zoomIn(_ sender: Any?) {
        keyReader?.zoomIn(sender)
    }

    @objc func zoomOut(_ sender: Any?) {
        keyReader?.zoomOut(sender)
    }

    @objc func fitWidth(_ sender: Any?) {
        keyReader?.fitWidth(sender)
    }

    @objc func previousPage(_ sender: Any?) {
        keyReader?.previousPage(sender)
    }

    @objc func nextPage(_ sender: Any?) {
        keyReader?.nextPage(sender)
    }

    @objc func goBack(_ sender: Any?) {
        keyReader?.goBack(sender)
    }

    @objc func highlightSelection(_ sender: Any?) {
        keyReader?.highlightSelection(sender)
    }

    @objc func toggleNote(_ sender: Any?) {
        keyReader?.toggleNote(sender)
    }

    @objc func focusSearch(_ sender: Any?) {
        keyReader?.focusSearch(sender)
    }

    @objc func copySelection(_ sender: Any?) {
        keyReader?.copySelection(sender)
    }

    @objc func nextSearchResult(_ sender: Any?) {
        keyReader?.nextSearchResult(sender)
    }

    @objc func previousSearchResult(_ sender: Any?) {
        keyReader?.previousSearchResult(sender)
    }

    private var keyReader: ReaderWindowController? {
        readers.first { $0.window?.isKeyWindow == true }
    }

    private func open(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        if let existing = readers.first(where: { $0.documentURL.standardizedFileURL == normalizedURL }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        do {
            guard let engine = try openEngine(for: normalizedURL) else { return }
            let tabHost = keyReader?.window ?? readers.last?.window
            let reader = ReaderWindowController(
                url: normalizedURL,
                engine: engine,
                readingPositionStore: readingPositionStore
            )
            reader.onClose = { [weak self, weak reader] in
                guard let self, let reader else { return }
                self.readers.removeAll { $0 === reader }
            }
            readers.append(reader)
            if let tabHost, let newWindow = reader.window {
                tabHost.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            } else {
                reader.showWindow(nil)
            }
        } catch {
            present(error: error, title: "Could not open PDF")
        }
    }

    private func openEngine(for url: URL) throws -> MuPDFDocument? {
        var password: String?
        while true {
            do {
                return try MuPDFDocument(
                    url: url,
                    password: password,
                    storeLimit: 12 * 1_024 * 1_024
                )
            } catch DocumentEngineError.passwordRequired {
                password = promptForPassword(filename: url.lastPathComponent, incorrect: false)
                if password == nil { return nil }
            } catch DocumentEngineError.incorrectPassword {
                password = promptForPassword(filename: url.lastPathComponent, incorrect: true)
                if password == nil { return nil }
            }
        }
    }

    private func promptForPassword(filename: String, incorrect: Bool) -> String? {
        let alert = NSAlert()
        alert.messageText = incorrect ? "Incorrect password" : "Password required"
        alert.informativeText = "Enter the password for \(filename)."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        let input = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        input.placeholderString = "PDF password"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }

    private func present(error: Error, title: String) {
        let alert = NSAlert(error: error)
        alert.messageText = title
        alert.runModal()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        NSApplication.shared.mainMenu = mainMenu

        let applicationItem = NSMenuItem()
        mainMenu.addItem(applicationItem)
        let applicationMenu = NSMenu()
        applicationItem.submenu = applicationMenu
        applicationMenu.addItem(withTitle: "About PDFlight", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit PDFlight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let open = fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        open.target = self
        let save = fileMenu.addItem(withTitle: "Save", action: #selector(saveDocument(_:)), keyEquivalent: "s")
        save.target = self
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        let undo = editMenu.addItem(
            withTitle: "Undo Annotation",
            action: #selector(undoAnnotation(_:)),
            keyEquivalent: "z"
        )
        undo.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        let copy = editMenu.addItem(withTitle: "Copy", action: #selector(copySelection(_:)), keyEquivalent: "c")
        copy.target = self
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let find = editMenu.addItem(withTitle: "Find…", action: #selector(focusSearch(_:)), keyEquivalent: "f")
        find.target = self
        addMenuItem(to: editMenu, title: "Find Next", action: #selector(nextSearchResult(_:)), key: "g", modifiers: [.command])
        addMenuItem(to: editMenu, title: "Find Previous", action: #selector(previousSearchResult(_:)), key: "g", modifiers: [.command, .shift])
        editMenu.addItem(.separator())
        addMenuItem(to: editMenu, title: "Highlight Selection", action: #selector(highlightSelection(_:)), key: "e", modifiers: [.command])

        let navigateItem = NSMenuItem()
        mainMenu.addItem(navigateItem)
        let navigateMenu = NSMenu(title: "Navigate")
        navigateItem.submenu = navigateMenu
        addMenuItem(to: navigateMenu, title: "Back", action: #selector(goBack(_:)), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [.command])
        addMenuItem(to: navigateMenu, title: "Previous Page", action: #selector(previousPage(_:)), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [])
        addMenuItem(to: navigateMenu, title: "Next Page", action: #selector(nextPage(_:)), key: String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [])

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        addMenuItem(to: viewMenu, title: "Zoom In", action: #selector(zoomIn(_:)), key: "+", modifiers: [.command])
        addMenuItem(to: viewMenu, title: "Zoom Out", action: #selector(zoomOut(_:)), key: "-", modifiers: [.command])
        addMenuItem(to: viewMenu, title: "Fit Width", action: #selector(fitWidth(_:)), key: "0", modifiers: [.command])
        viewMenu.addItem(.separator())
        addMenuItem(to: viewMenu, title: "Text Note", action: #selector(toggleNote(_:)), key: "n", modifiers: [])
    }

    private func addMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        key: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
    }
}
