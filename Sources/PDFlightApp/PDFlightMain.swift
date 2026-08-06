import AppKit

@main
enum PDFlightMain {
    @MainActor
    static func main() {
        NSWindow.allowsAutomaticWindowTabbing = false
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
