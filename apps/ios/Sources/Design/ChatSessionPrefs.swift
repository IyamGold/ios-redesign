import SwiftUI

/// Client-side session preferences: pins + ordering, persisted in `UserDefaults`. Server truth is left
/// untouched — this only reorders/annotates what the drawer already shows.
@Observable
@MainActor
final class ChatSessionPrefs {
    static let shared = ChatSessionPrefs()
    private static let pinsKey = "chat.sessions.pinned"

    private(set) var pinned: Set<String>

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: Self.pinsKey) ?? []
        self.pinned = Set(stored)
    }

    func isPinned(_ sessionKey: String) -> Bool {
        self.pinned.contains(sessionKey)
    }

    func togglePin(_ sessionKey: String) {
        if !self.pinned.insert(sessionKey).inserted {
            self.pinned.remove(sessionKey)
        }
        UserDefaults.standard.set(Array(self.pinned), forKey: Self.pinsKey)
    }

    /// Pinned first (keeping the incoming recency order within each group).
    func ordered(_ sessions: [ChatDrawerSession]) -> [ChatDrawerSession] {
        let pinnedRows = sessions.filter { self.pinned.contains($0.id) }
        let rest = sessions.filter { !self.pinned.contains($0.id) }
        return pinnedRows + rest
    }
}
