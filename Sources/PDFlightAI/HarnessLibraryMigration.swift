import CryptoKit
import Foundation

/// Prepares a portable copy of Harness-only paper PDFs and records their
/// identities without changing the Harness library or existing user PDFs.
public enum HarnessLibraryMigration {
    public struct Target: Sendable {
        public let paperID: String
        public let documentURL: URL
        public let copied: Bool
    }
    public struct Result: Sendable {
        public let targets: [Target]
        public let unavailablePaperIDs: [String]
        public let mappingsURL: URL
    }
    public enum MigrationError: Error { case conflictingCopy, unsafePaperID }

    public static func prepare(dataDirectory: URL, sourceMappingsURL: URL?, destination: URL) throws -> Result {
        let decoder = JSONDecoder(), fm = FileManager.default
        let index = try decoder.decode(Library.self, from: Data(contentsOf: dataDirectory.appendingPathComponent("index.json")))
        let groups = try decoder.decode(Groups.self, from: Data(contentsOf: dataDirectory.appendingPathComponent("conversations.json")))
        var mappings: [String: String] = [:]
        if let sourceMappingsURL, fm.fileExists(atPath: sourceMappingsURL.path) {
            mappings = try decoder.decode([String: String].self, from: Data(contentsOf: sourceMappingsURL))
        }
        var targets: [Target] = [], unavailable: [String] = []
        for group in groups.groups where !group.conversations.isEmpty {
            guard let paper = index.papers.first(where: { $0.id == group.paperId }) else { unavailable.append(group.paperId); continue }
            let originals = mappings.filter { $0.value == paper.id && fm.fileExists(atPath: $0.key) }.keys.sorted()
            if !originals.isEmpty {
                targets.append(contentsOf: originals.map { Target(paperID: paper.id, documentURL: URL(fileURLWithPath: $0), copied: false) })
                continue
            }
            guard paper.id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { throw MigrationError.unsafePaperID }
            let source = URL(fileURLWithPath: paper.path)
            guard fm.fileExists(atPath: source.path) else { unavailable.append(paper.id); continue }
            let folder = destination.appendingPathComponent("papers", isDirectory: true).appendingPathComponent(paper.id, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let cleanName = URL(fileURLWithPath: paper.title).lastPathComponent
            let name = cleanName.lowercased().hasSuffix(".pdf") ? cleanName : cleanName + ".pdf"
            let copy = folder.appendingPathComponent(name)
            if fm.fileExists(atPath: copy.path) {
                guard try digest(copy) == digest(source) else { throw MigrationError.conflictingCopy }
            } else {
                let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
                defer { try? fm.removeItem(at: temporary) }
                try fm.copyItem(at: source, to: temporary)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                try fm.linkItem(at: temporary, to: copy)
            }
            mappings[copy.standardizedFileURL.resolvingSymlinksInPath().path] = paper.id
            targets.append(Target(paperID: paper.id, documentURL: copy, copied: true))
        }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let mappingsURL = destination.appendingPathComponent("paper-paths.json")
        try JSONEncoder().encode(mappings).write(to: mappingsURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: mappingsURL.path)
        return Result(targets: targets, unavailablePaperIDs: unavailable, mappingsURL: mappingsURL)
    }
    private static func digest(_ url: URL) throws -> SHA256.Digest {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let bytes = try file.read(upToCount: 1_048_576), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize()
    }
    private struct Library: Decodable { let papers: [Paper] }
    private struct Paper: Decodable { let id: String; let title: String; let path: String }
    private struct Groups: Decodable { let groups: [Group] }
    private struct Group: Decodable { let paperId: String; let conversations: [Entry] }
    private struct Entry: Decodable { let sessionId: String }
}
