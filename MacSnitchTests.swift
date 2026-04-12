// Tests/MacSnitchTests.swift
// Full unit test suite for MacSnitch shared types and extension logic.

import XCTest
@testable import MacSnitchShared

// MARK: - Helpers

private func conn(
    process: String = "/usr/bin/curl",
    host: String    = "example.com",
    port: UInt16    = 443,
    resolved: String? = nil
) -> ConnectionInfo {
    var c = ConnectionInfo(
        pid: 1,
        processName: URL(fileURLWithPath: process).lastPathComponent,
        processPath: process,
        sourceAddress: "127.0.0.1", sourcePort: 12345,
        destinationAddress: host, destinationPort: port,
        protocol: .tcp)
    c.resolvedHostname = resolved
    return c
}

private func rule(
    process: String   = "/usr/bin/curl",
    action: RuleAction = .allow,
    duration: RuleDuration = .permanent,
    match: RuleMatch  = .process,
    enabled: Bool     = true
) -> Rule {
    Rule(processName: URL(fileURLWithPath: process).lastPathComponent,
         processPath: process,
         action: action, duration: duration, match: match,
         isEnabled: enabled)
}

/// Mirror of RuleCache.verdict logic for unit testing without the live singleton.
private func applies(_ rule: Rule, to connection: ConnectionInfo) -> Bool {
    guard rule.isEnabled else { return false }
    guard rule.processPath == connection.processPath || rule.processPath == "*" else { return false }
    switch rule.match {
    case .process:
        return true
    case .destination(let h):
        return connection.destinationAddress == h || connection.resolvedHostname == h
    case .destinationPort(let p):
        return connection.destinationPort == p
    case .destinationAndPort(let h, let p):
        return (connection.destinationAddress == h || connection.resolvedHostname == h)
            && connection.destinationPort == p
    }
}

// MARK: - RuleMatch Tests

final class RuleMatchTests: XCTestCase {

    func test_processMatch_matchesAnyDestination() {
        XCTAssertTrue(applies(rule(match: .process), to: conn()))
        XCTAssertTrue(applies(rule(match: .process), to: conn(host: "other.com", port: 80)))
    }

    func test_destinationMatch_byIP() {
        let r = rule(match: .destination(host: "1.2.3.4"))
        XCTAssertTrue(applies(r,  to: conn(host: "1.2.3.4")))
        XCTAssertFalse(applies(r, to: conn(host: "5.6.7.8")))
    }

    func test_destinationMatch_byResolvedHostname() {
        let r = rule(match: .destination(host: "api.github.com"))
        // Raw IP doesn't match the name...
        XCTAssertFalse(applies(r, to: conn(host: "140.82.112.6")))
        // ...but once resolved it does.
        XCTAssertTrue(applies(r,  to: conn(host: "140.82.112.6", resolved: "api.github.com")))
    }

    func test_portMatch_correctPort() {
        let r = rule(match: .destinationPort(port: 443))
        XCTAssertTrue(applies(r,  to: conn(port: 443)))
        XCTAssertFalse(applies(r, to: conn(port: 80)))
    }

    func test_exactMatch_bothMustMatch() {
        let r = rule(match: .destinationAndPort(host: "evil.com", port: 4444))
        XCTAssertTrue(applies(r,  to: conn(host: "evil.com", port: 4444)))
        XCTAssertFalse(applies(r, to: conn(host: "evil.com", port: 80)))   // wrong port
        XCTAssertFalse(applies(r, to: conn(host: "safe.com", port: 4444))) // wrong host
    }

    func test_exactMatch_resolvedHostname() {
        let r = rule(match: .destinationAndPort(host: "api.github.com", port: 443))
        let c = conn(host: "140.82.112.6", port: 443, resolved: "api.github.com")
        XCTAssertTrue(applies(r, to: c))
    }

    func test_wildcardProcess_matchesAnyApp() {
        let r = Rule(processName: "*", processPath: "*",
                     action: .deny, duration: .permanent,
                     match: .destination(host: "ads.com"))
        XCTAssertTrue(applies(r,  to: conn(process: "/Applications/Safari.app", host: "ads.com")))
        XCTAssertTrue(applies(r,  to: conn(process: "/usr/bin/curl",            host: "ads.com")))
        XCTAssertFalse(applies(r, to: conn(process: "/usr/bin/curl",            host: "safe.com")))
    }

    func test_disabledRule_neverMatches() {
        let r = rule(match: .process, enabled: false)
        XCTAssertFalse(applies(r, to: conn()))
    }

    func test_processPathMismatch_doesNotMatch() {
        let r = rule(process: "/usr/bin/curl", match: .process)
        XCTAssertFalse(applies(r, to: conn(process: "/usr/bin/wget")))
    }
}

// MARK: - RuleCache Tests

final class RuleCacheTests: XCTestCase {

    func test_insert_then_verdict_hit() {
        let cache = freshCache()
        let r = rule(match: .process)
        cache.insert(r)
        let result = cache.verdict(for: conn())
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.0, .allow)
        XCTAssertEqual(result?.1.id, r.id)
    }

    func test_empty_cache_miss() {
        XCTAssertNil(freshCache().verdict(for: conn()))
    }

    func test_remove_clears_entry() {
        let cache = freshCache()
        let r = rule(match: .process)
        cache.insert(r)
        cache.remove(id: r.id)
        XCTAssertNil(cache.verdict(for: conn()))
    }

    func test_update_replaces_existing() {
        let cache = freshCache()
        var r = rule(action: .allow, match: .process)
        cache.insert(r)
        r = Rule(id: r.id, created: r.created,
                 processName: r.processName, processPath: r.processPath,
                 action: .deny, duration: r.duration, match: r.match)
        cache.insert(r)   // same id — should replace
        let result = cache.verdict(for: conn())
        XCTAssertEqual(result?.0, .deny)
    }

    func test_clearSession_keepsPermament() {
        let cache = freshCache()
        let session   = rule(action: .deny,  duration: .session,   match: .process)
        let permanent = rule(action: .allow, duration: .permanent,
                             match: .destination(host: "safe.com"))
        cache.insert(session)
        cache.insert(permanent)
        cache.clearSession()

        // Permanent rule survives.
        XCTAssertNotNil(cache.verdict(for: conn(host: "safe.com")))
        // Session (process-level) rule is gone — conn to other host should miss.
        XCTAssertNil(cache.verdict(for: conn(host: "other.com")))
    }

    func test_disabledRule_notReturned() {
        let cache = freshCache()
        cache.insert(rule(match: .process, enabled: false))
        XCTAssertNil(cache.verdict(for: conn()))
    }

    func test_concurrent_insert_and_verdict() {
        // Smoke test: should not crash under concurrent access.
        let cache = freshCache()
        let q = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        let exp = expectation(description: "concurrent ops")
        exp.expectedFulfillmentCount = 200

        for i in 0..<100 {
            q.async {
                cache.insert(rule(match: .destinationPort(port: UInt16(i % 1000 + 1))))
                exp.fulfill()
            }
            q.async {
                _ = cache.verdict(for: conn())
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5)
    }
}

// MARK: - RuleMatch Codable Tests

final class RuleMatchCodableTests: XCTestCase {

    private func roundTrip(_ match: RuleMatch) throws -> RuleMatch {
        let data = try JSONEncoder().encode(match)
        return try JSONDecoder().decode(RuleMatch.self, from: data)
    }

    func test_process_roundTrip() throws {
        XCTAssertEqual(try roundTrip(.process), .process)
    }

    func test_destination_roundTrip() throws {
        XCTAssertEqual(try roundTrip(.destination(host: "api.github.com")),
                       .destination(host: "api.github.com"))
    }

    func test_destinationPort_roundTrip() throws {
        XCTAssertEqual(try roundTrip(.destinationPort(port: 8080)),
                       .destinationPort(port: 8080))
    }

    func test_destinationAndPort_roundTrip() throws {
        XCTAssertEqual(try roundTrip(.destinationAndPort(host: "evil.com", port: 4444)),
                       .destinationAndPort(host: "evil.com", port: 4444))
    }

    func test_rule_fullRoundTrip() throws {
        let original = Rule(
            processName: "curl", processPath: "/usr/bin/curl",
            action: .deny, duration: .session,
            match: .destinationAndPort(host: "bad.com", port: 1234),
            isEnabled: false, notes: "test note")
        let data    = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Rule.self, from: data)

        XCTAssertEqual(original.id,          decoded.id)
        XCTAssertEqual(original.processPath,  decoded.processPath)
        XCTAssertEqual(original.action,       decoded.action)
        XCTAssertEqual(original.duration,     decoded.duration)
        XCTAssertEqual(original.match,        decoded.match)
        XCTAssertEqual(original.isEnabled,    decoded.isEnabled)
        XCTAssertEqual(original.notes,        decoded.notes)
    }
}

// MARK: - Rule Array Export/Import

final class RuleImportExportTests: XCTestCase {

    func test_exportImport_preservesAllFields() throws {
        let rules = [
            Rule(processName: "curl", processPath: "/usr/bin/curl",
                 action: .allow, duration: .permanent, match: .process),
            Rule(processName: "Safari", processPath: "/Applications/Safari.app",
                 action: .deny, duration: .permanent,
                 match: .destination(host: "ads.doubleclick.net"),
                 notes: "block ads"),
        ]
        let data    = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([Rule].self, from: data)
        XCTAssertEqual(rules.count, decoded.count)
        for (a, b) in zip(rules, decoded) {
            XCTAssertEqual(a.id,           b.id)
            XCTAssertEqual(a.action,       b.action)
            XCTAssertEqual(a.match,        b.match)
            XCTAssertEqual(a.notes,        b.notes)
        }
    }
}

// MARK: - ConnectionInfo Tests

final class ConnectionInfoTests: XCTestCase {

    func test_displayDestination_prefersHostname() {
        var c = conn(host: "140.82.112.6")
        c.resolvedHostname = "api.github.com"
        XCTAssertEqual(c.displayDestination, "api.github.com")
    }

    func test_displayDestination_fallsBackToIP() {
        XCTAssertEqual(conn(host: "1.2.3.4").displayDestination, "1.2.3.4")
    }

    func test_connectionInfo_codable() throws {
        let original = conn(host: "1.2.3.4", port: 443, resolved: "example.com")
        let data     = try JSONEncoder().encode(original)
        let decoded  = try JSONDecoder().decode(ConnectionInfo.self, from: data)
        XCTAssertEqual(original.id,                  decoded.id)
        XCTAssertEqual(original.destinationAddress,  decoded.destinationAddress)
        XCTAssertEqual(original.resolvedHostname,    decoded.resolvedHostname)
        XCTAssertEqual(original.destinationPort,     decoded.destinationPort)
    }
}

// MARK: - VerdictReply Tests

final class VerdictReplyTests: XCTestCase {

    func test_replyWithRule_roundTrip() throws {
        let r     = rule(action: .deny, match: .process)
        let reply = VerdictReply(verdict: .deny, rule: r)
        let data  = try JSONEncoder().encode(reply)
        let back  = try JSONDecoder().decode(VerdictReply.self, from: data)
        XCTAssertEqual(back.verdict,   .deny)
        XCTAssertEqual(back.rule?.id,  r.id)
    }

    func test_replyWithoutRule_roundTrip() throws {
        let reply = VerdictReply(verdict: .allow, rule: nil)
        let data  = try JSONEncoder().encode(reply)
        let back  = try JSONDecoder().decode(VerdictReply.self, from: data)
        XCTAssertEqual(back.verdict, .allow)
        XCTAssertNil(back.rule)
    }
}

// MARK: - RuleCache test factory

extension RuleCacheTests {
    private func freshCache() -> RuleCache { RuleCache(shared: false) }
}
