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
        try readerSessionStoreRestoresOnlyTheLastOpenPDFs()
        print("PASS: reader session store restores only the last open PDFs")
        try await paperLibraryPersistsNestedCollectionsAndAssignments()
        print("PASS: paper library persists nested collections and paper assignments")
        try await paperLibraryTracksTrueRecentFilesAndMovesSelectionsAtomically()
        print("PASS: paper library tracks true recent files and moves multi-selections atomically")
        try legacyPaperLibraryPapersGainAutomaticAliases()
        print("PASS: legacy paper-library JSON gains automatic display aliases")
        try await equivalentRequestsReuseCache()
        print("PASS: equivalent requests reuse the cached page")
        try await concurrentRequestsShareRender()
        print("PASS: concurrent equivalent requests share one render")
        try await invalidationForcesFreshRender()
        print("PASS: page invalidation forces a fresh render")
        try await cacheEvictsLeastRecentlyUsedPage()
        print("PASS: byte budget evicts the least recently used page")
    }

    private static func paperLibraryPersistsNestedCollectionsAndAssignments() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-paper-library-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("paper-library.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = PaperLibraryStore(fileURL: fileURL)
        let vision = try await writer.createCollection(name: "Vision", parentID: nil)
        let reasoning = try await writer.createCollection(name: "Reasoning", parentID: vision.id)
        let paper = try await writer.addPaper(
            at: URL(
                fileURLWithPath: "/Users/reader/Papers/Ming 等 - 2026 - Yesterday's Shield, Today's Spear.pdf"
            ),
            to: nil
        )
        try check(
            paper.displayTitle == "Yesterday's Shield, Today's Spear",
            "expected author and year prefixes to be omitted from the automatic display alias"
        )
        try await writer.setPaperDisplayAlias(paper.id, to: "Shield and Spear")
        try await writer.movePaper(paper.id, to: reasoning.id)

        let reader = PaperLibraryStore(fileURL: fileURL)
        let snapshot = try await reader.snapshot()
        try check(snapshot.collections.count == 2, "expected both collection levels after reload")
        try check(
            snapshot.collections.first { $0.id == reasoning.id }?.parentID == vision.id,
            "expected the nested collection to retain its parent"
        )
        try check(
            snapshot.papers.first { $0.id == paper.id }?.collectionID == reasoning.id,
            "expected the paper assignment to survive reload"
        )
        try check(
            snapshot.papers.first { $0.id == paper.id }?.displayTitle == "Shield and Spear",
            "expected a custom paper display alias to survive reload"
        )
        try await reader.setPaperDisplayAlias(paper.id, to: "  ")
        let resetSnapshot = try await reader.snapshot()
        try check(
            resetSnapshot.papers.first { $0.id == paper.id }?.displayTitle
                == "Yesterday's Shield, Today's Spear",
            "expected clearing a custom alias to restore the automatic display alias"
        )

        do {
            try await reader.moveCollection(vision.id, to: reasoning.id)
            throw CheckFailure("expected collection cycles to be rejected")
        } catch PaperLibraryError.collectionCycle {
            // Expected.
        }
    }

    private static func readerSessionStoreRestoresOnlyTheLastOpenPDFs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-session-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("last-session.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = URL(fileURLWithPath: "/Users/reader/Papers/first.pdf")
        let second = URL(fileURLWithPath: "/Users/reader/Papers/second.PDF")
        let store = ReaderSessionStore(fileURL: fileURL)
        try store.save(
            documentURLs: [first, first, URL(fileURLWithPath: "/tmp/note.txt"), second],
            activeDocumentURL: first
        )
        let restoredState = try store.state()
        let restored = restoredState.documentURLs
        try check(
            restored == [first.standardizedFileURL, second.standardizedFileURL],
            "expected a portable, deduplicated PDF window session"
        )
        try check(
            restoredState.activeDocumentURL == first.standardizedFileURL,
            "expected the last active PDF tab to survive a session reload"
        )
        try store.clear()
        let cleared = try store.documentURLs()
        try check(cleared.isEmpty, "expected the saved window session to be clearable")
    }

    private static func legacyPaperLibraryPapersGainAutomaticAliases() throws {
        let data = Data("""
        {
          "id": "legacy-paper",
          "title": "Ming 等 - 2026 - Yesterday's Shield, Today's Spear",
          "path": "/Users/reader/Papers/legacy.pdf",
          "collectionID": null,
          "addedAt": "2026-08-20T12:00:00Z",
          "lastOpenedAt": "2026-08-20T12:00:00Z"
        }
        """.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let paper = try decoder.decode(PaperLibraryPaper.self, from: data)
        try check(paper.displayAlias == nil, "expected legacy JSON to decode without a stored alias")
        try check(
            paper.displayTitle == "Yesterday's Shield, Today's Spear",
            "expected a legacy paper to receive its derived display alias"
        )
    }

    private static func paperLibraryTracksTrueRecentFilesAndMovesSelectionsAtomically() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-paper-history-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent("paper-library.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PaperLibraryStore(fileURL: fileURL)
        let source = try await store.createCollection(name: "Inbox", parentID: nil)
        let destination = try await store.createCollection(name: "Methods", parentID: nil)
        let firstURL = URL(fileURLWithPath: "/Users/reader/Papers/first.pdf")
        let secondURL = URL(fileURLWithPath: "/Users/reader/Papers/second.pdf")
        let first = try await store.addPaper(at: firstURL, to: source.id)
        let second = try await store.addPaper(at: secondURL, to: source.id)
        let recentAfterAdding = try await store.recentPapers()
        try check(
            recentAfterAdding.isEmpty,
            "adding a PDF to Library should not claim it was opened"
        )

        _ = try await store.recordOpenedPaper(at: firstURL)
        try await Task.sleep(for: .milliseconds(2))
        _ = try await store.recordOpenedPaper(at: secondURL)
        let recent = try await store.recentPapers()
        try check(recent.map(\.id) == [second.id, first.id], "expected newest opened PDF first")

        try await store.movePapers([first.id, second.id], to: destination.id)
        let moved = try await store.snapshot().papers.filter { [first.id, second.id].contains($0.id) }
        try check(
            moved.allSatisfy { $0.collectionID == destination.id },
            "expected a selected group to move in one store update"
        )

        try await store.clearRecentHistory()
        let recentAfterClearing = try await store.recentPapers()
        try check(recentAfterClearing.isEmpty, "expected recent-file history to be clearable")
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
