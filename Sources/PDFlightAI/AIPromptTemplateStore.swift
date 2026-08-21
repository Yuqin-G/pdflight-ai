import Foundation

public actor AIPromptTemplateStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    public nonisolated var storageFileURL: URL { fileURL }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder
    }

    public func templates() throws -> [AIPromptTemplate] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AIPromptTemplate.defaults
        }
        let data = try Data(contentsOf: fileURL)
        return normalized(try decoder.decode([AIPromptTemplate].self, from: data))
    }

    public func save(_ templates: [AIPromptTemplate]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(normalized(templates)).write(to: fileURL, options: .atomic)
    }

    private func normalized(_ source: [AIPromptTemplate]) -> [AIPromptTemplate] {
        var seen: Set<String> = []
        var custom: [AIPromptTemplate] = []
        var builtIns: [String: AIPromptTemplate] = [:]

        for var template in source {
            template.id = template.id.trimmingCharacters(in: .whitespacesAndNewlines)
            template.name = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !template.id.isEmpty, !template.name.isEmpty, seen.insert(template.id).inserted else {
                continue
            }
            if template.id == AIPromptPreset.none.rawValue
                || template.id == AIPromptPreset.reading.rawValue {
                builtIns[template.id] = template
            } else {
                custom.append(template)
            }
        }

        let defaults = AIPromptTemplate.defaults
        let required = defaults.map { template in
            builtIns[template.id] ?? template
        }
        return required + custom
    }
}
