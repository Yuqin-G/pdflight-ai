import Foundation

/// Process-wide budget for heavy chat views, independent of sessions and tasks.
/// Weak entries cannot keep a closed document (or its background work) alive.
@MainActor
protocol ChatHeavyViewOwner: AnyObject {
    func discardHeavyChatViews()
}

@MainActor
final class ChatHeavyViewCache {
    static let shared = ChatHeavyViewCache()
    private weak var current: (any ChatHeavyViewOwner)?
    private weak var recent: (any ChatHeavyViewOwner)?
    private let idleTimeout: Duration
    private var expirations: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(idleTimeout: Duration = .seconds(30)) {
        self.idleTimeout = idleTimeout
    }

    func activate(_ owner: any ChatHeavyViewOwner) {
        cancelExpiration(for: owner)
        guard current !== owner else { return }
        let previous = current
        let victim = recent
        current = owner
        recent = previous ?? (victim === owner ? nil : victim)
        if let victim, victim !== current, victim !== recent {
            cancelExpiration(for: victim)
            victim.discardHeavyChatViews()
        }
    }

    func deactivate(_ owner: any ChatHeavyViewOwner) {
        // Keep both slots for quick A → B → A switches, then release hidden
        // renderers even when the user never opens a third document.
        guard contains(owner) else { return }
        cancelExpiration(for: owner)
        let identity = ObjectIdentifier(owner)
        let timeout = idleTimeout
        expirations[identity] = Task { @MainActor [weak self, weak owner] in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            guard !Task.isCancelled, let self, let owner else { return }
            self.remove(owner)
        }
    }

    private func cancelExpiration(for owner: any ChatHeavyViewOwner) {
        expirations.removeValue(forKey: ObjectIdentifier(owner))?.cancel()
    }

    func remove(_ owner: any ChatHeavyViewOwner) {
        cancelExpiration(for: owner)
        if current === owner { current = nil }
        if recent === owner { recent = nil }
        owner.discardHeavyChatViews()
    }

    func contains(_ owner: any ChatHeavyViewOwner) -> Bool {
        current === owner || recent === owner
    }

    var residentCount: Int { (current == nil ? 0 : 1) + (recent == nil ? 0 : 1) }
}
