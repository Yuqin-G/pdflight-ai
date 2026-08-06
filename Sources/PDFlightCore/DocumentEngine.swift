import Foundation

public struct PagePoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PageRect: Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum DocumentLinkTarget: Sendable, Equatable {
    case page(index: Int, point: PagePoint?)
    case url(URL)
}

public struct DocumentLink: Sendable, Equatable {
    public let rect: PageRect
    public let target: DocumentLinkTarget

    public init(rect: PageRect, target: DocumentLinkTarget) {
        self.rect = rect
        self.target = target
    }
}

public struct DocumentPage: Sendable, Equatable {
    public let index: Int
    public let width: Double
    public let height: Double
    public let links: [DocumentLink]

    public init(index: Int, width: Double, height: Double, links: [DocumentLink]) {
        self.index = index
        self.width = width
        self.height = height
        self.links = links
    }
}

public struct DocumentTextGlyph: Sendable, Equatable {
    public let scalar: UInt32
    public let rect: PageRect
    public let lineIndex: Int

    public init(scalar: UInt32, rect: PageRect, lineIndex: Int) {
        self.scalar = scalar
        self.rect = rect
        self.lineIndex = lineIndex
    }

    public var string: String {
        UnicodeScalar(scalar).map(String.init) ?? "�"
    }
}

public struct DocumentTextPage: Sendable, Equatable {
    public let pageIndex: Int
    public let glyphs: [DocumentTextGlyph]
    public let plainText: String

    public init(pageIndex: Int, glyphs: [DocumentTextGlyph], plainText: String) {
        self.pageIndex = pageIndex
        self.glyphs = glyphs
        self.plainText = plainText
    }

    public func textSelection(from anchor: Int, through end: Int) -> DocumentTextSelection? {
        guard glyphs.indices.contains(anchor), glyphs.indices.contains(end) else { return nil }
        let selectedGlyphs = glyphs[min(anchor, end)...max(anchor, end)]
        var text = ""
        var rects: [PageRect] = []
        var currentLine: Int?

        for glyph in selectedGlyphs {
            if currentLine != glyph.lineIndex {
                if currentLine != nil { text.append("\n") }
                rects.append(glyph.rect)
                currentLine = glyph.lineIndex
            } else if let lastRect = rects.last {
                rects[rects.count - 1] = lastRect.union(glyph.rect)
            }
            text.append(glyph.string)
        }
        return DocumentTextSelection(text: text, rects: rects)
    }
}

public struct DocumentTextSelection: Sendable, Equatable {
    public let text: String
    public let rects: [PageRect]

    public init(text: String, rects: [PageRect]) {
        self.text = text
        self.rects = rects
    }
}

private extension PageRect {
    func union(_ other: PageRect) -> PageRect {
        let minX = min(x, other.x)
        let minY = min(y, other.y)
        let maxX = max(x + width, other.x + other.width)
        let maxY = max(y + height, other.y + other.height)
        return PageRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

public struct DocumentSearchHit: Sendable, Equatable {
    public let pageIndex: Int
    public let rects: [PageRect]

    public init(pageIndex: Int, rects: [PageRect]) {
        self.pageIndex = pageIndex
        self.rects = rects
    }
}

public struct DocumentOutlineEntry: Sendable, Equatable {
    public let title: String
    public let pageIndex: Int?
    public let point: PagePoint?
    public let isInitiallyExpanded: Bool
    public let children: [DocumentOutlineEntry]

    public init(
        title: String,
        pageIndex: Int?,
        point: PagePoint? = nil,
        isInitiallyExpanded: Bool = false,
        children: [DocumentOutlineEntry] = []
    ) {
        self.title = title
        self.pageIndex = pageIndex
        self.point = point
        self.isInitiallyExpanded = isInitiallyExpanded
        self.children = children
    }
}

public enum DocumentAnnotationDraft: Sendable, Equatable {
    case highlight(pageIndex: Int, rects: [PageRect], contents: String?)
    case note(pageIndex: Int, point: PagePoint, contents: String)
}

public protocol DocumentEngine: Actor {
    nonisolated var pageCount: Int { get }
    func outline() throws -> [DocumentOutlineEntry]
    func page(at index: Int) throws -> DocumentPage
    func text(on pageIndex: Int) throws -> DocumentTextPage
    func search(_ query: String) throws -> [DocumentSearchHit]
    func render(_ request: PageRenderRequest) throws -> RenderedPage
    func add(_ annotation: DocumentAnnotationDraft) throws
    func undoLastAnnotation() throws -> Int?
    func save(to url: URL) throws
    func releaseMemory()
}

public enum DocumentEngineError: Error, LocalizedError, Sendable {
    case invalidPage(Int)
    case unsupportedDocument
    case passwordRequired
    case incorrectPassword
    case engineFailure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPage(let page): "Page \(page + 1) does not exist."
        case .unsupportedDocument: "This document is not a supported PDF."
        case .passwordRequired: "This PDF requires a password."
        case .incorrectPassword: "The PDF password is incorrect."
        case .engineFailure(let message): message
        }
    }
}
