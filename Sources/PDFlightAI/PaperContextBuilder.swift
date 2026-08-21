import Foundation
import PDFlightCore

public struct PaperContext: Sendable, Equatable {
    public let text: String
    public let includedPageCount: Int
    public let totalPageCount: Int
    public let wasTruncated: Bool

    public init(
        text: String,
        includedPageCount: Int,
        totalPageCount: Int,
        wasTruncated: Bool
    ) {
        self.text = text
        self.includedPageCount = includedPageCount
        self.totalPageCount = totalPageCount
        self.wasTruncated = wasTruncated
    }
}

public enum PaperContextBuilder {
    public static func build(
        engine: any DocumentEngine,
        title: String,
        maximumCharacters: Int = 120_000
    ) async throws -> PaperContext {
        let limit = max(1, maximumCharacters)
        var consumedCharacters = 0
        var includedPages = 0
        var sections: [String] = ["Title: \(title)"]
        var wasTruncated = false

        for pageIndex in 0..<engine.pageCount {
            try Task.checkCancellation()
            let page = try await engine.text(on: pageIndex)
            let pageText = page.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pageText.isEmpty else { continue }

            let remaining = limit - consumedCharacters
            if remaining <= 0 {
                wasTruncated = true
                break
            }
            if pageText.count > remaining {
                if includedPages == 0 {
                    sections.append("[Page \(pageIndex + 1)]\n\(String(pageText.prefix(remaining)))")
                    includedPages = 1
                    consumedCharacters += remaining
                }
                wasTruncated = true
                break
            }

            sections.append("[Page \(pageIndex + 1)]\n\(pageText)")
            includedPages += 1
            consumedCharacters += pageText.count
        }

        if wasTruncated {
            sections.append("[Document context was truncated to stay within the configured limit.]")
        }

        return PaperContext(
            text: sections.joined(separator: "\n\n"),
            includedPageCount: includedPages,
            totalPageCount: engine.pageCount,
            wasTruncated: wasTruncated
        )
    }
}
