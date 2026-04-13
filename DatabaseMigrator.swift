// MacSnitchApp/Services/DatabaseMigrator.swift
// Manages GRDB schema migrations so the database can evolve across app versions
// without losing existing rules or log entries.

import GRDB
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "Migrations")

enum DatabaseMigrator {

    /// Apply all pending migrations to `db` in order.
    /// Safe to call every launch — already-applied migrations are skipped.
    static func migrate(_ dbQueue: DatabaseQueue) throws {
        var migrator = GRDB.DatabaseMigrator()

        // ── v1: Initial schema ──────────────────────────────────────────────
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "rules", ifNotExists: true) { t in
                t.column("id",          .text).primaryKey()
                t.column("created",     .datetime).notNull()
                t.column("processName", .text).notNull()
                t.column("processPath", .text).notNull()
                t.column("action",      .text).notNull()
                t.column("duration",    .text).notNull()
                t.column("matchJSON",   .text).notNull()
                t.column("isEnabled",   .boolean).notNull().defaults(to: true)
                t.column("notes",       .text).notNull().defaults(to: "")
            }

            try db.create(table: "connection_log", ifNotExists: true) { t in
                t.column("id",                .text).primaryKey()
                t.column("timestamp",         .datetime).notNull()
                t.column("processName",       .text).notNull()
                t.column("processPath",       .text).notNull()
                t.column("destinationAddress",.text).notNull()
                t.column("resolvedHostname",  .text)
                t.column("destinationPort",   .integer).notNull()
                t.column("proto",             .text).notNull()
                t.column("verdict",           .text).notNull()
                t.column("ruleID",            .text)
            }
        }

        // ── v2: Index connection_log for faster queries ─────────────────────
        migrator.registerMigration("v2_log_indexes") { db in
            try db.create(index: "idx_log_timestamp",
                          on: "connection_log",
                          columns: ["timestamp"],
                          ifNotExists: true)
            try db.create(index: "idx_log_processPath",
                          on: "connection_log",
                          columns: ["processPath"],
                          ifNotExists: true)
            try db.create(index: "idx_log_verdict",
                          on: "connection_log",
                          columns: ["verdict"],
                          ifNotExists: true)
        }

        // ── v3: Add sourcePort to connection_log ────────────────────────────
        migrator.registerMigration("v3_log_source_port") { db in
            try db.alter(table: "connection_log") { t in
                t.add(column: "sourcePort", .integer).defaults(to: 0)
                t.add(column: "sourceAddress", .text).defaults(to: "")
            }
        }

        // ── v4: Rule hit counter ─────────────────────────────────────────────
        migrator.registerMigration("v4_rule_hit_count") { db in
            try db.alter(table: "rules") { t in
                t.add(column: "hitCount", .integer).defaults(to: 0)
            }
        }

        // Apply.
        try migrator.migrate(dbQueue)
        log.info("Database migrations complete")
    }
}
