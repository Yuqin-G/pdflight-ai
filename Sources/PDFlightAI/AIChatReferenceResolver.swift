import Foundation

public enum AIChatReferenceResolver {
    public struct Resolved: Sendable {
        public let context: String
        public let pdfURLs: [URL]
    }

    public enum ReferenceError: LocalizedError {
        case unavailable(String)
        public var errorDescription: String? {
            switch self { case .unavailable(let reason): return reason }
        }
    }

    /// Resolve only references explicitly selected in this draft, with bounded
    /// text. Reference material is user context, not a system instruction.
    public static func resolve(_ references: [AIChatDraftReference], draftText: String, workspaceURL: URL,
                               conversations: [AIConversation], allowOutsideWorkspace: Bool) throws -> Resolved {
        var sections: [String] = []
        var pdfURLs: [URL] = []
        guard references.count <= 8 else { throw ReferenceError.unavailable("一次最多引用 8 项资料。") }
        let root = workspaceURL.resolvingSymlinksInPath().standardizedFileURL
        let text = draftText as NSString
        var previousEnd = 0
        for reference in references {
            guard reference.offset >= previousEnd, reference.length > 0, reference.offset <= text.length,
                  reference.length <= text.length - reference.offset,
                  text.substring(with: NSRange(location: reference.offset, length: reference.length)) == reference.clipboardText else {
                throw ReferenceError.unavailable("引用已发生变化，请重新选择：\(reference.label)")
            }
            previousEnd = reference.offset + reference.length
            guard reference.source == "reference", reference.invalid != true else { throw ReferenceError.unavailable("引用不可用：\(reference.label)") }
            switch reference.appearance {
            case "session":
                guard let sessionID = sessionID(from: reference.ref), let session = conversations.first(where: { $0.id == sessionID }) else {
                    throw ReferenceError.unavailable("找不到引用的对话：\(reference.label)")
                }
                let turns = session.messages.filter { $0.role == .user || $0.role == .assistant }.suffix(24)
                    .map { "\($0.role.rawValue): \($0.content)" }.joined(separator: "\n\n")
                sections.append("引用的对话 \(reference.label)：\n" + (turns.count > 24_000 ? "[仅保留较新的对话内容]\n" : "") + String(turns.suffix(24_000)))
            case "file":
                guard let path = filePath(from: reference.ref) else { throw ReferenceError.unavailable("无法识别文件引用：\(reference.label)") }
                let file = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)).resolvingSymlinksInPath().standardizedFileURL
                guard allowOutsideWorkspace || file.path == root.path || file.path.hasPrefix(root.path + "/") else {
                    throw ReferenceError.unavailable("引用的文件位于当前工作区之外：\(reference.label)")
                }
                guard let properties = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), properties.isRegularFile == true else {
                    throw ReferenceError.unavailable("找不到引用的文件：\(reference.label)")
                }
                if file.pathExtension.lowercased() == "pdf" {
                    if !pdfURLs.contains(file) { pdfURLs.append(file) }
                } else {
                    guard let size = properties.fileSize, size <= 2 * 1_024 * 1_024,
                          let data = try? Data(contentsOf: file), let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
                        throw ReferenceError.unavailable("引用文件不是可读取的 UTF-8 文本，或超过 2 MB：\(reference.label)")
                    }
                    let truncated = text.count > 24_000
                    sections.append("引用的文件 \(reference.label)：\n" + String(text.prefix(24_000)) + (truncated ? "\n[文件内容已截断]" : ""))
                }
            default:
                throw ReferenceError.unavailable("暂不支持这个引用：\(reference.label)")
            }
        }
        return Resolved(context: sections.joined(separator: "\n\n"), pdfURLs: pdfURLs)
    }

    private static func filePath(from ref: String) -> String? {
        guard ref.hasPrefix("@") else { return nil }
        let value = String(ref.dropFirst())
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 { return String(value.dropFirst().dropLast()) }
        return value.isEmpty ? nil : value
    }

    private static func sessionID(from ref: String) -> String? {
        guard let marker = ref.range(of: "(dsh-session:"), ref.hasSuffix(")") else { return nil }
        var payload = String(ref[marker.upperBound..<ref.index(before: ref.endIndex)])
        payload = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }
}
