// NetworkExtension/FilterProvider.swift
// NEFilterDataProvider — intercepts every outbound TCP/UDP flow.

import NetworkExtension
import OSLog
import Network

private let log = Logger(subsystem: "com.macsnitch.extension", category: "FilterProvider")

final class FilterProvider: NEFilterDataProvider {

    private let ruleCache = RuleCache.shared   // shared with FilterControlProvider
    private let dnsResolver = DNSResolver()
    private var appConnection: NSXPCConnection?

    // Flows paused waiting for a user verdict, keyed by a local UUID.
    private var pendingFlows: [UUID: NEFilterFlow] = [:]
    private let pendingQueue = DispatchQueue(label: "com.macsnitch.pending", attributes: .concurrent)

    // MARK: - Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("MacSnitch extension starting")
        connectToApp()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        log.info("MacSnitch extension stopping: \(reason.rawValue)")
        appConnection?.invalidate()
        completionHandler()
    }

    // MARK: - Flow interception

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow,
              let remote = socketFlow.remoteEndpoint as? NWHostEndpoint,
              !remote.hostname.isEmpty else {
            return .allow()
        }

        let info = buildConnectionInfo(from: socketFlow, remote: remote)

        // Fast path: cached rule.
        if let (verdict, _) = ruleCache.verdict(for: info) {
            logVerdict(info: info, verdict: verdict, ruleID: nil)
            return verdict == .allow ? .allow() : .drop()
        }

        // Slow path: pause and ask the user.
        let flowID = UUID()
        pendingQueue.async(flags: .barrier) { self.pendingFlows[flowID] = flow }

        // Kick off async DNS then prompt.
        dnsResolver.resolve(ip: info.destinationAddress) { [weak self] hostname in
            var enriched = info
            enriched.resolvedHostname = hostname
            self?.askUser(info: enriched, flowID: flowID)
        }

        return .pause()
    }

    // MARK: - Asking the app

    private func askUser(info: ConnectionInfo, flowID: UUID) {
        guard let proxy = appConnection?.remoteObjectProxy as? MacSnitchAppXPCProtocol else {
            log.warning("No XPC app connection — defaulting allow for \(info.processName)")
            resume(flowID: flowID, verdict: .allow)
            return
        }
        guard let data = try? JSONEncoder().encode(info) else {
            resume(flowID: flowID, verdict: .allow); return
        }

        proxy.promptForVerdict(connectionData: data) { [weak self] replyData in
            guard let self else { return }
            if let reply = try? JSONDecoder().decode(VerdictReply.self, from: replyData) {
                if let rule = reply.rule, rule.duration != .once {
                    self.ruleCache.insert(rule)
                }
                self.logVerdict(info: info, verdict: reply.verdict, ruleID: reply.rule?.id)
                self.resume(flowID: flowID, verdict: reply.verdict)
            } else {
                self.resume(flowID: flowID, verdict: .allow)
            }
        }
    }

    private func resume(flowID: UUID, verdict: Verdict) {
        pendingQueue.async(flags: .barrier) {
            guard let flow = self.pendingFlows.removeValue(forKey: flowID) else { return }
            let nev: NEFilterDataVerdict = verdict == .allow
                ? .allow(withUpdateRules: false)
                : .drop()
            self.resumeFlow(flow, withVerdict: nev)
        }
    }

    // MARK: - XPC to app

    private func connectToApp() {
        let conn = NSXPCConnection(machServiceName: XPC.appMachServiceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: MacSnitchAppXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            log.warning("XPC connection to app lost")
            self?.appConnection = nil
            // Retry after a short delay.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self?.connectToApp()
            }
        }
        conn.resume()
        appConnection = conn
    }

    // MARK: - Build ConnectionInfo

    private func buildConnectionInfo(from flow: NEFilterSocketFlow, remote: NWHostEndpoint) -> ConnectionInfo {
        let local = flow.localEndpoint as? NWHostEndpoint
        let path = flow.sourceAppSigningIdentifier ?? "unknown"
        let name = URL(fileURLWithPath: path).lastPathComponent
        let pid: Int32 = flow.sourceAppAuditToken.map { Self.pid(from: $0) } ?? -1

        return ConnectionInfo(
            pid: pid,
            processName: name.isEmpty ? path : name,
            processPath: path,
            sourceAddress: local?.hostname ?? "0.0.0.0",
            sourcePort: UInt16(local?.port ?? "0") ?? 0,
            destinationAddress: remote.hostname,
            destinationPort: UInt16(remote.port) ?? 0,
            protocol: flow.socketType == SOCK_DGRAM ? .udp : .tcp
        )
    }

    private static func pid(from token: Data) -> Int32 {
        guard token.count >= 24 else { return -1 }
        return token.withUnsafeBytes { $0.load(fromByteOffset: 20, as: Int32.self) }
    }

    // MARK: - Logging (sends to app via XPC)

    private func logVerdict(info: ConnectionInfo, verdict: Verdict, ruleID: UUID?) {
        // The app's XPCServer receives this; it's fire-and-forget.
        // Implementation: encode a ConnectionLogEntry and send via a separate
        // XPC method (addLogEntry). Wired up in the full XPC protocol extension.
        _ = ConnectionLogEntry(connection: info, verdict: verdict, ruleID: ruleID)
        // TODO: call appProxy.logEntry(data:) once the log XPC method is added.
    }
}
