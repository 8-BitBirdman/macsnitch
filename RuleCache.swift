// NetworkExtension/RuleCache.swift
// Thread-safe in-memory rule cache, shared across both NEFilter providers.

import Foundation

// NSLock.withLock shim for Swift < 5.7 compatibility.
private extension NSLock {
    @discardableResult
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock(); defer { unlock() }
        return try body()
    }
}

final class RuleCache {
    static let shared = RuleCache(shared: true)

    private var rules: [Rule] = []
    private let lock = NSLock()

    /// Use `RuleCache.shared` in production. Pass `shared: false` only in tests.
    init(shared: Bool = true) {}

    func insert(_ rule: Rule) {
        lock.withLock {
            // Replace existing rule with same ID if present.
            if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[idx] = rule
            } else {
                rules.append(rule)
            }
        }
    }

    func remove(id: UUID) {
        lock.withLock { rules.removeAll { $0.id == id } }
    }

    func clearSession() {
        lock.withLock { rules.removeAll { $0.duration == .session } }
    }

    /// Returns the first matching verdict and the rule that produced it.
    func verdict(for connection: ConnectionInfo) -> (Verdict, Rule)? {
        lock.withLock {
            for rule in rules where rule.isEnabled {
                guard rule.processPath == connection.processPath || rule.processPath == "*" else {
                    continue
                }
                if matches(rule: rule, connection: connection) {
                    return (rule.action == .allow ? .allow : .deny, rule)
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
                || connection.resolvedHostname == host
        case .destinationPort(let port):
            return connection.destinationPort == port
        case .destinationAndPort(let host, let port):
            return (connection.destinationAddress == host || connection.resolvedHostname == host)
                && connection.destinationPort == port
        }
    }
}
