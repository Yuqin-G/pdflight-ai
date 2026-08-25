import Foundation

public struct ReaderSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var documentPaths: [String]
    public var updatedAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        documentPaths: [String],
        updatedAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.documentPaths = documentPaths
        self.updatedAt = updatedAt
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
        try lock.withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(ReaderSessionSnapshot.self, from: data)
            guard snapshot.formatVersion == ReaderSessionSnapshot.currentFormatVersion else {
                throw ReaderSessionStoreError.unsupportedFormat(snapshot.formatVersion)
            }
            return snapshot.documentPaths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        }
    }

    public func save(documentURLs: [URL]) throws {
        try lock.withLock {
            var seen: Set<String> = []
            let paths = documentURLs.compactMap { URL -> String? in
                let normalized = URL.standardizedFileURL
                guard normalized.pathExtension.lowercased() == "pdf",
                      seen.insert(normalized.path).inserted else { return nil }
                return normalized.path
            }
            let snapshot = ReaderSessionSnapshot(documentPaths: Array(paths.prefix(50)))
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
