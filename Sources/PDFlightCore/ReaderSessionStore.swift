import Foundation

public struct ReaderSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 2

    public var formatVersion: Int
    public var documentPaths: [String]
    public var activeDocumentPath: String?
    public var groups: [ReaderTabGroupSession]?
    public var activeGroupID: String?
    public var updatedAt: Date

    public init(
        formatVersion: Int = currentFormatVersion,
        documentPaths: [String],
        activeDocumentPath: String? = nil,
        groups: [ReaderTabGroupSession]? = nil,
        activeGroupID: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.documentPaths = documentPaths
        self.activeDocumentPath = activeDocumentPath
        self.groups = groups
        self.activeGroupID = activeGroupID
        self.updatedAt = updatedAt
    }
}

public struct ReaderSessionState: Equatable, Sendable {
    public var documentURLs: [URL]
    public var activeDocumentURL: URL?
    public var groups: [ReaderTabGroupSession]
    public var activeGroupID: String

    public init(documentURLs: [URL], activeDocumentURL: URL?, groups: [ReaderTabGroupSession]? = nil, activeGroupID: String = ReaderTabGroups.defaultID) {
        self.documentURLs = documentURLs
        self.activeDocumentURL = activeDocumentURL
        self.groups = groups ?? [ReaderTabGroupSession(id: ReaderTabGroups.defaultID, documentPaths: documentURLs.map(\.path), activeDocumentPath: activeDocumentURL?.path)]
        self.activeGroupID = activeGroupID
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
            guard (1...ReaderSessionSnapshot.currentFormatVersion).contains(snapshot.formatVersion) else {
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
                activeDocumentURL: activeDocumentURL,
                groups: snapshot.groups?.map(\.normalized),
                activeGroupID: snapshot.activeGroupID ?? ReaderTabGroups.defaultID
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

    public func save(groups: [ReaderTabGroupSession], activeGroupID: String) throws {
        try lock.withLock {
            var seen: Set<String> = []
            var normalized = groups.filter { seen.insert($0.id).inserted }.map(\.normalized)
            let defaultGroup = normalized.first { $0.id == ReaderTabGroups.defaultID }
                ?? ReaderTabGroupSession(id: ReaderTabGroups.defaultID)
            normalized.removeAll { $0.id == ReaderTabGroups.defaultID }
            normalized.insert(defaultGroup, at: 0)
            let selectedID = normalized.contains(where: { $0.id == activeGroupID }) ? activeGroupID : ReaderTabGroups.defaultID
            let selected = normalized.first { $0.id == selectedID }
            let snapshot = ReaderSessionSnapshot(
                documentPaths: normalized.flatMap(\.documentPaths),
                activeDocumentPath: selected?.activeDocumentPath,
                groups: normalized, activeGroupID: selectedID
            )
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
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
