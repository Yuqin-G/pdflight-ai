import AppKit
import Darwin

@main
enum PDFlightMain {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-check-sidebar-layout")
            || CommandLine.arguments.contains("--self-check-math-rendering") {
            do {
                if CommandLine.arguments.contains("--self-check-sidebar-layout") {
                    try PDFlightAppSelfChecks.sidebarLayout()
                }
                if CommandLine.arguments.contains("--self-check-math-rendering") {
                    try PDFlightAppSelfChecks.mathRendering()
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
