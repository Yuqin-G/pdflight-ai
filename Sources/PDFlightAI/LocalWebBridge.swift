import Foundation

/// Manages the bundled `uwa-lite` local web bridge that serves
/// OpenAI-compatible endpoints backed by a controlled browser session.
///
/// The bridge is started lazily: when an AI request targets a loopback
/// base URL whose port answers nothing, PDFlight resolves the service
/// directory (bundled resource, repo checkout, or `PDFLIGHT_UWA_HOME`),
/// spawns `main.py` on the requested port, and waits for `/health`.
/// A bridge already listening on the port is left alone and never killed.
public final class LocalWebBridge: @unchecked Sendable {
    public static let shared = LocalWebBridge()

    private let lock = NSLock()
    private var spawnedProcess: Process?
    private var readinessTask: Task<Bool, Never>?

    public init() {}

    public struct Endpoint: Sendable, Equatable {
        public var scheme: String
        public var host: String
        public var port: Int

        public init(scheme: String, host: String, port: Int) {
            self.scheme = scheme
            self.host = host
            self.port = port
        }

        public var healthURL: URL? {
            URL(string: "\(scheme)://\(host):\(port)/health")
        }
    }

    /// Returns the loopback endpoint for a base URL PDFlight could bridge,
    /// or nil when the URL is remote or malformed.
    public func bridgeEndpoint(from baseURL: String) -> Endpoint? {
        guard let components = URLComponents(
            string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        ),
            let host = components.host?.lowercased(),
            ["localhost", "127.0.0.1", "::1"].contains(host)
        else { return nil }
        let scheme = components.scheme?.lowercased() ?? "http"
        guard scheme == "http" || scheme == "https" else { return nil }
        return Endpoint(
            scheme: scheme,
            host: host,
            port: components.port ?? (scheme == "https" ? 443 : 80)
        )
    }

    /// Resolves the web service required by a model route. The Magpie
    /// forwarding endpoint can be healthy while its uwa-lite dependency is down.
    /// Other local APIs are not uwa-lite and must not be started by this helper.
    public func bridgeEndpoint(for configuration: AIProviderConfiguration) -> Endpoint? {
        guard AIConversationRouting.usesWebGateway(configuration),
              let endpoint = bridgeEndpoint(from: configuration.baseURL) else { return nil }
        if endpoint.port == 3425 {
            return Endpoint(scheme: "http", host: "127.0.0.1", port: 8199)
        }
        return endpoint
    }

    public func ensureReady(for configuration: AIProviderConfiguration) async -> Bool {
        guard let endpoint = bridgeEndpoint(for: configuration) else { return true }
        guard let url = endpoint.healthURL else { return false }
        return await ensureReady(for: url.absoluteString)
    }

    /// Ensures a bridge answers on the endpoint of `baseURL`. Returns true
    /// when the URL is remote (nothing to do) or the service is healthy.
    public func ensureReady(for baseURL: String) async -> Bool {
        guard let endpoint = bridgeEndpoint(from: baseURL) else { return true }
        if await probe(endpoint) { return true }
        // A caller may configure a different local OpenAI-compatible server.
        // It need not implement uwa-lite's /health route; an HTTP response
        // still proves that its port is occupied and must not be taken over.
        if await responds(endpoint) { return true }
        let task: Task<Bool, Never> = lock.withLock {
            if let readinessTask { return readinessTask }
            let task = Task { await self.spawnAndWait(for: endpoint) }
            readinessTask = task
            return task
        }
        return await task.value
    }

    /// Whether the endpoint answers `/health` quickly.
    public func probe(_ endpoint: Endpoint) async -> Bool {
        guard let url = endpoint.healthURL else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse).map {
                (200..<300).contains($0.statusCode)
            } ?? false
        } catch {
            return false
        }
    }

    public func responds(_ endpoint: Endpoint) async -> Bool {
        guard let url = endpoint.healthURL else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    /// Terminates the bridge process, but only when this app spawned it.
    public func shutdownOwned() {
        lock.withLock {
            guard let process = spawnedProcess else { return }
            spawnedProcess = nil
            readinessTask = nil
            if process.isRunning {
                process.terminate()
            }
        }
    }

    public var logFileURL: URL {
        Self.supportDirectory()
            .appendingPathComponent("uwa-lite.log", isDirectory: false)
    }

    // MARK: - Spawning

    private func spawnAndWait(for endpoint: Endpoint) async -> Bool {
        defer {
            lock.withLock { readinessTask = nil }
        }
        guard let home = serviceHome(),
              let python = pythonExecutable(under: home) else {
            return false
        }
        do {
            let process = Process()
            process.executableURL = python
            process.arguments = [home.appendingPathComponent("main.py").path]
            process.currentDirectoryURL = home
            var environment = ProcessInfo.processInfo.environment
            environment["APP_PORT"] = String(endpoint.port)
            environment["APP_HOST"] = "127.0.0.1"
            environment["PYTHONDONTWRITEBYTECODE"] = "1"
            if python.path.contains("/runtime/bin/"),
               let sitePackages = sitePackagesDirectory(under: home) {
                let existing = environment["PYTHONPATH"]
                environment["PYTHONPATH"] = [sitePackages.path, existing]
                    .compactMap { $0 }.joined(separator: ":")
            }
            process.environment = environment

            let logURL = logFileURL
            try FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let logHandle = try FileHandle(forWritingTo: logURL)
            logHandle.seekToEndOfFile()
            process.standardOutput = logHandle
            process.standardError = logHandle

            try process.run()
            lock.withLock { spawnedProcess = process }
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if await probe(endpoint) { return true }
            if let process = lock.withLock({ self.spawnedProcess }),
               !process.isRunning {
                return false
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        return false
    }

    private func serviceHome() -> URL? {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["PDFLIGHT_UWA_HOME"],
           !override.isEmpty,
           fileManager.fileExists(
            atPath: (override as NSString).appendingPathComponent("main.py")
           ) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let supportHome = Self.supportDirectory()
            .appendingPathComponent("uwa-lite", isDirectory: true)
        if fileManager.fileExists(
            atPath: supportHome.appendingPathComponent("main.py").path
        ) {
            return supportHome
        }
        if let bundled = Bundle.main.resourceURL?
            .appendingPathComponent("uwa-lite", isDirectory: true),
           fileManager.fileExists(
            atPath: bundled.appendingPathComponent("main.py").path
           ) {
            // The bundle is read-only; run the service from a writable copy.
            // Remove a stale directory or broken symlink before copying.
            try? fileManager.removeItem(at: supportHome)
            try? fileManager.copyItem(at: bundled, to: supportHome)
            if fileManager.fileExists(
                atPath: supportHome.appendingPathComponent("main.py").path
            ) {
                return supportHome
            }
            return bundled
        }
        var probe = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while true {
            let candidate = probe.appendingPathComponent("Services/uwa-lite", isDirectory: true)
            if fileManager.fileExists(
                atPath: candidate.appendingPathComponent("main.py").path
            ) {
                return candidate
            }
            let parent = probe.deletingLastPathComponent()
            guard parent.path != probe.path else { return nil }
            probe = parent
        }
    }

    private func pythonExecutable(under home: URL) -> URL? {
        let fileManager = FileManager.default
        for relative in ["runtime/bin/python3", ".venv/bin/python"] {
            let candidate = home.appendingPathComponent(relative, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        for name in ["python3.11", "python3.12", "python3.10", "python3"] {
            if let found = searchPATH(for: name) { return found }
        }
        return nil
    }

    private func sitePackagesDirectory(under home: URL) -> URL? {
        let lib = home.appendingPathComponent(".venv/lib", isDirectory: true)
        guard let versions = try? FileManager.default.contentsOfDirectory(
            atPath: lib.path
        ) else { return nil }
        for version in versions where version.hasPrefix("python") {
            let sitePackages = lib.appendingPathComponent(
                "\(version)/site-packages", isDirectory: true
            )
            if FileManager.default.fileExists(atPath: sitePackages.path) {
                return sitePackages
            }
        }
        return nil
    }

    private func searchPATH(for name: String) -> URL? {
        for directory in (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func supportDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        let directoryName = Bundle.main.bundleIdentifier ?? "dev.pdflight.reader"
        return applicationSupport.appendingPathComponent(directoryName, isDirectory: true)
    }
}
