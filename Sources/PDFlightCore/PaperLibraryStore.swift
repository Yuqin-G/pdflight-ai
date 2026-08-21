import Foundation

public struct PaperLibraryCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var parentID: String?
    public let createdAt: Date

    public init(id: String = UUID().uuidString, name: String, parentID: String?, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}

public struct PaperLibraryPaper: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var path: String
    public var collectionID: String?
    public var displayAlias: String?
    public let addedAt: Date
    public var lastOpenedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        path: String,
        collectionID: String?,
        displayAlias: String? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.collectionID = collectionID
        self.displayAlias = displayAlias
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
    }

    public var fileURL: URL { URL(fileURLWithPath: path) }

    public var displayTitle: String {
        let custom = displayAlias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? Self.automaticDisplayAlias(for: title) : custom
    }

    public static func automaticDisplayAlias(for fileName: String) -> String {
        let parts = fileName.components(separatedBy: " - ")
        guard parts.count >= 3 else { return fileName }
        let author = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let year = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let title = parts.dropFirst(2).joined(separator: " - ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let yearPrefix = year.prefix(4)
        let suffix = year.dropFirst(4)
        let validYear = yearPrefix.count == 4
            && yearPrefix.allSatisfy(\.isNumber)
            && (suffix.isEmpty || (suffix.count == 1 && suffix.allSatisfy(\.isLetter)))
        guard !author.isEmpty, validYear, !title.isEmpty else { return fileName }
        return title
    }
}

public struct PaperLibrarySnapshot: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var collections: [PaperLibraryCollection]
    public var papers: [PaperLibraryPaper]

    public init(
        formatVersion: Int = 1,
        collections: [PaperLibraryCollection] = [],
        papers: [PaperLibraryPaper] = []
    ) {
        self.formatVersion = formatVersion
        self.collections = collections
        self.papers = papers
    }
}

public enum PaperLibraryError: Error, LocalizedError, Equatable {
    case invalidName
    case collectionNotFound
    case paperNotFound
    case collectionCycle
    case unsupportedFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidName: "A collection name cannot be empty."
        case .collectionNotFound: "The selected collection no longer exists."
        case .paperNotFound: "The selected paper no longer exists in the library."
        case .collectionCycle: "A collection cannot be moved inside itself or one of its children."
        case let .unsupportedFormat(version): "Unsupported paper library format version \(version)."
        }
    }
}

public actor PaperLibraryStore {
    private let fileURL: URL
    private var cachedSnapshot: PaperLibrarySnapshot?

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func snapshot() throws -> PaperLibrarySnapshot {
        try loadIfNeeded()
    }

    @discardableResult
    public func createCollection(name: String, parentID: String?) throws -> PaperLibraryCollection {
        var state = try loadIfNeeded()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw PaperLibraryError.invalidName }
        if let parentID, !state.collections.contains(where: { $0.id == parentID }) {
            throw PaperLibraryError.collectionNotFound
        }
        let collection = PaperLibraryCollection(name: cleanName, parentID: parentID)
        state.collections.append(collection)
        try save(state)
        return collection
    }

    public func renameCollection(_ id: String, to name: String) throws {
        var state = try loadIfNeeded()
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw PaperLibraryError.invalidName }
        guard let index = state.collections.firstIndex(where: { $0.id == id }) else {
            throw PaperLibraryError.collectionNotFound
        }
        state.collections[index].name = cleanName
        try save(state)
    }

    public func moveCollection(_ id: String, to parentID: String?) throws {
        var state = try loadIfNeeded()
        guard let index = state.collections.firstIndex(where: { $0.id == id }) else {
            throw PaperLibraryError.collectionNotFound
        }
        if let parentID {
            guard state.collections.contains(where: { $0.id == parentID }) else {
                throw PaperLibraryError.collectionNotFound
            }
            let descendants = descendantIDs(of: id, collections: state.collections)
            guard parentID != id, !descendants.contains(parentID) else {
                throw PaperLibraryError.collectionCycle
            }
        }
        state.collections[index].parentID = parentID
        try save(state)
    }

    public func deleteCollection(_ id: String) throws {
        var state = try loadIfNeeded()
        guard state.collections.contains(where: { $0.id == id }) else {
            throw PaperLibraryError.collectionNotFound
        }
        var removedIDs = descendantIDs(of: id, collections: state.collections)
        removedIDs.insert(id)
        state.collections.removeAll { removedIDs.contains($0.id) }
        for index in state.papers.indices where state.papers[index].collectionID.map(removedIDs.contains) == true {
            state.papers[index].collectionID = nil
        }
        try save(state)
    }

    @discardableResult
    public func addPaper(at url: URL, to collectionID: String?) throws -> PaperLibraryPaper {
        var state = try loadIfNeeded()
        if let collectionID, !state.collections.contains(where: { $0.id == collectionID }) {
            throw PaperLibraryError.collectionNotFound
        }
        let normalizedURL = url.standardizedFileURL
        let path = normalizedURL.path
        if let index = state.papers.firstIndex(where: { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }) {
            state.papers[index].title = normalizedURL.deletingPathExtension().lastPathComponent
            state.papers[index].lastOpenedAt = Date()
            if let collectionID { state.papers[index].collectionID = collectionID }
            let paper = state.papers[index]
            try save(state)
            return paper
        }
        let paper = PaperLibraryPaper(
            title: normalizedURL.deletingPathExtension().lastPathComponent,
            path: path,
            collectionID: collectionID
        )
        state.papers.append(paper)
        try save(state)
        return paper
    }

    public func movePaper(_ id: String, to collectionID: String?) throws {
        var state = try loadIfNeeded()
        if let collectionID, !state.collections.contains(where: { $0.id == collectionID }) {
            throw PaperLibraryError.collectionNotFound
        }
        guard let index = state.papers.firstIndex(where: { $0.id == id }) else {
            throw PaperLibraryError.paperNotFound
        }
        state.papers[index].collectionID = collectionID
        try save(state)
    }

    public func setPaperDisplayAlias(_ id: String, to alias: String?) throws {
        var state = try loadIfNeeded()
        guard let index = state.papers.firstIndex(where: { $0.id == id }) else {
            throw PaperLibraryError.paperNotFound
        }
        let cleanAlias = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        state.papers[index].displayAlias = cleanAlias?.isEmpty == false ? cleanAlias : nil
        try save(state)
    }

    public func removePaper(_ id: String) throws {
        var state = try loadIfNeeded()
        guard state.papers.contains(where: { $0.id == id }) else {
            throw PaperLibraryError.paperNotFound
        }
        state.papers.removeAll { $0.id == id }
        try save(state)
    }

    private func loadIfNeeded() throws -> PaperLibrarySnapshot {
        if let cachedSnapshot { return cachedSnapshot }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let empty = PaperLibrarySnapshot()
            cachedSnapshot = empty
            return empty
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PaperLibrarySnapshot.self, from: data)
        guard decoded.formatVersion == 1 else {
            throw PaperLibraryError.unsupportedFormat(decoded.formatVersion)
        }
        cachedSnapshot = decoded
        return decoded
    }

    private func save(_ snapshot: PaperLibrarySnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        cachedSnapshot = snapshot
    }

    private func descendantIDs(
        of id: String,
        collections: [PaperLibraryCollection]
    ) -> Set<String> {
        var descendants: Set<String> = []
        var frontier = [id]
        while let parent = frontier.popLast() {
            let children = collections.filter { $0.parentID == parent }.map(\.id)
            for child in children where descendants.insert(child).inserted {
                frontier.append(child)
            }
        }
        return descendants
    }
}
