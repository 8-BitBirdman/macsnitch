// MacSnitchApp/Services/RuleStore.swift
// Persistent rule storage backed by SQLite via GRDB.
// Add GRDB.swift via SPM: https://github.com/groue/GRDB.swift (~> 6.0)

import Foundation
import GRDB
import Combine
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "RuleStore")

// MARK: - Database Record

/// GRDB-compatible wrapper around Rule for table persistence.
private struct RuleRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "rules"

    var id: String
    var created: Date
    var processName: String
    var processPath: String
    var action: String
    var duration: String
    var matchJSON: String
    var isEnabled: Bool
    var notes: String
    var hitCount: Int       // added in migration v4

    init(rule: Rule) throws {
        id = rule.id.uuidString
        created = rule.created
        processName = rule.processName
        processPath = rule.processPath
        action = rule.action.rawValue
        duration = rule.duration.rawValue
        let matchData = try JSONEncoder().encode(rule.match)
        matchJSON = String(data: matchData, encoding: .utf8) ?? "{}"
        isEnabled = rule.isEnabled
        notes = rule.notes
        hitCount = rule.hitCount
    }

    func toRule() throws -> Rule {
        guard
            let uuid = UUID(uuidString: id),
            let ruleAction = RuleAction(rawValue: action),
            let ruleDuration = RuleDuration(rawValue: duration),
            let matchData = matchJSON.data(using: .utf8)
        else { throw RuleStoreError.corruptRecord }
        let match = try JSONDecoder().decode(RuleMatch.self, from: matchData)
        return Rule(id: uuid, created: created,
                    processName: processName, processPath: processPath,
                    action: ruleAction, duration: ruleDuration, match: match,
                    isEnabled: isEnabled, hitCount: hitCount, notes: notes)
    }
}

// MARK: - Log Record

private struct LogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "connection_log"

    var id: String
    var timestamp: Date
    var processName: String
    var processPath: String
    var destinationAddress: String
    var resolvedHostname: String?
    var destinationPort: Int
    var proto: String
    var verdict: String
    var ruleID: String?
    var sourcePort: Int      // added in migration v3
    var sourceAddress: String // added in migration v3

    init(entry: ConnectionLogEntry) {
        id = entry.id.uuidString
        timestamp = entry.timestamp
        processName = entry.connection.processName
        processPath = entry.connection.processPath
        destinationAddress = entry.connection.destinationAddress
        resolvedHostname = entry.connection.resolvedHostname
        destinationPort = Int(entry.connection.destinationPort)
        proto = entry.connection.protocol.rawValue
        verdict = entry.verdict.rawValue
        ruleID = entry.ruleID?.uuidString
        sourcePort = Int(entry.connection.sourcePort)
        sourceAddress = entry.connection.sourceAddress
    }

    func toEntry() -> ConnectionLogEntry? {
        guard let uuid = UUID(uuidString: id),
              let v = Verdict(rawValue: verdict),
              let p = TransportProtocol(rawValue: proto) else { return nil }

        let conn = ConnectionInfo(
            pid: -1, processName: processName, processPath: processPath,
            sourceAddress: sourceAddress, sourcePort: UInt16(sourcePort),
            destinationAddress: destinationAddress,
            destinationPort: UInt16(destinationPort),
            protocol: p, timestamp: timestamp,
            resolvedHostname: resolvedHostname)

        return ConnectionLogEntry(id: uuid, connection: conn,
                                  verdict: v, ruleID: UUID(uuidString: ruleID ?? ""),
                                  timestamp: timestamp)
    }
}

// MARK: - Error

enum RuleStoreError: Error { case corruptRecord }

// MARK: - RuleStore

@MainActor
final class RuleStore: ObservableObject {
    @Published private(set) var rules: [Rule] = []

    private var db: DatabaseQueue!
    private var sessionRules: [Rule] = []   // duration == .session, not in DB

    init() {
        setupDatabase()
        loadRules()
    }

    // MARK: - Setup

    private func setupDatabase() {
        let dir = appSupportDir()
        let path = dir.appendingPathComponent("macsnitch.sqlite").path
        do {
            db = try DatabaseQueue(path: path)
            try AppDatabaseMigrator.migrate(db)
            log.info("Database ready at \(path)")
        } catch {
            log.error("Failed to open/migrate database: \(error)")
        }
    }

    private func loadRules() {
        do {
            let records = try db.read { db in
                try RuleRecord.fetchAll(db)
            }
            rules = try records.map { try $0.toRule() }
            log.info("Loaded \(self.rules.count) rules")
            
            if rules.isEmpty {
                prepopulateSystemRules()
            }
        } catch {
            log.error("Failed to load rules: \(error)")
        }
    }

    private func prepopulateSystemRules() {
        log.info("Pre-populating default system rules...")
        let defaults: [(name: String, path: String)] = [
            ("trustd", "/usr/libexec/trustd"),
            ("ocspd", "/usr/libexec/ocspd"),
            ("mDNSResponder", "/usr/sbin/mDNSResponder"),
            ("cloudd", "/System/Library/PrivateFrameworks/CloudKitDaemon.framework/Support/cloudd"),
            ("softwareupdated", "/System/Library/CoreServices/Software Update.app/Contents/Resources/softwareupdated"),
            ("nsurlsessiond", "/usr/libexec/nsurlsessiond"),
            ("com.apple.Safari", "/Applications/Safari.app/Contents/MacOS/Safari")
        ]
        
        for item in defaults {
            if FileManager.default.fileExists(atPath: item.path) {
                let rule = Rule(
                    processName: item.name,
                    processPath: item.path,
                    action: .allow,
                    duration: .permanent,
                    match: .process,
                    notes: "Default system rule")
                add(rule)
            }
        }
    }

    // MARK: - Public API

    func add(_ rule: Rule) {
        if rule.duration == .session {
            sessionRules.append(rule)
            rules.append(rule)
            return
        }
        guard rule.duration == .permanent else { return }
        do {
            let record = try RuleRecord(rule: rule)
            try db.write { db in try record.insert(db) }
            rules.append(rule)
        } catch { log.error("Failed to insert rule: \(error)") }
    }

    func add(_ rules: [Rule]) {
        do {
            try db.write { db in
                for rule in rules {
                    guard rule.duration == .permanent else { continue }
                    let record = try RuleRecord(rule: rule)
                    try record.insert(db)
                }
            }
            self.rules.append(contentsOf: rules)
        } catch { log.error("Failed bulk insert: \(error)") }
    }

    func update(_ rule: Rule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        }
        guard rule.duration == .permanent else { return }
        do {
            let record = try RuleRecord(rule: rule)
            try db.write { db in try record.update(db) }
        } catch { log.error("Failed to update rule: \(error)") }
    }

    func remove(id: UUID) {
        rules.removeAll { $0.id == id }
        sessionRules.removeAll { $0.id == id }
        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM rules WHERE id = ?", arguments: [id.uuidString])
            }
        } catch { log.error("Failed to delete rule: \(error)") }
    }

    func remove(ids: [UUID]) {
        let stringIDs = ids.map { $0.uuidString }
        rules.removeAll { ids.contains($0.id) }
        sessionRules.removeAll { ids.contains($0.id) }
        do {
            try db.write { db in
                let placeholders = stringIDs.map { _ in "?" }.joined(separator: ",")
                try db.execute(sql: "DELETE FROM rules WHERE id IN (\(placeholders))", arguments: StatementArguments(stringIDs))
            }
        } catch { log.error("Failed bulk delete: \(error)") }
    }

    func clearSessionRules() {
        sessionRules.forEach { rule in rules.removeAll { $0.id == rule.id } }
        sessionRules.removeAll()
    }

    func verdict(for connection: ConnectionInfo) -> (action: RuleAction, rule: Rule)? {
        for rule in rules where rule.isEnabled {
            guard rule.processPath == connection.processPath || rule.processPath == "*" else { continue }
            if ruleMatches(rule: rule, connection: connection) {
                return (rule.action, rule)
            }
        }
        return nil
    }

    private func ruleMatches(rule: Rule, connection: ConnectionInfo) -> Bool {
        switch rule.match {
        case .process: return true
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
            if pattern.hasPrefix("*.") {
                let suffix = pattern.dropFirst(1)
                if addr.hasSuffix(suffix) { return true }
                let domainOnly = pattern.dropFirst(2)
                if addr == String(domainOnly) { return true }
            }
        }
        return false
    }

    // MARK: - Log

    func appendLog(_ entry: ConnectionLogEntry) {
        let record = LogRecord(entry: entry)
        Task.detached(priority: .background) {
            do {
                try self.db.write { db in
                    try record.insert(db)
                    // Increment hitCount if a rule matched
                    if let rid = entry.ruleID?.uuidString {
                        try db.execute(sql: "UPDATE rules SET hitCount = hitCount + 1 WHERE id = ?", arguments: [rid])
                    }
                }
            } catch {
                // Background logging errors are non-critical
            }
        }
    }

    func fetchLog(limit: Int = 500) -> [ConnectionLogEntry] {
        do {
            let records = try db.read { db in
                try LogRecord.order(Column("timestamp").desc).limit(limit).fetchAll(db)
            }
            return records.compactMap { $0.toEntry() }
        } catch { return [] }
    }

    func clearLog() {
        do {
            try db.write { db in try db.execute(sql: "DELETE FROM connection_log") }
        } catch { log.error("Failed to clear log: \(error)") }
    }

    // MARK: - Import / Export

    func exportRules() throws -> Data {
        let exportable = rules.filter { $0.duration == .permanent }
        return try JSONEncoder().encode(exportable)
    }

    func importRules(from data: Data) throws -> [Rule] {
        let imported = try JSONDecoder().decode([Rule].self, from: data)
        var added: [Rule] = []
        for var rule in imported {
            // Avoid duplicates by processPath+match combination.
            let isDuplicate = rules.contains {
                $0.processPath == rule.processPath && $0.match == rule.match
            }
            if !isDuplicate {
                let newRule = Rule(processName: rule.processName, processPath: rule.processPath,
                            action: rule.action, duration: .permanent, match: rule.match,
                            isEnabled: rule.isEnabled, notes: rule.notes)
                add(newRule)
                added.append(newRule)
            }
        }
        return added
    }

    // MARK: - Helpers

    private func appSupportDir() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MacSnitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
