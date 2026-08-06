import Foundation

public struct ReadingPosition: Codable, Sendable, Equatable {
    public let bookmark: DocumentViewportBookmark
    public let zoom: Double
    public let updatedAt: Date

    public init(bookmark: DocumentViewportBookmark, zoom: Double, updatedAt: Date = Date()) {
        self.bookmark = bookmark
        self.zoom = zoom
        self.updatedAt = updatedAt
    }
}

@MainActor
public final class ReadingPositionStore {
    private struct Archive: Codable {
        var version = 1
        var documents: [String: ReadingPosition] = [:]
    }

    private let fileURL: URL
    private let maximumDocumentCount: Int
    private var archive = Archive()
    private var hasLoaded = false

    public init(fileURL: URL, maximumDocumentCount: Int = 1_000) {
        self.fileURL = fileURL
        self.maximumDocumentCount = max(1, maximumDocumentCount)
    }

    public func position(for documentURL: URL) throws -> ReadingPosition? {
        try loadIfNeeded()
        return archive.documents[key(for: documentURL)]
    }

    public func save(_ position: ReadingPosition, for documentURL: URL) throws {
        try loadIfNeeded()
        archive.documents[key(for: documentURL)] = position
        pruneOldDocumentsIfNeeded()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(archive).write(to: fileURL, options: .atomic)
    }

    private func loadIfNeeded() throws {
        guard !hasLoaded else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            hasLoaded = true
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        archive = try decoder.decode(Archive.self, from: Data(contentsOf: fileURL))
        hasLoaded = true
    }

    private func key(for documentURL: URL) -> String {
        documentURL.standardizedFileURL.path
    }

    private func pruneOldDocumentsIfNeeded() {
        let overflow = archive.documents.count - maximumDocumentCount
        guard overflow > 0 else { return }
        let oldestKeys = archive.documents
            .sorted {
                if $0.value.updatedAt == $1.value.updatedAt {
                    return $0.key < $1.key
                }
                return $0.value.updatedAt < $1.value.updatedAt
            }
            .prefix(overflow)
            .map(\.key)
        oldestKeys.forEach { archive.documents.removeValue(forKey: $0) }
    }
}
