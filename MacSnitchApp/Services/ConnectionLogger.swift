// MacSnitchApp/Services/ConnectionLogger.swift
// In-memory + SQLite log of all intercepted connections.
// The XPCServer calls appendEntry() on the main actor.

import Foundation
import Combine

@MainActor
final class ConnectionLogger: ObservableObject {
    @Published private(set) var entries: [ConnectionLogEntry] = []
    @Published private(set) var processStats: [ProcessStats] = []
    @Published private(set) var destinationStats: [DestinationStats] = []

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
        updateStats()
    }

    func clearAll() {
        entries.removeAll()
        processStats.removeAll()
        destinationStats.removeAll()
        store.clearLog()
    }

    private func loadRecent() {
        entries = store.fetchLog(limit: 500)
        updateStats()
    }

    private func updateStats() {
        // Compute Process Stats
        var pMap: [String: ProcessStats] = [:]
        for e in entries {
            var s = pMap[e.connection.processPath] ?? ProcessStats(
                processName: e.connection.processName,
                processPath: e.connection.processPath,
                allowed: 0, denied: 0, total: 0)
            s.total += 1
            if e.verdict == .allow { s.allowed += 1 } else { s.denied += 1 }
            pMap[e.connection.processPath] = s
        }
        processStats = pMap.values.sorted { $0.total > $1.total }

        // Compute Destination Stats
        var dMap: [String: Int] = [:]
        for e in entries {
            let d = e.connection.displayDestination
            dMap[d, default: 0] += 1
        }
        destinationStats = dMap.map { DestinationStats(hostname: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Filtered views

    func entries(for processPath: String) -> [ConnectionLogEntry] {
        entries.filter { $0.connection.processPath == processPath }
    }

    func entries(verdict: Verdict) -> [ConnectionLogEntry] {
        entries.filter { $0.verdict == verdict }
    }
}
