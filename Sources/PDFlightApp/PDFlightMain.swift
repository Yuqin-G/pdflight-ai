import AppKit
import Darwin
import PDFlightAI

@main
enum PDFlightMain {
    @MainActor
    static func main() {
        let supportedSelfChecks: Set<String> = [
            "--self-check-chat-renderer",
            "--self-check-group-tabs",
            "--self-check-sidebar-layout",
            "--self-check-math-rendering",
            "--self-check-native-paper-chat"
        ]
        if CommandLine.arguments.dropFirst().contains(where: {
            $0.hasPrefix("--self-check") && !supportedSelfChecks.contains($0)
        }) {
            fputs("Unknown --self-check option. Refusing to start a reading session.\n", stderr)
            exit(EX_USAGE)
        }
        if CommandLine.arguments.contains("--self-check-chat-renderer") {
            do {
                try NativePaperChatSidebar.rendererResourceSelfCheck()
                print("PASS: chat renderer resource resolution and visible native fallback")
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        if CommandLine.arguments.contains("--paper-import-capabilities") {
            let value: [String: Any] = ["paperImportProtocol": 1, "queueDirectory": PaperImportQueue.defaultDirectory.path]
            if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
               let output = String(data: data, encoding: .utf8) { print(output) }
            return
        }
        if CommandLine.arguments.contains("--self-check-group-tabs") {
            let application = NSApplication.shared
            application.setActivationPolicy(.regular)
            Task { @MainActor in
                do {
                    try await AppDelegate.groupTabsSelfCheck()
                    exit(EXIT_SUCCESS)
                } catch {
                    fputs("FAIL: \(error)\n", stderr)
                    exit(EXIT_FAILURE)
                }
            }
            application.run()
            return
        }
        if CommandLine.arguments.contains("--self-check-sidebar-layout")
            || CommandLine.arguments.contains("--self-check-math-rendering")
            || CommandLine.arguments.contains("--self-check-native-paper-chat") {
            do {
                if CommandLine.arguments.contains("--self-check-sidebar-layout") {
                    try PDFlightAppSelfChecks.sidebarLayout()
                }
                if CommandLine.arguments.contains("--self-check-math-rendering") {
                    try PDFlightAppSelfChecks.mathRendering()
                }
                if CommandLine.arguments.contains("--self-check-native-paper-chat") {
                    _ = NSApplication.shared
                    try NativePaperChatSidebar.selfCheck()
                    print("PASS: native paper chat preserves quoted drafts and pasted image attachments")
                }
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
            return
        }
        NSWindow.allowsAutomaticWindowTabbing = false
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
