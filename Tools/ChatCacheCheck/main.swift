import Foundation

@MainActor
private final class Owner: ChatHeavyViewOwner {
    var evictions = 0
    func discardHeavyChatViews() { evictions += 1 }
}

@main
struct ChatCacheCheck {
    @MainActor static func main() async throws {
        let cache = ChatHeavyViewCache()
        let a = Owner(), b = Owner(), c = Owner()
        cache.activate(a)
        cache.deactivate(a); cache.activate(b)
        cache.deactivate(b); cache.activate(a)
        precondition(a.evictions == 0 && b.evictions == 0)
        cache.deactivate(a); cache.activate(b)
        cache.deactivate(b); cache.activate(c)
        precondition(a.evictions == 1 && cache.contains(b) && cache.contains(c))
        cache.remove(c)
        precondition(cache.residentCount == 1 && c.evictions == 1)
        cache.activate(b)
        precondition(cache.residentCount == 1 && b.evictions == 0)
        cache.remove(b)
        precondition(cache.residentCount == 0)
        weak var released: Owner?
        do {
            let owner = Owner()
            released = owner
            cache.activate(owner)
        }
        precondition(released == nil && cache.residentCount == 0)

        let owners = (0..<17).map { _ in Owner() }
        var expected: [Int] = []
        for step in 0..<1000 {
            let index = (step * 7 + step / 5) % owners.count
            if let active = expected.first { cache.deactivate(owners[active]) }
            cache.activate(owners[index])
            expected.removeAll { $0 == index }
            expected.insert(index, at: 0)
            expected = Array(expected.prefix(2))
            precondition(cache.residentCount == expected.count)
            for candidate in owners.indices {
                precondition(cache.contains(owners[candidate]) == expected.contains(candidate))
            }
        }
        let expiring = ChatHeavyViewCache(idleTimeout: .milliseconds(20))
        let warm = Owner(), visible = Owner()
        expiring.activate(warm)
        expiring.deactivate(warm)
        expiring.activate(visible)
        try await Task.sleep(for: .milliseconds(100))
        precondition(warm.evictions == 1 && !expiring.contains(warm))
        precondition(visible.evictions == 0 && expiring.residentCount == 1)
        expiring.deactivate(visible)
        expiring.activate(visible)
        try await Task.sleep(for: .milliseconds(100))
        precondition(visible.evictions == 0 && expiring.contains(visible))
        expiring.remove(visible)
        print("PASS: current + recent cache; A/B reuse; third-owner eviction; close; weak ownership; 1000 selections; idle expiry; reactivation cancels expiry")
    }
}
