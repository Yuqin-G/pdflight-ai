import Foundation
import CMuPDF
import PDFlightCore

public actor MuPDFDocument: DocumentEngine {
    public nonisolated let pageCount: Int
    private let handle: DocumentHandle
    private var annotationPages: [Int] = []

    public init(
        url: URL,
        password: String? = nil,
        storeLimit: Int = 64 * 1_024 * 1_024
    ) throws {
        var error = ErrorBuffer()
        var errorCode: Int32 = 0
        let opened = url.path.withCString { path in
            if let password {
                return password.withCString { password in
                    pl_document_open(
                        path, password, storeLimit, &errorCode, &error.bytes, error.bytes.count)
                }
            }
            return pl_document_open(
                path, nil, storeLimit, &errorCode, &error.bytes, error.bytes.count)
        }
        guard let opened else { throw error.engineError(code: errorCode) }
        self.handle = DocumentHandle(raw: opened)
        self.pageCount = Int(pl_document_page_count(opened))
    }

    deinit {
        pl_document_close(handle.raw)
    }

    public func outline() throws -> [DocumentOutlineEntry] {
        var rawEntries: UnsafeMutablePointer<PLOutlineEntry>?
        var entryCount = 0
        var error = ErrorBuffer()
        let succeeded = pl_document_outline(
            handle.raw,
            &rawEntries,
            &entryCount,
            &error.bytes,
            error.bytes.count
        )
        guard succeeded != 0 else { throw error.engineError() }
        defer { pl_outline_entries_free(rawEntries, entryCount) }
        guard let rawEntries else { return [] }

        var builders: [OutlineBuilder] = []
        builders.reserveCapacity(entryCount)
        var roots: [OutlineBuilder] = []
        for offset in 0..<entryCount {
            let raw = rawEntries[offset]
            let pageIndex = raw.target_page >= 0 ? Int(raw.target_page) : nil
            let builder = OutlineBuilder(
                title: String(cString: raw.title),
                pageIndex: pageIndex,
                point: pageIndex.map { _ in
                    PagePoint(x: Double(raw.target_x), y: Double(raw.target_y))
                },
                isInitiallyExpanded: raw.is_open != 0
            )
            builders.append(builder)
            if raw.parent_index >= 0,
               builders.indices.contains(Int(raw.parent_index)) {
                builders[Int(raw.parent_index)].children.append(builder)
            } else {
                roots.append(builder)
            }
        }
        return roots.map(\.entry)
    }

    public func page(at index: Int) throws -> DocumentPage {
        try validate(pageIndex: index)
        var size = PLPageSize()
        var rawLinks: UnsafeMutablePointer<PLLink>?
        var linkCount = 0
        var error = ErrorBuffer()
        let succeeded = pl_document_page(
            handle.raw, Int32(index), &size, &rawLinks, &linkCount, &error.bytes, error.bytes.count)
        guard succeeded != 0 else { throw error.engineError() }
        defer { pl_links_free(rawLinks, linkCount) }

        let links: [DocumentLink] = rawLinks.map { buffer in
            (0..<linkCount).compactMap { offset in
                let link = buffer[offset]
                let rect = PageRect(
                    x: Double(link.rect.x),
                    y: Double(link.rect.y),
                    width: Double(link.rect.width),
                    height: Double(link.rect.height)
                )
                if link.target_page >= 0 {
                    let point = PagePoint(x: Double(link.target_x), y: Double(link.target_y))
                    return DocumentLink(
                        rect: rect,
                        target: .page(index: Int(link.target_page), point: point)
                    )
                }
                guard let uri = link.uri,
                      let url = URL(string: String(cString: uri)) else { return nil }
                return DocumentLink(rect: rect, target: .url(url))
            }
        } ?? []

        return DocumentPage(
            index: index,
            width: Double(size.width),
            height: Double(size.height),
            links: links
        )
    }

    public func render(_ request: PageRenderRequest) throws -> RenderedPage {
        try validate(pageIndex: request.pageIndex)
        var bitmap = PLBitmap()
        var error = ErrorBuffer()
        let succeeded = pl_document_render(
            handle.raw,
            Int32(request.pageIndex),
            Float(request.scale),
            &bitmap,
            &error.bytes,
            error.bytes.count
        )
        guard succeeded != 0 else { throw error.engineError() }
        defer { pl_bitmap_free(&bitmap) }
        guard let samples = bitmap.samples else {
            throw DocumentEngineError.engineFailure("MuPDF returned an empty pixel buffer")
        }
        let byteCount = Int(bitmap.stride) * Int(bitmap.height)
        return RenderedPage(
            width: Int(bitmap.width),
            height: Int(bitmap.height),
            bytesPerRow: Int(bitmap.stride),
            pixels: Data(bytes: samples, count: byteCount)
        )
    }

    public func text(on pageIndex: Int) throws -> DocumentTextPage {
        try validate(pageIndex: pageIndex)
        var rawGlyphs: UnsafeMutablePointer<PLTextGlyph>?
        var glyphCount = 0
        var error = ErrorBuffer()
        let succeeded = pl_document_text(
            handle.raw,
            Int32(pageIndex),
            &rawGlyphs,
            &glyphCount,
            &error.bytes,
            error.bytes.count
        )
        guard succeeded != 0 else { throw error.engineError() }
        defer { pl_text_glyphs_free(rawGlyphs) }

        let glyphs: [DocumentTextGlyph]
        if let buffer = rawGlyphs {
            glyphs = (0..<glyphCount).map { offset in
                let glyph = buffer[offset]
                return DocumentTextGlyph(
                    scalar: glyph.scalar,
                    rect: pageRect(glyph.rect),
                    lineIndex: Int(glyph.line_index)
                )
            }
        } else {
            glyphs = []
        }

        var plainText = ""
        var previousLine: Int?
        for glyph in glyphs {
            if let previousLine, previousLine != glyph.lineIndex {
                plainText.append("\n")
            }
            plainText.append(glyph.string)
            previousLine = glyph.lineIndex
        }
        return DocumentTextPage(pageIndex: pageIndex, glyphs: glyphs, plainText: plainText)
    }

    public func search(_ query: String) throws -> [DocumentSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [DocumentSearchHit] = []
        for pageIndex in 0..<pageCount {
            let quads = try searchPage(handle: handle, pageIndex: pageIndex, query: trimmed)
            guard !quads.isEmpty else { continue }

            var currentMark: Int32?
            var rects: [PageRect] = []
            for quad in quads {
                if let currentMark, currentMark != quad.mark {
                    results.append(DocumentSearchHit(pageIndex: pageIndex, rects: rects))
                    rects.removeAll(keepingCapacity: true)
                }
                currentMark = quad.mark
                rects.append(quad.rect)
            }
            if !rects.isEmpty {
                results.append(DocumentSearchHit(pageIndex: pageIndex, rects: rects))
            }
        }
        return results
    }

    public func add(_ annotation: DocumentAnnotationDraft) throws {
        let pageIndex: Int
        switch annotation {
        case .highlight(let index, let rects, let contents):
            try addHighlights(pageIndex: index, rects: rects, contents: contents)
            pageIndex = index
        case .note(let index, let point, let contents):
            try addNote(pageIndex: index, point: point, contents: contents)
            pageIndex = index
        }
        annotationPages.append(pageIndex)
    }

    public func undoLastAnnotation() throws -> Int? {
        guard let pageIndex = annotationPages.last else { return nil }
        var error = ErrorBuffer()
        let succeeded = pl_document_undo(handle.raw, &error.bytes, error.bytes.count)
        guard succeeded != 0 else { throw error.engineError() }
        annotationPages.removeLast()
        return pageIndex
    }

    public func save(to url: URL) throws {
        var error = ErrorBuffer()
        let succeeded = url.path.withCString { path in
            pl_document_save(handle.raw, path, &error.bytes, error.bytes.count)
        }
        guard succeeded != 0 else { throw error.engineError() }
    }

    public func releaseMemory() {
        pl_document_empty_store(handle.raw)
    }

    private func validate(pageIndex: Int) throws {
        guard pageIndex >= 0, pageIndex < pageCount else {
            throw DocumentEngineError.invalidPage(pageIndex)
        }
    }

    private func addHighlights(pageIndex: Int, rects: [PageRect], contents: String?) throws {
        try validate(pageIndex: pageIndex)
        guard !rects.isEmpty else { return }
        var error = ErrorBuffer()
        let rawRects = rects.map { rect in
            PLRect(
                x: Float(rect.x),
                y: Float(rect.y),
                width: Float(rect.width),
                height: Float(rect.height)
            )
        }
        let errorCapacity = error.bytes.count
        let succeeded = rawRects.withUnsafeBufferPointer { buffer in
            if let contents {
                return contents.withCString { contentsPointer in
                    pl_document_add_highlights(
                        handle.raw,
                        Int32(pageIndex),
                        buffer.baseAddress,
                        buffer.count,
                        contentsPointer,
                        &error.bytes,
                        errorCapacity
                    )
                }
            } else {
                return pl_document_add_highlights(
                    handle.raw,
                    Int32(pageIndex),
                    buffer.baseAddress,
                    buffer.count,
                    nil,
                    &error.bytes,
                    errorCapacity
                )
            }
        }
        guard succeeded != 0 else { throw error.engineError() }
    }

    private func addNote(pageIndex: Int, point: PagePoint, contents: String) throws {
        try validate(pageIndex: pageIndex)
        var error = ErrorBuffer()
        let succeeded = contents.withCString { contents in
            pl_document_add_note(
                handle.raw,
                Int32(pageIndex),
                Float(point.x),
                Float(point.y),
                contents,
                &error.bytes,
                error.bytes.count
            )
        }
        guard succeeded != 0 else { throw error.engineError() }
    }
}

private func pageRect(_ rect: PLRect) -> PageRect {
    PageRect(
        x: Double(rect.x),
        y: Double(rect.y),
        width: Double(rect.width),
        height: Double(rect.height)
    )
}

private struct DocumentHandle: @unchecked Sendable {
    let raw: OpaquePointer
}

private final class OutlineBuilder {
    let title: String
    let pageIndex: Int?
    let point: PagePoint?
    let isInitiallyExpanded: Bool
    var children: [OutlineBuilder] = []

    init(
        title: String,
        pageIndex: Int?,
        point: PagePoint?,
        isInitiallyExpanded: Bool
    ) {
        self.title = title
        self.pageIndex = pageIndex
        self.point = point
        self.isInitiallyExpanded = isInitiallyExpanded
    }

    var entry: DocumentOutlineEntry {
        DocumentOutlineEntry(
            title: title,
            pageIndex: pageIndex,
            point: point,
            isInitiallyExpanded: isInitiallyExpanded,
            children: children.map(\.entry)
        )
    }
}

private struct SearchQuadResult: Sendable {
    let mark: Int32
    let rect: PageRect
}

private func searchPage(
    handle: DocumentHandle,
    pageIndex: Int,
    query: String
) throws -> [SearchQuadResult] {
    var rawQuads: UnsafeMutablePointer<PLSearchQuad>?
    var quadCount = 0
    var error = ErrorBuffer()
    let succeeded = query.withCString { query in
        pl_document_search_page(
            handle.raw,
            Int32(pageIndex),
            query,
            &rawQuads,
            &quadCount,
            &error.bytes,
            error.bytes.count
        )
    }
    guard succeeded != 0 else { throw error.engineError() }
    defer { pl_search_quads_free(rawQuads) }
    guard let rawQuads else { return [] }
    return (0..<quadCount).map { offset in
        SearchQuadResult(mark: rawQuads[offset].mark, rect: pageRect(rawQuads[offset].rect))
    }
}

private struct ErrorBuffer {
    var bytes = [CChar](repeating: 0, count: 512)

    func engineError(code: Int32 = 0) -> DocumentEngineError {
        let message = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return "Unknown MuPDF error" }
            return String(cString: base)
        }
        switch code {
        case Int32(PL_ERROR_PASSWORD_REQUIRED): return .passwordRequired
        case Int32(PL_ERROR_INCORRECT_PASSWORD): return .incorrectPassword
        default: return .engineFailure(message)
        }
    }
}
