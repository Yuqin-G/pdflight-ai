public struct DocumentViewportZoomAnchor: Sendable, Equatable {
    public let pageIndex: Int
    public let point: PagePoint
    public let viewportOffset: PagePoint

    public init(pageIndex: Int, point: PagePoint, viewportOffset: PagePoint) {
        self.pageIndex = pageIndex
        self.point = point
        self.viewportOffset = viewportOffset
    }

    public static func capture(
        pageIndex: Int,
        pageOrigin: PagePoint,
        viewportOrigin: PagePoint,
        viewportSize: PagePoint,
        zoom: Double
    ) -> DocumentViewportZoomAnchor {
        let viewportOffset = PagePoint(
            x: viewportSize.x / 2,
            y: viewportSize.y / 2
        )
        return DocumentViewportZoomAnchor(
            pageIndex: pageIndex,
            point: PagePoint(
                x: (viewportOrigin.x + viewportOffset.x - pageOrigin.x) / zoom,
                y: (viewportOrigin.y + viewportOffset.y - pageOrigin.y) / zoom
            ),
            viewportOffset: viewportOffset
        )
    }

    public func restoredViewportOrigin(pageOrigin: PagePoint, zoom: Double) -> PagePoint {
        PagePoint(
            x: pageOrigin.x + point.x * zoom - viewportOffset.x,
            y: pageOrigin.y + point.y * zoom - viewportOffset.y
        )
    }
}
