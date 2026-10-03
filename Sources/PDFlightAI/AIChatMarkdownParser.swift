import Foundation

public enum AIChatMarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList(start: Int, items: [String])
    case blockquote(String)
    case code(language: String?, content: String)
    case table(headers: [String], rows: [[String]])
    case horizontalRule
}

public enum AIChatMarkdownParser {
    public static func blocks(in markdown: String) -> [AIChatMarkdownBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var result: [AIChatMarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let closingDelimiter = standaloneMathClosingDelimiter(for: trimmed),
               let closingIndex = lines.indices.dropFirst(index + 1).first(where: {
                   lines[$0].trimmingCharacters(in: .whitespaces) == closingDelimiter
               }) {
                result.append(.paragraph(
                    lines[index...closingIndex].joined(separator: "\n")
                ))
                index = closingIndex + 1
                continue
            }

            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                index += 1
                var codeLines: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                result.append(.code(
                    language: language.isEmpty ? nil : language,
                    content: codeLines.joined(separator: "\n")
                ))
                continue
            }

            if let heading = heading(from: trimmed) {
                result.append(heading)
                index += 1
                continue
            }

            if isHorizontalRule(trimmed) {
                result.append(.horizontalRule)
                index += 1
                continue
            }

            if index + 1 < lines.count,
               isTableDelimiter(lines[index + 1]),
               trimmed.contains("|") {
                let headers = tableCells(in: line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let candidate = lines[index]
                    guard !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                          candidate.contains("|") else { break }
                    rows.append(tableCells(in: candidate))
                    index += 1
                }
                result.append(.table(headers: headers, rows: rows))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quoteLines.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                result.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            if unorderedItem(from: line) != nil {
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(from: lines[index]) {
                    items.append(item)
                    index += 1
                }
                result.append(.unorderedList(items))
                continue
            }

            if let first = orderedItem(from: line) {
                var items = [first.text]
                let start = first.number
                index += 1
                while index < lines.count, let item = orderedItem(from: lines[index]) {
                    items.append(item.text)
                    index += 1
                }
                result.append(.orderedList(start: start, items: items))
                continue
            }

            var paragraphLines = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty || startsBlock(
                    candidateTrimmed,
                    line: candidate,
                    nextLine: index + 1 < lines.count ? lines[index + 1] : nil
                ) {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            result.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }
        return result
    }

    private static func standaloneMathClosingDelimiter(for line: String) -> String? {
        switch line {
        case "$$": "$$"
        case "\\[": "\\]"
        default: nil
        }
    }

    private static func startsBlock(_ trimmed: String, line: String, nextLine: String?) -> Bool {
        trimmed.hasPrefix("```")
            || heading(from: trimmed) != nil
            || isHorizontalRule(trimmed)
            || trimmed.hasPrefix(">")
            || unorderedItem(from: line) != nil
            || orderedItem(from: line) != nil
            || (nextLine.map(isTableDelimiter) == true && trimmed.contains("|"))
    }

    private static func heading(from line: String) -> AIChatMarkdownBlock? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first?.isWhitespace == true else { return nil }
        return .heading(
            level: hashes,
            text: remainder.trimmingCharacters(in: .whitespaces)
        )
    }

    private static func unorderedItem(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              "-*+".contains(first),
              trimmed.dropFirst().first?.isWhitespace == true else { return nil }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(from line: String) -> (number: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber }
        guard let number = Int(digits), !digits.isEmpty else { return nil }
        let suffix = trimmed.dropFirst(digits.count)
        guard let marker = suffix.first,
              marker == "." || marker == ")",
              suffix.dropFirst().first?.isWhitespace == true else { return nil }
        return (number, suffix.dropFirst().trimmingCharacters(in: .whitespaces))
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: CharacterSet(charactersIn: " :-"))
            return trimmed.isEmpty && cell.filter { $0 == "-" }.count >= 3
        }
    }

    private static func tableCells(in line: String) -> [String] {
        var value = line.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("|") { value.removeFirst() }
        if value.hasSuffix("|") { value.removeLast() }
        return value.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
