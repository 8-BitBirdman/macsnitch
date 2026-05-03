// MacSnitchApp/Services/ExtensionClient.swift
// App-side XPC client that pushes rule changes into the Network Extension's cache.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "ExtensionClient")

final class ExtensionClient: ObservableObject {
    var onReconnect: (() -> Void)?
    private var connection: NSXPCConnection?

    func connect() {
        let conn = NSXPCConnection(machServiceName: XPC.machServiceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: MacSnitchExtensionXPCProtocol.self)
        conn.interruptionHandler = { [weak self] in
            log.warning("Extension XPC connection interrupted")
        }
        conn.invalidationHandler = { [weak self] in
            log.warning("Extension XPC connection invalidated")
            self?.connection = nil
        }
        conn.resume()
        connection = conn
        onReconnect?()
    }

    private var proxy: MacSnitchExtensionXPCProtocol? {
        connection?.remoteObjectProxy as? MacSnitchExtensionXPCProtocol
    }

    private func ensureConnection() -> MacSnitchExtensionXPCProtocol? {
        if connection == nil {
            connect()
        }
        return proxy
    }

    func push(rule: Rule) {
        guard let data = try? JSONEncoder().encode(rule) else { return }
        ensureConnection()?.updateRule(ruleData: data) { ok in
            log.debug("push rule \(rule.id): \(ok)")
        }
    }

    func push(rules: [Rule]) {
        let encoder = JSONEncoder()
        let datas = rules.compactMap { try? encoder.encode($0) }
        guard !datas.isEmpty else { return }
        
        ensureConnection()?.updateRules(ruleDatas: datas) { ok in
            log.info("push \(rules.count) rules: \(ok)")
        }
    }

    func remove(ruleID: UUID) {
        ensureConnection()?.removeRule(ruleID: ruleID.uuidString) { ok in
            log.debug("remove rule \(ruleID): \(ok)")
        }
    }

    func clearSessionRules() {
        ensureConnection()?.clearSessionRules { ok in
            log.debug("clearSessionRules: \(ok)")
        }
    }
}
