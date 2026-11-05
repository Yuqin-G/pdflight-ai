import Foundation

/// Collection identity is independent of its editable name and position in the tree.
public enum ReaderTabGroups {
    public static let defaultID = "default"

    public static func collectionID(_ id: String) -> String { "collection:" + id }

    public static func destination(for url: URL, in library: PaperLibrarySnapshot) -> String {
        guard let paper = library.papers.first(where: {
            $0.fileURL.standardizedFileURL == url.standardizedFileURL
        }), let id = paper.collectionID,
              library.collections.contains(where: { $0.id == id }) else { return defaultID }
        return collectionID(id)
    }

    public static func orderedIDs(in library: PaperLibrarySnapshot) -> [String] {
        var result = [defaultID]
        func appendChildren(of parent: String?) {
            for collection in library.collections.filter({ $0.parentID == parent }).sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    || ($0.name == $1.name && $0.id < $1.id)
            }) where !result.contains(collectionID(collection.id)) {
                result.append(collectionID(collection.id))
                appendChildren(of: collection.id)
            }
        }
        appendChildren(of: nil)
        return result
    }
}

public struct ReaderTabGroupSession: Codable, Equatable, Sendable {
    public var id: String
    public var documentPaths: [String]
    public var activeDocumentPath: String?

    public init(id: String, documentPaths: [String] = [], activeDocumentPath: String? = nil) {
        self.id = id
        self.documentPaths = documentPaths
        self.activeDocumentPath = activeDocumentPath
    }

    public var normalized: Self {
        var seen: Set<String> = []
        let paths = documentPaths.compactMap { path -> String? in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.pathExtension.lowercased() == "pdf", seen.insert(url.path).inserted else { return nil }
            return url.path
        }
        let active = activeDocumentPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return Self(id: id, documentPaths: paths,
                    activeDocumentPath: active.flatMap { paths.contains($0) ? $0 : nil })
    }
}
