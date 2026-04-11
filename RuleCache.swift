// NetworkExtension/RuleCache.swift
// Thread-safe in-memory cache of rules for fast flow verdict lookup.

import Foundation

final class RuleCache {
    private var rules: [Rule] = []
    private let lock = NSLock()

    func insert(_ rule: Rule) {
        lock.withLock { rules.append(rule) }
    }

    func remove(id: UUID) {
        lock.withLock { rules.removeAll { $0.id == id } }
    }

    func verdict(for connection: ConnectionInfo) -> Verdict? {
        lock.withLock {
            for rule in rules where rule.processPath == connection.processPath || rule.processPath == "*" {
                if matches(rule: rule, connection: connection) {
                    return rule.action == .allow ? .allow : .deny
                }
            }
            return nil
        }
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
