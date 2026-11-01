import Foundation

public struct AIPaperToolContext: Sendable {
    public let documentURL: URL
    public let workspaceURL: URL
    public let pageCount: Int
    public let readPage: @Sendable (Int) async throws -> String

    public init(documentURL: URL, workspaceURL: URL, pageCount: Int, readPage: @escaping @Sendable (Int) async throws -> String) {
        self.documentURL = documentURL; self.workspaceURL = workspaceURL; self.pageCount = pageCount; self.readPage = readPage
    }
}

public struct AIChatToolResult: Sendable, Equatable {
    public let content: String
    public let isError: Bool
    public init(content: String, isError: Bool = false) { self.content = content; self.isError = isError }
}

/// Native reading tools operate on the open paper and its workspace. The
/// caller owns the document engine; no Harness process is needed.
public enum AIPaperToolRuntime {
    private struct Arguments: Decodable {
        var action: String?
        var page: Int?
        var file_path: String?
        var offset: Int?
        var limit: Int?
        var pattern: String?
        var path: String?
    }

    private static func schema(_ properties: [String: AIJSONValue], required: [String]) -> AIJSONValue {
        .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(AIJSONValue.string))])
    }
    private static func string(_ description: String) -> AIJSONValue { .object(["type": .string("string"), "description": .string(description)]) }
    private static func integer(_ description: String) -> AIJSONValue { .object(["type": .string("integer"), "description": .string(description)]) }

    public static let definitions: [AIChatToolDefinition] = [
        .init(name: "pdf_reading", description: "Read or search the currently open PDF. Page numbers are one-based; cite the page number in answers.", parameters: schema([
            "action": .object(["type": .string("string"), "enum": .array([.string("read_page"), .string("search")])]),
            "page": integer("One-based page number for read_page."), "pattern": string("Literal text to search for in the PDF.")
        ], required: ["action"])),
        .init(name: "read", description: "Read a UTF-8 text file in the paper workspace with line numbers.", parameters: schema([
            "file_path": string("Path to the text file, relative to the paper workspace or absolute within it."),
            "offset": integer("One-based first line."), "limit": integer("Maximum number of lines.")
        ], required: ["file_path"])),
        .init(name: "grep", description: "Search UTF-8 text files in the paper workspace using a regular expression.", parameters: schema([
            "pattern": string("Regular expression to search for."), "path": string("A file or directory within the paper workspace.")
        ], required: ["pattern"]))
    ]

    public static func execute(_ call: AIChatToolCall, context: AIPaperToolContext) async -> AIChatToolResult {
        do {
            try Task.checkCancellation()
            let args = try JSONDecoder().decode(Arguments.self, from: Data(call.arguments.utf8))
            let output: String
            switch call.name {
            case "pdf_reading": output = try await pdf(args, context: context)
            case "read": output = try read(args, context: context)
            case "grep": output = try grep(args, context: context)
            default: throw ToolError.message("未知工具：\(call.name)")
            }
            return AIChatToolResult(content: output)
        } catch is CancellationError {
            return AIChatToolResult(content: "工具调用已取消。", isError: true)
        } catch {
            return AIChatToolResult(content: error.localizedDescription, isError: true)
        }
    }

    private enum ToolError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private static func pdf(_ args: Arguments, context: AIPaperToolContext) async throws -> String {
        switch args.action {
        case "read_page":
            guard let page = args.page, page >= 1, page <= context.pageCount else { throw ToolError.message("页码必须在 1 到 \(context.pageCount) 之间。") }
            let text = try await context.readPage(page - 1)
            return "PDF 第 \(page) 页：\n" + String(text.prefix(24_000))
        case "search":
            guard let pattern = args.pattern, !pattern.isEmpty, pattern.count <= 500 else { throw ToolError.message("请提供不超过 500 字的搜索内容。") }
            var matches: [String] = []
            for page in 0..<context.pageCount {
                try Task.checkCancellation()
                let text = try await context.readPage(page)
                if let range = text.range(of: pattern, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let start = text.index(range.lowerBound, offsetBy: -120, limitedBy: text.startIndex) ?? text.startIndex
                    let end = text.index(range.upperBound, offsetBy: 120, limitedBy: text.endIndex) ?? text.endIndex
                    matches.append("第 \(page + 1) 页：" + String(text[start..<end]))
                    if matches.count == 30 { break }
                }
            }
            return matches.isEmpty ? "未找到匹配的 PDF 文本。" : matches.joined(separator: "\n\n")
        default: throw ToolError.message("pdf_reading 支持 read_page 和 search。")
        }
    }

    private static func resolved(_ path: String, root: URL) throws -> URL {
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = (path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path))
            .standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/") else {
            throw ToolError.message("文件不在当前论文的工作目录内。")
        }
        return candidate
    }

    private static func read(_ args: Arguments, context: AIPaperToolContext) throws -> String {
        guard let path = args.file_path, !path.isEmpty else { throw ToolError.message("缺少 file_path。") }
        let url = try resolved(path, root: context.workspaceURL)
        guard url.pathExtension.lowercased() != "pdf" else { throw ToolError.message("请使用 pdf_reading 读取 PDF。") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 4 * 1_024 * 1_024 else { throw ToolError.message("只能读取不超过 4 MB 的普通文本文件。") }
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let start = max(1, args.offset ?? 1); let limit = min(2_000, max(1, args.limit ?? 500))
        guard start <= lines.count else { return "文件只有 \(lines.count) 行。" }
        return lines.dropFirst(start - 1).prefix(limit).enumerated().map { "\(start + $0.offset): \($0.element)" }.joined(separator: "\n").prefixString(40_000)
    }

    private static func grep(_ args: Arguments, context: AIPaperToolContext) throws -> String {
        guard let pattern = args.pattern, !pattern.isEmpty, pattern.count <= 500 else { throw ToolError.message("缺少有效的搜索表达式。") }
        let regex = try NSRegularExpression(pattern: pattern)
        let root = try resolved(args.path ?? ".", root: context.workspaceURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { throw ToolError.message("搜索路径不存在。") }
        var files: [URL] = []
        if isDirectory.boolValue {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while files.count < 500, let url = enumerator?.nextObject() as? URL { files.append(url) }
        } else { files.append(root) }
        var matches: [String] = []
        for file in files {
            try Task.checkCancellation()
            guard let safe = try? resolved(file.path, root: context.workspaceURL) else { continue }
            guard let values = try? safe.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true,
                  (values.fileSize ?? 0) <= 1_024 * 1_024, let text = try? String(contentsOf: safe, encoding: .utf8) else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated() {
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    matches.append("\(safe.lastPathComponent):\(index + 1): \(line.prefix(500))")
                    if matches.count >= 100 { return matches.joined(separator: "\n").prefixString(40_000) }
                }
            }
        }
        return matches.isEmpty ? "没有匹配结果。" : matches.joined(separator: "\n").prefixString(40_000)
    }
}

private extension String {
    func prefixString(_ count: Int) -> String { String(prefix(count)) }
}
