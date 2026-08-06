public struct DocumentViewportBookmark: Codable, Sendable, Equatable {
    public let pageIndex: Int
    public let point: PagePoint

    public init(pageIndex: Int, point: PagePoint) {
        self.pageIndex = pageIndex
        self.point = point
    }

    public static func capture(
        pageIndex: Int,
        pageOrigin: PagePoint,
        viewportOrigin: PagePoint,
        zoom: Double
    ) -> DocumentViewportBookmark {
        DocumentViewportBookmark(
            pageIndex: pageIndex,
            point: PagePoint(
                x: (viewportOrigin.x - pageOrigin.x) / zoom,
                y: max(0, (viewportOrigin.y - pageOrigin.y) / zoom)
            )
        )
    }

    public func restoredViewportOrigin(pageOrigin: PagePoint, zoom: Double) -> PagePoint {
        PagePoint(
            x: pageOrigin.x + point.x * zoom,
            y: pageOrigin.y + point.y * zoom
        )
    }
}
