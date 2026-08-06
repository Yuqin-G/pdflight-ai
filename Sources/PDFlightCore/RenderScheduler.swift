import Foundation

public struct PageRenderRequest: Hashable, Sendable {
    public let pageIndex: Int
    public let scale: Double

    public init(pageIndex: Int, scale: Double) {
        self.pageIndex = pageIndex
        self.scale = scale
    }
}

public struct RenderedPage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixels: Data

    public init(width: Int, height: Int, bytesPerRow: Int, pixels: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.pixels = pixels
    }

    public var byteCount: Int { pixels.count }
}

public actor RenderScheduler {
    public typealias RenderOperation = @Sendable (PageRenderRequest) async throws -> RenderedPage

    private let operation: RenderOperation
    private let byteLimit: Int
    private var cachedPages: [PageRenderRequest: RenderedPage] = [:]
    private var recency: [PageRenderRequest] = []
    private var cachedByteCount = 0
    private var inFlight: [PageRenderRequest: Task<RenderedPage, Error>] = [:]

    public init(byteLimit: Int, operation: @escaping RenderOperation) {
        self.byteLimit = max(0, byteLimit)
        self.operation = operation
    }

    public func render(_ request: PageRenderRequest) async throws -> RenderedPage {
        if let cached = cachedPages[request] {
            touch(request)
            return cached
        }
        if let existing = inFlight[request] {
            return try await existing.value
        }

        let task = Task { try await operation(request) }
        inFlight[request] = task
        do {
            let rendered = try await task.value
            inFlight[request] = nil
            insert(rendered, for: request)
            return rendered
        } catch {
            inFlight[request] = nil
            throw error
        }
    }

    public func invalidate(pageIndex: Int) {
        let keys = cachedPages.keys.filter { $0.pageIndex == pageIndex }
        for key in keys {
            if let removed = cachedPages.removeValue(forKey: key) {
                cachedByteCount -= removed.byteCount
            }
            recency.removeAll { $0 == key }
        }
    }

    public func removeAll() {
        cachedPages.removeAll(keepingCapacity: false)
        recency.removeAll(keepingCapacity: false)
        cachedByteCount = 0
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll(keepingCapacity: false)
    }

    private func insert(_ page: RenderedPage, for request: PageRenderRequest) {
        guard page.byteCount <= byteLimit else { return }

        if let previous = cachedPages.updateValue(page, forKey: request) {
            cachedByteCount -= previous.byteCount
        }
        cachedByteCount += page.byteCount
        touch(request)

        while cachedByteCount > byteLimit, let oldest = recency.first {
            recency.removeFirst()
            if let removed = cachedPages.removeValue(forKey: oldest) {
                cachedByteCount -= removed.byteCount
            }
        }
    }

    private func touch(_ request: PageRenderRequest) {
        recency.removeAll { $0 == request }
        recency.append(request)
    }
}
