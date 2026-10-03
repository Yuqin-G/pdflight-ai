import AppKit
import PDFlightAI
import PDFlightCore
import PDFlightMuPDF

enum ReaderCopyDestination: Equatable {
    case textEditor
    case pdfSelection
    case none
}

enum ReaderCopyRouting {
    static func destination(
        editorSelectionLength: Int?,
        hasPDFSelection: Bool
    ) -> ReaderCopyDestination {
        if let editorSelectionLength, editorSelectionLength > 0 {
            return .textEditor
        }
        if hasPDFSelection {
            return .pdfSelection
        }
        return .none
    }
}

enum ReaderSessionRestorePreference {
    static let defaultsKey = "reader.restoreLastSession"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? false
    }

    static func setEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: defaultsKey)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var readers: [ReaderWindowController] = []
    private let readingPositionStore = ReadingPositionStore(fileURL: AppDelegate.readingStateURL)
    private let paperLibraryStore = PaperLibraryStore(fileURL: AppDelegate.paperLibraryURL)
    private let readerSessionStore = ReaderSessionStore(fileURL: AppDelegate.readerSessionURL)
    private let aiChatHistoryStore = AIChatHistoryStore(directoryURL: AppDelegate.aiHistoryDirectoryURL)
    private let aiPromptTemplateStore = AIPromptTemplateStore(fileURL: AppDelegate.aiPromptTemplatesURL)
    private let aiConfigurationStore = AppDelegate.makeAIConfigurationStore()
    private var recentPapers: [PaperLibraryPaper] = []
    private weak var openRecentMenu: NSMenu?
    private var isTerminating = false

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

    private static var aiHistoryDirectoryURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["PDFLIGHT_AI_HISTORY_DIRECTORY"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryName = Bundle.main.bundleIdentifier ?? "dev.pdflight.reader"
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("ai-chats", isDirectory: true)
    }

    private static var aiPromptTemplatesURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryName = Bundle.main.bundleIdentifier ?? "dev.pdflight.reader"
        return applicationSupport
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("prompt-templates.json")
    }

    private static var paperLibraryURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["PDFLIGHT_PAPER_LIBRARY_FILE"],
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
            .appendingPathComponent("paper-library.json")
    }

    private static var readerSessionURL: URL {
        if let overridePath = ProcessInfo.processInfo.environment["PDFLIGHT_READER_SESSION_FILE"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath)
        }
        return paperLibraryURL
            .deletingLastPathComponent()
            .appendingPathComponent("last-session.json")
    }

    private static func makeAIConfigurationStore() -> AIConfigurationStore {
        let environment = ProcessInfo.processInfo.environment
        let defaults: UserDefaults
        if let suiteName = environment["PDFLIGHT_AI_SETTINGS_SUITE"],
           !suiteName.isEmpty,
           let suite = UserDefaults(suiteName: suiteName) {
            defaults = suite
        } else {
            defaults = .standard
        }
        let service = environment["PDFLIGHT_AI_KEYCHAIN_SERVICE"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "dev.pdflight.reader.ai"
        return AIConfigurationStore(
            userDefaults: defaults,
            secretStore: KeychainAISecretStore(service: service)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        IOSMathResourceLocator.install()
        installMainMenu()
        refreshRecentDocuments()

        let arguments = CommandLine.arguments.dropFirst().map(URL.init(fileURLWithPath:))
        let PDFs = arguments.filter { $0.pathExtension.lowercased() == "pdf" }
        if PDFs.isEmpty {
            let restored = restoreLastSessionIfEnabled()
            if !restored {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.readers.isEmpty else { return }
                    self.openDocument(nil)
                }
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
        if !isTerminating { saveCurrentSession() }
        isTerminating = true
        LocalWebBridge.shared.shutdownOwned()
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

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        open(URL(fileURLWithPath: path))
    }

    @objc private func clearRecentDocuments(_ sender: Any?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await paperLibraryStore.clearRecentHistory()
                recentPapers = []
                NotificationCenter.default.post(name: .paperLibraryDidChange, object: nil)
            } catch {
                present(error: error, title: "Could not clear recent files")
            }
        }
    }

    @objc private func toggleRestoreLastSession(_ sender: NSMenuItem) {
        let enabled = !ReaderSessionRestorePreference.isEnabled()
        ReaderSessionRestorePreference.setEnabled(enabled)
        sender.state = enabled ? .on : .off
    }

    @objc private func quitApplication(_ sender: Any?) {
        saveCurrentSession()
        isTerminating = true
        NSApplication.shared.terminate(sender)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            // If an unsaved-annotation prompt cancelled termination, normal session updates resume.
            self?.isTerminating = false
        }
    }

    @objc func saveDocument(_ sender: Any?) {
        keyReader?.saveDocument(sender)
    }

    @objc func undoAnnotation(_ sender: Any?) {
        if let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView {
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
        let editor = NSApplication.shared.keyWindow?.firstResponder as? NSTextView
        switch ReaderCopyRouting.destination(
            editorSelectionLength: editor?.selectedRange().length,
            hasPDFSelection: keyReader?.hasCopyablePDFSelection == true
        ) {
        case .textEditor:
            editor?.copy(sender)
        case .pdfSelection:
            keyReader?.copySelection(sender)
        case .none:
            NSSound.beep()
        }
    }

    @objc func nextSearchResult(_ sender: Any?) {
        keyReader?.nextSearchResult(sender)
    }

    @objc func previousSearchResult(_ sender: Any?) {
        keyReader?.previousSearchResult(sender)
    }

    @objc func toggleAI(_ sender: Any?) {
        keyReader?.toggleAI(sender)
    }

    @objc func configureAI(_ sender: Any?) {
        keyReader?.configureAI(sender)
    }

    private var keyReader: ReaderWindowController? {
        readers.first { $0.window?.isKeyWindow == true }
    }

    private func open(_ url: URL) {
        open(url, selectingAIConversation: nil)
    }

    private func open(_ url: URL, selectingAIConversation conversationID: String?) {
        let normalizedURL = url.standardizedFileURL
        if let existing = readers.first(where: { $0.documentURL.standardizedFileURL == normalizedURL }) {
            recordOpenedDocument(normalizedURL)
            if let conversationID { existing.selectAIConversation(conversationID) }
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        do {
            guard let engine = try openEngine(for: normalizedURL) else { return }
            let tabHost = keyReader?.window ?? readers.last?.window
            let reader = ReaderWindowController(
                url: normalizedURL,
                engine: engine,
                readingPositionStore: readingPositionStore,
                paperLibraryStore: paperLibraryStore,
                aiChatHistoryStore: aiChatHistoryStore,
                aiPromptTemplateStore: aiPromptTemplateStore,
                aiConfigurationStore: aiConfigurationStore
            )
            reader.onClose = { [weak self, weak reader] in
                guard let self, let reader else { return }
                self.readers.removeAll { $0 === reader }
                if !self.isTerminating { self.saveCurrentSession() }
            }
            reader.onActivate = { [weak self] in
                guard let self, !isTerminating else { return }
                saveCurrentSession()
            }
            reader.onNavigateAIHistory = { [weak self] URL, conversationID in
                self?.open(URL, selectingAIConversation: conversationID)
            }
            reader.onOpenPaperFromLibrary = { [weak self] url in
                self?.open(url)
            }
            recordOpenedDocument(normalizedURL)
            if let conversationID { reader.selectAIConversation(conversationID) }
            readers.append(reader)
            saveCurrentSession()
            if let tabHost, let newWindow = reader.window {
                tabHost.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            } else {
                reader.showWindow(nil)
                let storedFullScreen = UserDefaults.standard.object(
                    forKey: ReaderWindowController.windowFullScreenDefaultsKey
                ) as? Bool
                // First launch defaults to full screen; after that the
                // last state the user chose is what gets restored.
                if storedFullScreen ?? true, let window = reader.window {
                    DispatchQueue.main.async {
                        guard !window.styleMask.contains(.fullScreen) else { return }
                        window.toggleFullScreen(nil)
                    }
                }
            }
        } catch {
            present(error: error, title: "Could not open PDF")
        }
    }

    private func recordOpenedDocument(_ url: URL) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await paperLibraryStore.recordOpenedPaper(at: url)
                recentPapers = try await paperLibraryStore.recentPapers(limit: 20)
                NotificationCenter.default.post(name: .paperLibraryDidChange, object: nil)
            } catch {
                // Opening the PDF remains successful even if optional history cannot be saved.
            }
        }
    }

    private func refreshRecentDocuments() {
        Task { [weak self] in
            guard let self else { return }
            recentPapers = (try? await paperLibraryStore.recentPapers(limit: 20)) ?? []
        }
    }

    private func saveCurrentSession() {
        try? readerSessionStore.save(
            documentURLs: readers.map(\.documentURL),
            activeDocumentURL: keyReader?.documentURL
        )
    }

    private func restoreLastSessionIfEnabled() -> Bool {
        guard ReaderSessionRestorePreference.isEnabled() else { return false }
        let state = (try? readerSessionStore.state())
            ?? ReaderSessionState(documentURLs: [], activeDocumentURL: nil)
        let URLs = state.documentURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        guard !URLs.isEmpty else { return false }
        URLs.forEach(open)
        if let activeURL = state.activeDocumentURL,
           let activeReader = readers.first(where: {
               $0.documentURL.standardizedFileURL == activeURL.standardizedFileURL
           }) {
            activeReader.window?.makeKeyAndOrderFront(nil)
            saveCurrentSession()
        }
        return true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openRecentMenu else { return }
        menu.removeAllItems()
        if recentPapers.isEmpty {
            let empty = NSMenuItem(title: "No Recent PDFs", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for paper in recentPapers {
                let item = NSMenuItem(
                    title: paper.displayTitle,
                    action: #selector(openRecentDocument(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = paper.path
                item.toolTip = paper.path
                item.isEnabled = FileManager.default.fileExists(atPath: paper.path)
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let clear = NSMenuItem(
                title: "Clear Menu",
                action: #selector(clearRecentDocuments(_:)),
                keyEquivalent: ""
            )
            clear.target = self
            menu.addItem(clear)
        }
        refreshRecentDocuments()
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
        let aiSettings = applicationMenu.addItem(
            withTitle: "AI Settings…",
            action: #selector(configureAI(_:)),
            keyEquivalent: ","
        )
        aiSettings.target = self
        let restoreSession = applicationMenu.addItem(
            withTitle: "Restore Last Session at Launch",
            action: #selector(toggleRestoreLastSession(_:)),
            keyEquivalent: ""
        )
        restoreSession.target = self
        restoreSession.state = ReaderSessionRestorePreference.isEnabled() ? .on : .off
        applicationMenu.addItem(.separator())
        let quit = applicationMenu.addItem(
            withTitle: "Quit PDFlight",
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quit.target = self

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let open = fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        open.target = self
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: "Open Recent")
        recentMenu.delegate = self
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        openRecentMenu = recentMenu
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
        addMenuItem(to: navigateMenu, title: "Previous Page", action: #selector(previousPage(_:)), key: "", modifiers: [])
        addMenuItem(to: navigateMenu, title: "Next Page", action: #selector(nextPage(_:)), key: "", modifiers: [])

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        addMenuItem(to: viewMenu, title: "Zoom In", action: #selector(zoomIn(_:)), key: "+", modifiers: [.command])
        addMenuItem(to: viewMenu, title: "Zoom Out", action: #selector(zoomOut(_:)), key: "-", modifiers: [.command])
        addMenuItem(to: viewMenu, title: "Fit Width", action: #selector(fitWidth(_:)), key: "0", modifiers: [.command])
        viewMenu.addItem(.separator())
        addMenuItem(to: viewMenu, title: "Ask PDF", action: #selector(toggleAI(_:)), key: "a", modifiers: [.command, .shift])
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
