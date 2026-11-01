import AppKit
import Foundation

@main
enum IsolatedApplicationLauncher {
    @MainActor
    static func main() {
        guard CommandLine.arguments.count >= 3 else {
            FileHandle.standardError.write(
                Data("usage: launch-isolated-app <application> <document>...\n".utf8)
            )
            exit(2)
        }

        let applicationURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let documentURLs = CommandLine.arguments.dropFirst(2).map(URL.init(fileURLWithPath:))
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = ProcessInfo.processInfo.environment["PDFLIGHT_TEST_ACTIVATE"] == "1"
        configuration.addsToRecentItems = false
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["-ApplePersistenceIgnoreState", "YES"]
        if let readingStatePath = ProcessInfo.processInfo.environment["PDFLIGHT_READING_STATE_FILE"] {
            configuration.environment["PDFLIGHT_READING_STATE_FILE"] = readingStatePath
        }
        if let harnessSupport = ProcessInfo.processInfo.environment["PDFLIGHT_HARNESS_SUPPORT_DIRECTORY"] {
            configuration.environment["PDFLIGHT_HARNESS_SUPPORT_DIRECTORY"] = harnessSupport
        }
        for key in ["PDFLIGHT_PAPER_LIBRARY_FILE", "PDFLIGHT_READER_SESSION_FILE"] {
            if let value = ProcessInfo.processInfo.environment[key] {
                configuration.environment[key] = value
            }
        }

        NSWorkspace.shared.open(
            Array(documentURLs),
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { application, error in
            if let error {
                FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
                exit(1)
            }
            guard let application else {
                FileHandle.standardError.write(Data("application did not launch\n".utf8))
                exit(1)
            }
            print(application.processIdentifier)
            exit(0)
        }

        RunLoop.main.run()
    }
}
