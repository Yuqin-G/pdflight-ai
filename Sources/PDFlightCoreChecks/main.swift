import Foundation
import PDFlightCore

@main
enum PDFlightCoreChecks {
    static func main() async throws {
        try textSelectionReturnsTextAndOneHighlightRectPerLine()
        print("PASS: text selection returns text and one highlight rect per line")
        try navigationBookmarkRestoresCenteredViewport()
        print("PASS: navigation history restores the exact centered viewport")
        try zoomAnchorKeepsPageCentered()
        print("PASS: zoom keeps the same page point at the viewport center")
        try returnAdvancesCompletedSearch()
        print("PASS: Return advances a completed search")
        try readingPositionSurvivesStoreReload()
        print("PASS: reading position survives a store reload")
        try readingPositionStorePrunesOldDocuments()
        print("PASS: reading position store prunes old documents")
        try await equivalentRequestsReuseCache()
        print("PASS: equivalent requests reuse the cached page")
        try await concurrentRequestsShareRender()
        print("PASS: concurrent equivalent requests share one render")
        try await invalidationForcesFreshRender()
        print("PASS: page invalidation forces a fresh render")
        try await cacheEvictsLeastRecentlyUsedPage()
        print("PASS: byte budget evicts the least recently used page")
    }

    private static func navigationBookmarkRestoresCenteredViewport() throws {
        let pageOrigin = PagePoint(x: 180, y: 300)
        let originalViewportOrigin = PagePoint(x: 0, y: 420)
        let bookmark = DocumentViewportBookmark.capture(
            pageIndex: 4,
            pageOrigin: pageOrigin,
            viewportOrigin: originalViewportOrigin,
            zoom: 1
        )

        let restored = bookmark.restoredViewportOrigin(pageOrigin: pageOrigin, zoom: 1)

        try check(
            restored == originalViewportOrigin,
            "expected navigation return origin \(originalViewportOrigin), got \(restored)"
        )
    }

    private static func zoomAnchorKeepsPageCentered() throws {
        let anchor = DocumentViewportZoomAnchor.capture(
            pageIndex: 0,
            pageOrigin: PagePoint(x: 200, y: 24),
            viewportOrigin: PagePoint(x: 0, y: 0),
            viewportSize: PagePoint(x: 1_000, y: 700),
            zoom: 1
        )

        let restored = anchor.restoredViewportOrigin(
            pageOrigin: PagePoint(x: 24, y: 24),
            zoom: 2
        )

        try check(
            restored.x == 124,
            "expected centered zoom origin x=124, got x=\(restored.x)"
        )
    }

    private static func returnAdvancesCompletedSearch() throws {
        try check(
            SearchSubmissionIntent.resolve(
                query: "reasoning",
                completedQuery: "reasoning",
                resultCount: 4,
                isShiftPressed: false
            ) == .nextResult,
            "expected Return to advance an existing search"
        )
        try check(
            SearchSubmissionIntent.resolve(
                query: "reasoning",
                completedQuery: "reasoning",
                resultCount: 4,
                isShiftPressed: true
            ) == .previousResult,
            "expected Shift-Return to move to the previous search result"
        )
        try check(
            SearchSubmissionIntent.resolve(
                query: "new query",
                completedQuery: "reasoning",
                resultCount: 4,
                isShiftPressed: false
            ) == .startSearch,
            "expected an edited query to start a new search"
        )
    }

    @MainActor
    private static func readingPositionSurvivesStoreReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-reading-position-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("reading-state.json")
        let documentURL = URL(fileURLWithPath: "/Users/reader/Papers/example.pdf")
        defer { try? FileManager.default.removeItem(at: directory) }

        let expected = ReadingPosition(
            bookmark: DocumentViewportBookmark(
                pageIndex: 14,
                point: PagePoint(x: -12.5, y: 318.25)
            ),
            zoom: 1.75,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let writer = ReadingPositionStore(fileURL: stateURL)
        try writer.save(expected, for: documentURL)

        let reader = ReadingPositionStore(fileURL: stateURL)
        let restored = try reader.position(for: documentURL)

        try check(restored == expected, "expected the exact reading position after reopening the store")
    }

    @MainActor
    private static func readingPositionStorePrunesOldDocuments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-reading-limit-\(UUID().uuidString)", isDirectory: true)
        let stateURL = directory.appendingPathComponent("reading-state.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = ReadingPositionStore(fileURL: stateURL, maximumDocumentCount: 2)
        for index in 0..<3 {
            let position = ReadingPosition(
                bookmark: DocumentViewportBookmark(
                    pageIndex: index,
                    point: PagePoint(x: 0, y: 0)
                ),
                zoom: 1,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
            )
            try store.save(
                position,
                for: URL(fileURLWithPath: "/Users/reader/Papers/\(index).pdf")
            )
        }

        let reloaded = ReadingPositionStore(fileURL: stateURL, maximumDocumentCount: 2)
        let oldest = try reloaded.position(
            for: URL(fileURLWithPath: "/Users/reader/Papers/0.pdf")
        )
        let newest = try reloaded.position(
            for: URL(fileURLWithPath: "/Users/reader/Papers/2.pdf")
        )

        try check(oldest == nil, "expected the least recently read document to be pruned")
        try check(newest?.bookmark.pageIndex == 2, "expected the newest document to remain")
    }

    private static func textSelectionReturnsTextAndOneHighlightRectPerLine() throws {
        let page = DocumentTextPage(
            pageIndex: 0,
            glyphs: [
                DocumentTextGlyph(scalar: 65, rect: PageRect(x: 10, y: 10, width: 5, height: 10), lineIndex: 0),
                DocumentTextGlyph(scalar: 66, rect: PageRect(x: 16, y: 10, width: 5, height: 10), lineIndex: 0),
                DocumentTextGlyph(scalar: 67, rect: PageRect(x: 10, y: 25, width: 5, height: 10), lineIndex: 1)
            ],
            plainText: "AB\nC"
        )

        let selection = page.textSelection(from: 2, through: 0)

        try check(selection?.text == "AB\nC", "expected selected text to preserve line breaks")
        try check(
            selection?.rects == [
                PageRect(x: 10, y: 10, width: 11, height: 10),
                PageRect(x: 10, y: 25, width: 5, height: 10)
            ],
            "expected one unioned highlight rectangle per selected line"
        )
    }

    private static func invalidationForcesFreshRender() async throws {
        let counter = InvocationCounter()
        let scheduler = RenderScheduler(byteLimit: 64) { request in
            await counter.increment()
            return RenderedPage(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixels: Data(repeating: UInt8(request.pageIndex), count: 16)
            )
        }
        let request = PageRenderRequest(pageIndex: 3, scale: 1)

        _ = try await scheduler.render(request)
        await scheduler.invalidate(pageIndex: 3)
        _ = try await scheduler.render(request)
        let count = await counter.value

        try check(count == 2, "expected invalidation to force a fresh render, got \(count)")
    }

    private static func cacheEvictsLeastRecentlyUsedPage() async throws {
        let counter = InvocationCounter()
        let scheduler = RenderScheduler(byteLimit: 16) { request in
            await counter.increment()
            return RenderedPage(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixels: Data(repeating: UInt8(request.pageIndex), count: 16)
            )
        }

        _ = try await scheduler.render(PageRenderRequest(pageIndex: 0, scale: 1))
        _ = try await scheduler.render(PageRenderRequest(pageIndex: 1, scale: 1))
        _ = try await scheduler.render(PageRenderRequest(pageIndex: 0, scale: 1))
        let count = await counter.value

        try check(count == 3, "expected the oldest page to be evicted, got \(count) renders")
    }

    private static func concurrentRequestsShareRender() async throws {
        let counter = InvocationCounter()
        let scheduler = RenderScheduler(byteLimit: 64) { request in
            await counter.increment()
            try await Task.sleep(for: .milliseconds(40))
            return RenderedPage(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixels: Data(repeating: UInt8(request.pageIndex), count: 16)
            )
        }
        let request = PageRenderRequest(pageIndex: 2, scale: 2)

        async let first = scheduler.render(request)
        async let second = scheduler.render(request)
        _ = try await (first, second)
        let count = await counter.value

        try check(count == 1, "expected concurrent requests to share one render, got \(count)")
    }

    private static func equivalentRequestsReuseCache() async throws {
        let counter = InvocationCounter()
        let scheduler = RenderScheduler(byteLimit: 64) { request in
            await counter.increment()
            return RenderedPage(
                width: 2,
                height: 2,
                bytesPerRow: 8,
                pixels: Data(repeating: UInt8(request.pageIndex), count: 16)
            )
        }
        let request = PageRenderRequest(pageIndex: 7, scale: 1.5)

        let first = try await scheduler.render(request)
        let second = try await scheduler.render(request)
        let count = await counter.value

        try check(first == second, "equivalent renders returned different pixels")
        try check(count == 1, "expected one render, got \(count)")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure(message) }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private actor InvocationCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
