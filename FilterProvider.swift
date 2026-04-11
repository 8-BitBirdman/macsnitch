// NetworkExtension/FilterProvider.swift
// NEFilterDataProvider subclass — the heart of MacSnitch.
// This runs in a system extension process and intercepts every outbound flow.

import NetworkExtension
import OSLog

private let log = Logger(subsystem: "com.macsnitch.extension", category: "FilterProvider")

class FilterProvider: NEFilterDataProvider {

    // In-memory rule cache; populated from the app via XPC.
    private var ruleCache = RuleCache()

    // XPC connection back to the main app for prompting the user.
    private var appConnection: NSXPCConnection?

    // Flows waiting for a verdict from the user, keyed by flow identifier.
    private var pendingFlows: [UUID: NEFilterFlow] = [:]
    private let pendingQueue = DispatchQueue(label: "com.macsnitch.extension.pending")

    // MARK: - Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("MacSnitch filter starting")
        setupXPCConnection()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("MacSnitch filter stopping, reason: \(reason.rawValue)")
        appConnection?.invalidate()
        completionHandler()
    }

    // MARK: - Flow Handling

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let remoteEndpoint = socketFlow.remoteEndpoint as? NWHostEndpoint else {
            // Non-socket flows (e.g. browser content) — allow by default.
            return .allow()
        }

        let connection = buildConnectionInfo(from: socketFlow, remoteEndpoint: remoteEndpoint)

        // 1. Check rule cache first (fast path).
        if let cachedVerdict = ruleCache.verdict(for: connection) {
            log.debug("Cache hit for \(connection.processName): \(cachedVerdict.rawValue)")
            return cachedVerdict == .allow ? .allow() : .drop()
        }

        // 2. No cached rule — pause the flow and ask the user.
        let flowID = UUID()
        pendingQueue.sync { pendingFlows[flowID] = flow }

        promptUser(connection: connection, flowID: flowID)

        // Return .pause() to hold the flow open while we wait.
        return .pause()
    }

    // MARK: - XPC Setup

    private func setupXPCConnection() {
        let connection = NSXPCConnection(machServiceName: XPC.appMachServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: MacSnitchAppXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            log.warning("XPC connection to app invalidated — will reconnect on next flow")
            self?.appConnection = nil
        }
        connection.resume()
        appConnection = connection
    }

    // MARK: - User Prompting

    private func promptUser(connection: ConnectionInfo, flowID: UUID) {
        guard let proxy = appConnection?.remoteObjectProxy as? MacSnitchAppXPCProtocol else {
            log.error("No XPC connection to app — defaulting to allow for \(connection.processName)")
            resumeFlow(flowID: flowID, verdict: .allow)
            return
        }

        guard let data = try? JSONEncoder().encode(connection) else {
            log.error("Failed to encode ConnectionInfo")
            resumeFlow(flowID: flowID, verdict: .allow)
            return
        }

        proxy.promptForVerdict(connectionData: data) { [weak self] replyData in
            guard let self else { return }

            struct VerdictReply: Decodable {
                let verdict: Verdict
                let rule: Rule?
            }

            if let reply = try? JSONDecoder().decode(VerdictReply.self, from: replyData) {
                // Cache the rule if the user chose "always".
                if let rule = reply.rule, rule.duration != .once {
                    self.ruleCache.insert(rule)
                }
                self.resumeFlow(flowID: flowID, verdict: reply.verdict)
            } else {
                // Malformed reply — fail open (allow).
                self.resumeFlow(flowID: flowID, verdict: .allow)
            }
        }
    }

    private func resumeFlow(flowID: UUID, verdict: Verdict) {
        pendingQueue.sync {
            guard let flow = pendingFlows.removeValue(forKey: flowID) else { return }
            let neVerdict: NEFilterDataVerdict = verdict == .allow ? .allow(withUpdateRules: false) : .drop()
            self.resumeFlow(flow, withVerdict: neVerdict)
        }
    }

    // MARK: - Connection Info

    private func buildConnectionInfo(from flow: NEFilterSocketFlow, remoteEndpoint: NWHostEndpoint) -> ConnectionInfo {
        let sourceEndpoint = flow.localEndpoint as? NWHostEndpoint
        let pid = flow.sourceAppAuditToken.map { ProcessInfo.pid(from: $0) } ?? -1
        let processPath = flow.sourceAppSigningIdentifier ?? "unknown"
        let processName = URL(fileURLWithPath: processPath).lastPathComponent

        return ConnectionInfo(
            pid: pid,
            processName: processName.isEmpty ? processPath : processName,
            processPath: processPath,
            sourceAddress: sourceEndpoint?.hostname ?? "0.0.0.0",
            sourcePort: UInt16(sourceEndpoint?.port ?? "0") ?? 0,
            destinationAddress: remoteEndpoint.hostname,
            destinationPort: UInt16(remoteEndpoint.port) ?? 0,
            protocol: flow.socketType == SOCK_DGRAM ? .udp : .tcp
        )
    }
}

// MARK: - ProcessInfo helper

private extension ProcessInfo {
    static func pid(from auditToken: Data) -> Int32 {
        // audit_token_t is a 32-byte opaque struct; PID is at bytes 20–23.
        guard auditToken.count >= 24 else { return -1 }
        return auditToken.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 20, as: Int32.self)
        }
    }
}
