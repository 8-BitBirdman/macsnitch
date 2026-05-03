// MacSnitchApp/Models/AppStatsModel.swift
// Aggregates connection log entries into per-process and per-destination statistics.
// Subscribed to ConnectionLogger.$entries via Combine; debounced to avoid
// recomputing on every single new entry under heavy traffic.

import Foundation
import Combine

// MARK: - Per-process stats

struct ProcessStats: Identifiable, Comparable {
    let id: String          // processPath used as stable identifier
    let processName: String
    let processPath: String
    let allowed: Int
    let denied: Int

    var total: Int { allowed + denied }
    var denyRate: Double { total == 0 ? 0 : Double(denied) / Double(total) }

    static func < (lhs: ProcessStats, rhs: ProcessStats) -> Bool {
        lhs.total > rhs.total   // sort descending by total connections
    }
}

// MARK: - Per-destination stats

struct DestinationStats: Identifiable, Comparable {
    let id: String          // host used as stable identifier
    let host: String
    let count: Int

    static func < (lhs: DestinationStats, rhs: DestinationStats) -> Bool {
        lhs.count > rhs.count
    }
}

// MARK: - AppStatsModel

@MainActor
final class AppStatsModel: ObservableObject {
    @Published private(set) var processStats: [ProcessStats] = []
    @Published private(set) var topDestinations: [DestinationStats] = []

    private var cancellable: AnyCancellable?

    init(logger: ConnectionLogger) {
        cancellable = logger.$entries
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] entries in
                self?.recompute(entries: entries)
            }
    }

    // MARK: - Computation

    private func recompute(entries: [ConnectionLogEntry]) {
        var byProcess: [String: (name: String, allowed: Int, denied: Int)] = [:]
        var byDestination: [String: Int] = [:]

        for entry in entries {
            let path = entry.connection.processPath
            var ps = byProcess[path] ?? (name: entry.connection.processName, allowed: 0, denied: 0)
            if entry.verdict == .allow { ps.allowed += 1 } else { ps.denied += 1 }
            byProcess[path] = ps

            let dest = entry.connection.displayDestination
            byDestination[dest, default: 0] += 1
        }

        processStats = byProcess
            .map { path, s in
                ProcessStats(id: path, processName: s.name, processPath: path,
                             allowed: s.allowed, denied: s.denied)
            }
            .sorted()
            .prefix(50)
            .map { $0 }

        topDestinations = byDestination
            .map { DestinationStats(id: $0.key, host: $0.key, count: $0.value) }
            .sorted()
            .prefix(20)
            .map { $0 }
    }
}
