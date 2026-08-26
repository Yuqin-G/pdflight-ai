import Foundation

enum IOSMathLatexCompatibility {
    static func renderable(_ latex: String) -> String {
        var output = ""
        var cursor = latex.startIndex

        while let command = nextExtendedArrow(in: latex, after: cursor) {
            output += latex[cursor..<command.range.lowerBound]
            guard let replacement = replacement(
                for: command.name,
                in: latex,
                after: command.range.upperBound
            ) else {
                output += latex[command.range]
                cursor = command.range.upperBound
                continue
            }
            output += replacement.latex
            cursor = replacement.resumeAt
        }

        output += latex[cursor...]
        return output
    }

    private static func nextExtendedArrow(
        in latex: String,
        after cursor: String.Index
    ) -> (name: String, range: Range<String.Index>)? {
        ["xrightarrow", "xleftarrow"]
            .compactMap { name -> (String, Range<String.Index>)? in
                nextCommand(named: name, in: latex, after: cursor)
                    .map { (name, $0) }
            }
            .min { $0.1.lowerBound < $1.1.lowerBound }
    }

    private static func nextCommand(
        named name: String,
        in latex: String,
        after cursor: String.Index
    ) -> Range<String.Index>? {
        var searchStart = cursor
        while searchStart < latex.endIndex,
              let range = latex.range(
                of: "\\\(name)",
                range: searchStart..<latex.endIndex
              ) {
            let hasCommandBoundary = range.upperBound == latex.endIndex
                || !latex[range.upperBound].isLetter
            if !isEscaped(at: range.lowerBound, in: latex), hasCommandBoundary {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    private static func replacement(
        for command: String,
        in latex: String,
        after commandEnd: String.Index
    ) -> (latex: String, resumeAt: String.Index)? {
        var cursor = commandEnd
        while cursor < latex.endIndex, latex[cursor].isWhitespace {
            cursor = latex.index(after: cursor)
        }

        var lowerLabel: String?
        if cursor < latex.endIndex, latex[cursor] == "[" {
            guard let group = balancedGroup(
                in: latex,
                startingAt: cursor,
                opening: "[",
                closing: "]"
            ) else { return nil }
            lowerLabel = group.body
            cursor = group.resumeAt
            while cursor < latex.endIndex, latex[cursor].isWhitespace {
                cursor = latex.index(after: cursor)
            }
        }

        guard cursor < latex.endIndex, latex[cursor] == "{",
              let upperLabel = balancedGroup(
                in: latex,
                startingAt: cursor,
                opening: "{",
                closing: "}"
              ) else { return nil }

        let arrow = command == "xleftarrow" ? "\\longleftarrow" : "\\longrightarrow"
        let upper = "\\overset{\(upperLabel.body)}{\(arrow)}"
        let compatible = lowerLabel.map { "\\underset{\($0)}{\(upper)}" } ?? upper
        return (compatible, upperLabel.resumeAt)
    }

    private static func balancedGroup(
        in latex: String,
        startingAt start: String.Index,
        opening: Character,
        closing: Character
    ) -> (body: String, resumeAt: String.Index)? {
        guard start < latex.endIndex, latex[start] == opening else { return nil }
        var depth = 0
        var escaped = false
        var cursor = start
        let bodyStart = latex.index(after: start)

        while cursor < latex.endIndex {
            let character = latex[cursor]
            if character == "\\" {
                escaped.toggle()
            } else {
                if !escaped, character == opening { depth += 1 }
                if !escaped, character == closing {
                    depth -= 1
                    if depth == 0 {
                        return (
                            String(latex[bodyStart..<cursor]),
                            latex.index(after: cursor)
                        )
                    }
                }
                escaped = false
            }
            cursor = latex.index(after: cursor)
        }
        return nil
    }

    private static func isEscaped(at index: String.Index, in latex: String) -> Bool {
        var cursor = index
        var slashCount = 0
        while cursor > latex.startIndex {
            let previous = latex.index(before: cursor)
            guard latex[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }
        return slashCount % 2 == 1
    }
}
