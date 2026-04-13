// MacSnitchApp/Services/ExtensionClient.swift
// App-side XPC client that pushes rule changes into the Network Extension's cache.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "ExtensionClient")

final class ExtensionClient: ObservableObject {
    private var connection: NSXPCConnection?

    func connect() {
        let conn = NSXPCConnection(machServiceName: XPC.machServiceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: MacSnitchExtensionXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            log.warning("Extension XPC connection invalidated")
            self?.connection = nil
        }
        conn.resume()
        connection = conn
    }

    private var proxy: MacSnitchExtensionXPCProtocol? {
        connection?.remoteObjectProxy as? MacSnitchExtensionXPCProtocol
    }

    func push(rule: Rule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        proxy?.updateRule(ruleData: data) { ok in
            log.debug("push rule \(rule.id): \(ok)")
        }
    }

    func remove(ruleID: UUID) {
        proxy?.removeRule(ruleID: ruleID.uuidString) { ok in
            log.debug("remove rule \(ruleID): \(ok)")
        }
    }

    func clearSessionRules() {
        proxy?.clearSessionRules { ok in
            log.debug("clearSessionRules: \(ok)")
        }
    }
}
