import AppKit
import PDFlightCore

@MainActor
final class DocumentCanvasView: NSView {
    private(set) var pageViews: [PageView] = []
    private var pages: [DocumentPage] = []
    private let pageGap: CGFloat = 20
    private let outerMargin: CGFloat = 24

    override var isFlipped: Bool { true }

    func install(pages: [DocumentPage], delegate: PageViewDelegate, tool: ReaderTool) {
        pageViews.forEach { $0.removeFromSuperview() }
        self.pages = pages
        pageViews = pages.map { page in
            let view = PageView(frame: .zero)
            view.page = page
            view.delegate = delegate
            view.tool = tool
            view.layer?.shadowColor = NSColor.black.cgColor
            view.layer?.shadowOpacity = 0.14
            view.layer?.shadowRadius = 10
            view.layer?.shadowOffset = CGSize(width: 0, height: -2)
            addSubview(view)
            return view
        }
    }

    func layoutPages(zoom: Double, viewportWidth: CGFloat) {
        let widestPage = pages.map { $0.width * zoom }.max() ?? 0
        let canvasWidth = max(viewportWidth, widestPage + outerMargin * 2)
        var y = outerMargin

        for (page, view) in zip(pages, pageViews) {
            let size = NSSize(width: page.width * zoom, height: page.height * zoom)
            view.zoom = zoom
            view.frame = NSRect(
                x: (canvasWidth - size.width) / 2,
                y: y,
                width: size.width,
                height: size.height
            )
            y += size.height + pageGap
        }
        frame.size = NSSize(
            width: canvasWidth,
            height: max(1, y - pageGap + outerMargin)
        )
    }

    func indices(near visibleRect: CGRect) -> Set<Int> {
        let preload = visibleRect.height * 0.35
        let target = visibleRect.insetBy(dx: 0, dy: -preload)
        return Set(pageViews.indices.filter { pageViews[$0].frame.intersects(target) })
    }

    func pageIndex(at verticalOffset: CGFloat) -> Int? {
        if let visible = pageViews.firstIndex(where: { $0.frame.minY <= verticalOffset && $0.frame.maxY > verticalOffset }) {
            return visible
        }
        return pageViews.indices.min { left, right in
            abs(pageViews[left].frame.midY - verticalOffset) < abs(pageViews[right].frame.midY - verticalOffset)
        }
    }

}
