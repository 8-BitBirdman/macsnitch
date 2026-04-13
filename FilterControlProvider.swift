// NetworkExtension/FilterControlProvider.swift
// NEFilterControlProvider — receives rule updates from the app
// and forwards them into the FilterProvider's cache.
// This runs in the same extension process as FilterProvider.

import NetworkExtension
import OSLog

private let log = Logger(subsystem: "com.macsnitch.extension", category: "FilterControlProvider")

final class FilterControlProvider: NEFilterControlProvider {

    // Shared rule cache — both providers live in the same process so we
    // can use a singleton here.
    private let ruleCache = RuleCache.shared

    // XPC listener so the app can push rule changes into the extension.
    private var xpcListener: NSXPCListener?

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("FilterControlProvider starting")
        startXPCListener()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        xpcListener?.invalidate()
        completionHandler()
    }

    // MARK: - Rule handling

    override func handleRemediation(for flow: NEFilterFlow, completionHandler: @escaping (NEFilterControlVerdict) -> Void) {
        // Called when a previously-dropped flow is re-evaluated after a rule change.
        completionHandler(.allow(withUpdateRules: true))
    }

    override func updateRules(_ rules: [NEFilterRule], completionHandler: @escaping (Error?) -> Void) {
        // Called by the system when NEFilterManager rules change.
        // We manage our own rule cache, so we just acknowledge.
        completionHandler(nil)
    }

    // MARK: - XPC listener (app → extension)

    private func startXPCListener() {
        let listener = NSXPCListener(machServiceName: XPC.machServiceName)
        listener.delegate = self
        listener.resume()
        xpcListener = listener
        log.info("Extension XPC listener started on \(XPC.machServiceName)")
    }
}

// MARK: - NSXPCListenerDelegate

extension FilterControlProvider: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: MacSnitchExtensionXPCProtocol.self)
        conn.exportedObject = ExtensionXPCHandler(cache: ruleCache)
        conn.resume()
        return true
    }
}

// MARK: - XPC Handler (exported to app)

private final class ExtensionXPCHandler: NSObject, MacSnitchExtensionXPCProtocol {
    private let cache: RuleCache
    init(cache: RuleCache) { self.cache = cache }

    func updateRule(ruleData: Data, reply: @escaping (Bool) -> Void) {
        guard let rule = try? JSONDecoder().decode(Rule.self, from: ruleData) else {
            reply(false); return
        }
        cache.insert(rule)
        log.debug("Rule updated: \(rule.id)")
        reply(true)
    }

    func removeRule(ruleID: String, reply: @escaping (Bool) -> Void) {
        guard let id = UUID(uuidString: ruleID) else { reply(false); return }
        cache.remove(id: id)
        log.debug("Rule removed: \(ruleID)")
        reply(true)
    }

    func clearSessionRules(reply: @escaping (Bool) -> Void) {
        cache.clearSession()
        log.info("Session rules cleared")
        reply(true)
    }
}
