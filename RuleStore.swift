// MacSnitchApp/Services/RuleStore.swift
// Persistent rule storage backed by SQLite.
// Uses GRDB (https://github.com/groue/GRDB.swift) — add via SPM.

import Foundation
import Combine
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "RuleStore")

// MARK: - RuleStore

/// Observable store for firewall rules. Persists to SQLite via GRDB.
/// Add GRDB.swift via SPM: https://github.com/groue/GRDB.swift
@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var rules: [Rule] = []

    // TODO: Replace with GRDB DatabaseQueue once SPM dependency is added.
    // For now, uses simple JSON file persistence as a placeholder.
    private let storageURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MacSnitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        storageURL = dir.appendingPathComponent("rules.json")
        load()
    }

    // MARK: - Public API

    func add(_ rule: Rule) {
        rules.append(rule)
        save()
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        save()
    }

    func update(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
            save()
        }
    }

    /// Finds the first matching rule for a given connection.
    func verdict(for connection: ConnectionInfo) -> (action: RuleAction, rule: Rule)? {
        for rule in rules where rule.processPath == connection.processPath || rule.processPath == "*" {
            if matches(rule: rule, connection: connection) {
                return (rule.action, rule)
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([Rule].self, from: data) else {
            log.info("No existing rules found, starting fresh")
            return
        }
        rules = loaded.filter { $0.duration == .permanent }
        log.info("Loaded \(self.rules.count) rules from disk")
    }

    private func save() {
        let permanent = rules.filter { $0.duration == .permanent }
        guard let data = try? JSONEncoder().encode(permanent) else {
            log.error("Failed to encode rules")
            return
        }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func matches(rule: Rule, connection: ConnectionInfo) -> Bool {
        switch rule.match {
        case .process:
            return true
        case .destination(let host):
            return connection.destinationAddress == host
        case .destinationPort(let port):
            return connection.destinationPort == port
        case .destinationAndPort(let host, let port):
            return connection.destinationAddress == host && connection.destinationPort == port
        }
    }
}
