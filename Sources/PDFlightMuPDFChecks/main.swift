import CoreGraphics
import CoreText
import Foundation
import PDFKit
import PDFlightCore
import PDFlightMuPDF

@main
enum PDFlightMuPDFChecks {
    static func main() async throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-engine-check-\(UUID().uuidString).pdf")
        let saved = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-engine-saved-\(UUID().uuidString).pdf")
        let encrypted = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdflight-engine-encrypted-\(UUID().uuidString).pdf")
        defer {
            try? FileManager.default.removeItem(at: fixture)
            try? FileManager.default.removeItem(at: saved)
            try? FileManager.default.removeItem(at: encrypted)
        }
        try makeFixture(at: fixture)
        try makeFixture(at: encrypted, password: "pdflight")

        do {
            _ = try MuPDFDocument(url: encrypted, storeLimit: 8 * 1_024 * 1_024)
            throw CheckFailure("expected an encrypted PDF to request a password")
        } catch DocumentEngineError.passwordRequired {
            // Expected.
        }
        do {
            _ = try MuPDFDocument(
                url: encrypted, password: "incorrect", storeLimit: 8 * 1_024 * 1_024)
            throw CheckFailure("expected an incorrect password to be rejected")
        } catch DocumentEngineError.incorrectPassword {
            // Expected.
        }
        let unlocked = try MuPDFDocument(
            url: encrypted, password: "pdflight", storeLimit: 8 * 1_024 * 1_024)
        try check(unlocked.pageCount == 2, "correct password did not unlock the PDF")

        let document = try MuPDFDocument(url: fixture, storeLimit: 8 * 1_024 * 1_024)
        let pageCount = document.pageCount
        try check(pageCount == 2, "expected 2 pages, got \(pageCount)")

        let outline = try await document.outline()
        try check(
            outline == [
                DocumentOutlineEntry(
                    title: "Introduction",
                    pageIndex: 0,
                    point: PagePoint(x: 0, y: 0),
                    isInitiallyExpanded: true,
                    children: [
                        DocumentOutlineEntry(
                            title: "Methods",
                            pageIndex: 1,
                            point: PagePoint(x: 0, y: 0)
                        )
                    ]
                ),
                DocumentOutlineEntry(
                    title: "Appendix",
                    pageIndex: 1,
                    point: PagePoint(x: 0, y: 0)
                )
            ],
            "expected MuPDF to preserve the fixture's hierarchical outline, got \(outline)"
        )

        let firstPage = try await document.page(at: 0)
        try check(firstPage.width == 300, "expected a 300 point page, got \(firstPage.width)")
        try check(firstPage.height == 400, "expected a 400 point page, got \(firstPage.height)")
        try check(firstPage.links.contains { link in
            if case .url(let url) = link.target { return url.absoluteString == "https://example.com/paper" }
            return false
        }, "expected the fixture's external link")
        try check(firstPage.links.contains { link in
            if case .page(let index, _) = link.target { return index == 1 }
            return false
        }, "expected the fixture's internal page link")

        let extracted = try await document.text(on: 0)
        try check(
            extracted.plainText.contains("PDFlight searchable phrase"),
            "expected text extraction to return the fixture text"
        )
        try check(!extracted.glyphs.isEmpty, "expected text extraction to include glyph geometry")
        let hits = try await document.search("searchable phrase")
        try check(hits.map(\.pageIndex) == [0, 1], "expected search hits on both fixture pages")
        try check(hits.allSatisfy { !$0.rects.isEmpty }, "expected search hits to include geometry")

        let bitmap = try await document.render(PageRenderRequest(pageIndex: 0, scale: 1))
        try check(bitmap.width == 300, "expected a 300 pixel render, got \(bitmap.width)")
        try check(bitmap.height == 400, "expected a 400 pixel render, got \(bitmap.height)")
        try check(bitmap.pixels.count == bitmap.bytesPerRow * bitmap.height, "pixel buffer size is inconsistent")

        let doubled = try await document.render(PageRenderRequest(pageIndex: 0, scale: 2))
        let expectedBarPixel = (180 * doubled.bytesPerRow) + (100 * 3)
        try check(
            doubled.pixels[expectedBarPixel] < 128,
            "2x rendering moved content away from its expected page coordinate"
        )

        let blankBefore = try await document.render(PageRenderRequest(pageIndex: 1, scale: 1))
        try await document.add(.highlight(
            pageIndex: 1,
            rects: [
                PageRect(x: 60, y: 80, width: 180, height: 28),
                PageRect(x: 60, y: 112, width: 120, height: 28)
            ],
            contents: "PDFlight engine check"
        ))
        let highlightedBeforeUndo = try await document.render(
            PageRenderRequest(pageIndex: 1, scale: 1))
        try check(
            highlightedBeforeUndo.pixels != blankBefore.pixels,
            "highlight did not change the rendered page before undo"
        )
        let undonePage = try await document.undoLastAnnotation()
        try check(undonePage == 1, "undo did not report the affected page")
        let afterUndo = try await document.render(PageRenderRequest(pageIndex: 1, scale: 1))
        try check(afterUndo.pixels == blankBefore.pixels, "undo did not restore the page")

        try await document.add(.highlight(
            pageIndex: 1,
            rects: [PageRect(x: 60, y: 80, width: 180, height: 28)],
            contents: "PDFlight engine check"
        ))
        try await document.add(.note(
            pageIndex: 1,
            point: PagePoint(x: 44, y: 54),
            contents: "A saved PDFlight note"
        ))
        try await document.save(to: saved)
        let reopened = try MuPDFDocument(url: saved, storeLimit: 8 * 1_024 * 1_024)
        let highlighted = try await reopened.render(PageRenderRequest(pageIndex: 1, scale: 1))
        try check(blankBefore.pixels != highlighted.pixels, "saved highlight did not change the rendered page")

        print("PASS: MuPDF passwords, text, search, links, rendering, highlights, and notes")
    }

    private static func makeFixture(at url: URL, password: String? = nil) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 300, height: 400)
        var options: [CFString: Any] = [:]
        if let password {
            options[kCGPDFContextUserPassword] = password
            options[kCGPDFContextOwnerPassword] = "pdflight-owner"
            options[kCGPDFContextEncryptionKeyLength] = 128
        }
        guard let context = CGContext(
            url as CFURL,
            mediaBox: &mediaBox,
            options.isEmpty ? nil : options as CFDictionary
        ) else {
            throw CheckFailure("could not create fixture PDF")
        }

        context.beginPDFPage(nil)
        drawText("PDFlight searchable phrase", in: context, at: CGPoint(x: 40, y: 340))
        context.setFillColor(CGColor(gray: 0.2, alpha: 1))
        context.fill(CGRect(x: 40, y: 300, width: 220, height: 20))
        context.setURL(URL(string: "https://example.com/paper")! as CFURL,
                       for: CGRect(x: 40, y: 300, width: 220, height: 20))
        context.setDestination("pdflight-page-two" as CFString,
                               for: CGRect(x: 40, y: 250, width: 220, height: 20))
        context.endPDFPage()

        context.beginPDFPage(nil)
        context.addDestination("pdflight-page-two" as CFString, at: CGPoint(x: 0, y: 400))
        drawText("PDFlight searchable phrase", in: context, at: CGPoint(x: 40, y: 340))
        context.endPDFPage()
        context.closePDF()
        if password == nil {
            try addOutline(to: url)
        }
    }

    private static func addOutline(to url: URL) throws {
        guard let document = PDFDocument(url: url),
              let firstPage = document.page(at: 0),
              let secondPage = document.page(at: 1) else {
            throw CheckFailure("could not reopen the fixture to add its outline")
        }

        let root = PDFOutline()
        let introduction = PDFOutline()
        introduction.label = "Introduction"
        introduction.destination = PDFDestination(
            page: firstPage,
            at: NSPoint(x: 0, y: firstPage.bounds(for: .mediaBox).height)
        )
        let methods = PDFOutline()
        methods.label = "Methods"
        methods.destination = PDFDestination(
            page: secondPage,
            at: NSPoint(x: 0, y: secondPage.bounds(for: .mediaBox).height)
        )
        introduction.insertChild(methods, at: 0)
        introduction.isOpen = true

        let appendix = PDFOutline()
        appendix.label = "Appendix"
        appendix.destination = PDFDestination(
            page: secondPage,
            at: NSPoint(x: 0, y: secondPage.bounds(for: .mediaBox).height)
        )
        root.insertChild(introduction, at: 0)
        root.insertChild(appendix, at: 1)
        document.outlineRoot = root
        guard document.write(to: url) else {
            throw CheckFailure("could not write the fixture outline")
        }
    }

    private static func drawText(_ text: String, in context: CGContext, at point: CGPoint) {
        let font = CTFontCreateWithName("Helvetica" as CFString, 15, nil)
        let attributed = NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key: font]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
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
