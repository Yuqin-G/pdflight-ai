import Foundation

public enum AIMessageContentSegment: Equatable, Sendable {
    case text(String)
    case math(latex: String, display: Bool)
}

public enum AIMessageContentParser {
    private struct Delimiter {
        let opening: String
        let closing: String
        let display: Bool
    }

    private static let delimiters = [
        Delimiter(opening: "$$", closing: "$$", display: true),
        Delimiter(opening: "\\[", closing: "\\]", display: true),
        Delimiter(opening: "\\(", closing: "\\)", display: false),
        Delimiter(opening: "$", closing: "$", display: false)
    ]

    public static func segments(in content: String) -> [AIMessageContentSegment] {
        guard !content.isEmpty else { return [.text("")] }
        var result: [AIMessageContentSegment] = []
        var cursor = content.startIndex

        while cursor < content.endIndex {
            guard let opening = nextOpening(in: content, after: cursor) else {
                appendText(String(content[cursor...]), to: &result)
                break
            }
            if opening.range.lowerBound > cursor {
                appendText(String(content[cursor..<opening.range.lowerBound]), to: &result)
            }
            let bodyStart = opening.range.upperBound
            let closingRange = nextOccurrence(
                of: opening.delimiter.closing,
                in: content,
                after: bodyStart,
                singleDollar: opening.delimiter.closing == "$"
            )

            if let closingRange {
                let rawLatex = String(content[bodyStart..<closingRange.lowerBound])
                let trimmedRawLatex = rawLatex.trimmingCharacters(in: .whitespacesAndNewlines)
                let latex = normalizedLatex(
                    rawLatex,
                    display: opening.delimiter.display
                )
                let hasCleanInlineBoundary = opening.delimiter.opening != "$"
                    || rawLatex == trimmedRawLatex
                if hasCleanInlineBoundary, isPlausibleLatex(latex) {
                    result.append(.math(latex: latex, display: opening.delimiter.display))
                    cursor = closingRange.upperBound
                    continue
                }
            }

            if opening.delimiter.opening == "$",
               let recovered = recoverTruncatedInlineLatex(
                in: content,
                after: bodyStart,
                before: closingRange?.lowerBound ?? content.endIndex
               ) {
                result.append(.math(latex: recovered.latex, display: false))
                cursor = recovered.resumeAt
                continue
            }

            if closingRange == nil {
                appendText(String(content[opening.range.lowerBound...]), to: &result)
                break
            }

            // Treat only the opener as ordinary text, then resume scanning. This
            // recovers a later valid formula instead of swallowing prose up to it.
            appendText(String(content[opening.range]), to: &result)
            cursor = opening.range.upperBound
        }
        return result
    }

    private static func normalizedLatex(_ rawLatex: String, display: Bool) -> String {
        let trimmed = rawLatex.trimmingCharacters(in: .whitespacesAndNewlines)
        let singleLine: String
        if display, trimmed.contains(where: { $0.isNewline }) {
            singleLine = trimmed
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        } else {
            singleLine = trimmed
        }
        return normalizeRepeatedEscapes(in: singleLine)
    }

    /// Some model gateways return LaTeX that has been escaped once for JSON and
    /// then escaped again as ordinary text. Normalize only formulas that carry
    /// that repeated-escape fingerprint so valid `\\` row breaks remain intact.
    private static func normalizeRepeatedEscapes(in latex: String) -> String {
        var cursor = latex.startIndex
        var hasRepeatedStructuralEscape = false
        var repeatedCommandRunCount = 0
        while cursor < latex.endIndex {
            guard latex[cursor] == "\\" else {
                cursor = latex.index(after: cursor)
                continue
            }
            var end = cursor
            var count = 0
            while end < latex.endIndex, latex[end] == "\\" {
                count += 1
                end = latex.index(after: end)
            }
            if count > 1, end < latex.endIndex {
                let next = latex[end]
                if next == "{" || next == "}" {
                    hasRepeatedStructuralEscape = true
                    break
                }
                if count >= 3, next.isLetter {
                    repeatedCommandRunCount += 1
                    let prefix = latex[..<cursor]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if prefix.isEmpty {
                        hasRepeatedStructuralEscape = true
                        break
                    }
                }
            }
            cursor = end
        }
        if repeatedCommandRunCount >= 2 {
            hasRepeatedStructuralEscape = true
        }
        guard hasRepeatedStructuralEscape else { return latex }

        var normalized = ""
        cursor = latex.startIndex
        while cursor < latex.endIndex {
            guard latex[cursor] == "\\" else {
                normalized.append(latex[cursor])
                cursor = latex.index(after: cursor)
                continue
            }
            var end = cursor
            var count = 0
            while end < latex.endIndex, latex[end] == "\\" {
                count += 1
                end = latex.index(after: end)
            }
            guard end < latex.endIndex else {
                normalized.append(String(repeating: "\\", count: count))
                break
            }
            let next = latex[end]
            if next == "_" {
                normalized.append("_")
                cursor = latex.index(after: end)
            } else if count > 1, next.isLetter || next == "{" || next == "}" {
                normalized.append("\\")
                cursor = end
            } else if count >= 4, count.isMultiple(of: 2), next.isWhitespace {
                normalized.append(String(repeating: "\\", count: count / 2))
                cursor = end
            } else {
                normalized.append(String(repeating: "\\", count: count))
                cursor = end
            }
        }
        return normalized
    }

    public static func isPlausibleLatex(_ latex: String) -> Bool {
        guard !latex.isEmpty,
              latex.count <= 512,
              !latex.contains("\n"),
              !latex.contains("\r") else {
            return false
        }

        var braceDepth = 0
        var previousWasEscape = false
        var textGroupDepths: [Int] = []
        var pendingTextGroup = false
        var index = latex.startIndex
        while index < latex.endIndex {
            let character = latex[index]
            if character == "\\",
               latex[index...].hasPrefix("\\text{") {
                pendingTextGroup = true
            }
            if character == "\\" {
                previousWasEscape.toggle()
                index = latex.index(after: index)
                continue
            }
            if !previousWasEscape {
                if character == "{" {
                    braceDepth += 1
                    if pendingTextGroup {
                        textGroupDepths.append(braceDepth)
                        pendingTextGroup = false
                    }
                }
                if character == "}" {
                    guard braceDepth > 0 else { return false }
                    if textGroupDepths.last == braceDepth {
                        textGroupDepths.removeLast()
                    }
                    braceDepth -= 1
                }
            }
            if character.unicodeScalars.contains(where: { $0.value >= 128 }),
               textGroupDepths.isEmpty {
                return false
            }
            previousWasEscape = false
            index = latex.index(after: index)
        }
        return braceDepth == 0 && !previousWasEscape
    }

    private static func recoverTruncatedInlineLatex(
        in content: String,
        after bodyStart: String.Index,
        before limit: String.Index
    ) -> (latex: String, resumeAt: String.Index)? {
        guard bodyStart < limit else { return nil }
        var boundary = bodyStart
        while boundary < limit {
            let character = content[boundary]
            if character == "\n" || character == "\r"
                || character.unicodeScalars.contains(where: { $0.value >= 128 }) {
                break
            }
            boundary = content.index(after: boundary)
        }
        guard boundary < limit || boundary < content.endIndex,
              boundary > bodyStart else { return nil }

        var candidate = String(content[bodyStart..<boundary])
        guard candidate.first?.isWhitespace != true, candidate.count <= 512 else { return nil }
        while candidate.last?.isWhitespace == true { candidate.removeLast() }

        while !candidate.isEmpty {
            if containsMathSyntax(candidate), isPlausibleLatex(candidate) {
                return (candidate, boundary)
            }
            candidate.removeLast()
            while candidate.last?.isWhitespace == true { candidate.removeLast() }
        }
        return nil
    }

    private static func containsMathSyntax(_ latex: String) -> Bool {
        latex.contains("\\")
            || latex.contains("_")
            || latex.contains("^")
            || latex.contains("=")
            || latex.contains("+")
            || latex.contains("*")
            || latex.contains("/")
            || latex.contains("<")
            || latex.contains(">")
    }

    private static func nextOpening(
        in content: String,
        after cursor: String.Index
    ) -> (delimiter: Delimiter, range: Range<String.Index>)? {
        var best: (delimiter: Delimiter, range: Range<String.Index>)?
        for delimiter in delimiters {
            guard let range = nextOccurrence(
                of: delimiter.opening,
                in: content,
                after: cursor,
                singleDollar: delimiter.opening == "$"
            ) else { continue }
            if best == nil || range.lowerBound < best!.range.lowerBound {
                best = (delimiter, range)
            }
        }
        return best
    }

    private static func nextOccurrence(
        of token: String,
        in content: String,
        after cursor: String.Index,
        singleDollar: Bool
    ) -> Range<String.Index>? {
        var searchStart = cursor
        while searchStart < content.endIndex,
              let range = content.range(of: token, range: searchStart..<content.endIndex) {
            let escaped = isEscaped(at: range.lowerBound, in: content)
            let belongsToDoubleDollar: Bool
            if singleDollar {
                let beforeIsDollar = range.lowerBound > content.startIndex
                    && content[content.index(before: range.lowerBound)] == "$"
                let afterIsDollar = range.upperBound < content.endIndex
                    && content[range.upperBound] == "$"
                belongsToDoubleDollar = beforeIsDollar || afterIsDollar
            } else {
                belongsToDoubleDollar = false
            }
            if !escaped && !belongsToDoubleDollar { return range }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func isEscaped(at index: String.Index, in content: String) -> Bool {
        var cursor = index
        var slashCount = 0
        while cursor > content.startIndex {
            let previous = content.index(before: cursor)
            guard content[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }
        return slashCount % 2 == 1
    }

    private static func appendText(
        _ text: String,
        to result: inout [AIMessageContentSegment]
    ) {
        guard !text.isEmpty else { return }
        if case let .text(existing)? = result.last {
            result[result.count - 1] = .text(existing + text)
        } else {
            result.append(.text(text))
        }
    }
}
