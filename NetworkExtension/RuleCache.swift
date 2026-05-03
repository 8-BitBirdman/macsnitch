// NetworkExtension/RuleCache.swift
// Thread-safe in-memory rule cache, shared across both NEFilter providers.

import Foundation
import MacSnitchShared

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

    private var rulesByProcess: [String: [Rule]] = [:] // "*" is the key for global rules
    private let lock = NSLock()

    /// Use `RuleCache.shared` in production. Pass `shared: false` only in tests.
    init(shared: Bool = true) {}

    func insert(_ rule: Rule) {
        lock.withLock {
            let path = rule.processPath
            var processRules = rulesByProcess[path] ?? []
            if let idx = processRules.firstIndex(where: { $0.id == rule.id }) {
                processRules[idx] = rule
            } else {
                processRules.append(rule)
            }
            rulesByProcess[path] = processRules
        }
    }

    func remove(id: UUID) {
        lock.withLock {
            for (path, var processRules) in rulesByProcess {
                if let idx = processRules.firstIndex(where: { $0.id == id }) {
                    processRules.remove(at: idx)
                    if processRules.isEmpty {
                        rulesByProcess.removeValue(forKey: path)
                    } else {
                        rulesByProcess[path] = processRules
                    }
                    return
                }
            }
        }
    }

    func clearSession() {
        lock.withLock {
            for path in Array(rulesByProcess.keys) {
                var processRules = rulesByProcess[path] ?? []
                processRules.removeAll { $0.duration == RuleDuration.session }
                if processRules.isEmpty {
                    rulesByProcess.removeValue(forKey: path)
                } else {
                    rulesByProcess[path] = processRules
                }
            }
        }
    }

    /// Returns the first matching verdict and the rule that produced it.
    func verdict(for connection: ConnectionInfo) -> (Verdict, Rule)? {
        lock.withLock {
            // Check process-specific rules first, then global rules ("*").
            let pathsToCheck = [connection.processPath, "*"]
            for path in pathsToCheck {
                guard let processRules = rulesByProcess[path] else { continue }
                for rule in processRules where rule.isEnabled {
                    if matches(rule: rule, connection: connection) {
                        return (rule.action == .allow ? .allow : .deny, rule)
                    }
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
            return hostMatches(pattern: host, connection: connection)
        case .destinationPort(let port):
            return connection.destinationPort == port
        case .destinationAndPort(let host, let port):
            return hostMatches(pattern: host, connection: connection)
                && connection.destinationPort == port
        }
    }

    private func hostMatches(pattern: String, connection: ConnectionInfo) -> Bool {
        let addresses = [connection.destinationAddress, connection.resolvedHostname].compactMap { $0 }
        
        for addr in addresses {
            if addr == pattern { return true }
            
            // Wildcard support: *.example.com
            if pattern.hasPrefix("*.") {
                let suffix = pattern.dropFirst(1) // ".example.com"
                if addr.hasSuffix(suffix) { return true }
                // Also match the domain itself (e.g. *.google.com matches google.com)
                let domainOnly = pattern.dropFirst(2) // "example.com"
                if addr == String(domainOnly) { return true }
            }
        }
        return false
    }
}
