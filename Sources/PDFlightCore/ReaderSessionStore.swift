import Foundation

public struct ReaderSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var documentPaths: [String]
    public var activeDocumentPath: String?
    public var updatedAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        documentPaths: [String],
        activeDocumentPath: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.documentPaths = documentPaths
        self.activeDocumentPath = activeDocumentPath
        self.updatedAt = updatedAt
    }
}

public struct ReaderSessionState: Equatable, Sendable {
    public var documentURLs: [URL]
    public var activeDocumentURL: URL?

    public init(documentURLs: [URL], activeDocumentURL: URL?) {
        self.documentURLs = documentURLs
        self.activeDocumentURL = activeDocumentURL
    }
}

public enum ReaderSessionStoreError: Error, LocalizedError, Equatable {
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(version):
            "Unsupported reader-session format version \(version)."
        }
    }
}

public final class ReaderSessionStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func documentURLs() throws -> [URL] {
        try state().documentURLs
    }

    public func state() throws -> ReaderSessionState {
        try lock.withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return ReaderSessionState(documentURLs: [], activeDocumentURL: nil)
            }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ReaderSessionSnapshot.self, from: data)
            guard snapshot.formatVersion == ReaderSessionSnapshot.currentFormatVersion else {
                throw ReaderSessionStoreError.unsupportedFormat(snapshot.formatVersion)
            }
            let documentURLs = snapshot.documentPaths.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
            let activeDocumentURL = snapshot.activeDocumentPath.map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
            return ReaderSessionState(
                documentURLs: documentURLs,
                activeDocumentURL: activeDocumentURL
            )
        }
    }

    public func save(documentURLs: [URL], activeDocumentURL: URL? = nil) throws {
        try lock.withLock {
            var seen: Set<String> = []
            let paths = documentURLs.compactMap { URL -> String? in
                let normalized = URL.standardizedFileURL
                guard normalized.pathExtension.lowercased() == "pdf",
                      seen.insert(normalized.path).inserted else { return nil }
                return normalized.path
            }
            let storedPaths = Array(paths.prefix(50))
            let requestedActivePath = activeDocumentURL?.standardizedFileURL.path
            let activeDocumentPath = requestedActivePath.flatMap { path in
                storedPaths.contains(path) ? path : nil
            }
            let snapshot = ReaderSessionSnapshot(
                documentPaths: storedPaths,
                activeDocumentPath: activeDocumentPath
            )
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        }
    }

    public func clear() throws {
        try save(documentURLs: [])
    }
}
