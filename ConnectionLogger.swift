// MacSnitchApp/Services/ConnectionLogger.swift
// In-memory + SQLite log of all intercepted connections.
// The XPCServer calls appendEntry() on the main actor.

import Foundation
import Combine

@MainActor
final class ConnectionLogger: ObservableObject {
    @Published private(set) var entries: [ConnectionLogEntry] = []

    private let store: RuleStore
    private let maxMemoryEntries = 1000

    init(store: RuleStore) {
        self.store = store
        loadRecent()
    }

    func appendEntry(_ entry: ConnectionLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxMemoryEntries {
            entries.removeLast(entries.count - maxMemoryEntries)
        }
        store.appendLog(entry)
    }

    func clearAll() {
        entries.removeAll()
        store.clearLog()
    }

    private func loadRecent() {
        entries = store.fetchLog(limit: 500)
    }

    // MARK: - Filtered views

    func entries(for processPath: String) -> [ConnectionLogEntry] {
        entries.filter { $0.connection.processPath == processPath }
    }

    func entries(verdict: Verdict) -> [ConnectionLogEntry] {
        entries.filter { $0.verdict == verdict }
    }
}
