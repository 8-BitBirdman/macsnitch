// NetworkExtension/FilterProvider.swift
// NEFilterDataProvider — intercepts every outbound TCP/UDP flow.

import NetworkExtension
import OSLog

private let log = Logger(subsystem: "com.macsnitch.extension", category: "FilterProvider")

final class FilterProvider: NEFilterDataProvider, NSXPCListenerDelegate {

    private let ruleCache   = RuleCache.shared
    private let dnsResolver = DNSResolver()
    private var appConnection: NSXPCConnection?
    private var xpcListener: NSXPCListener?

    private var pendingFlows: [UUID: NEFilterFlow] = [:]
    private let pendingQueue = DispatchQueue(
        label: "com.macsnitch.pending", attributes: .concurrent)

    // MARK: - Lifecycle

    override func startFilter(completionHandler: @escaping (Error?) -> Void) {
        log.info("MacSnitch extension starting")
        connectToApp()
        startXPCListener()
        completionHandler(nil)
    }

    override func stopFilter(with reason: NEProviderStopReason,
                             completionHandler: @escaping () -> Void) {
        log.info("MacSnitch extension stopping: \(reason.rawValue)")
        appConnection?.invalidate()
        xpcListener?.invalidate()
        completionHandler()
    }

    // MARK: - Flow interception

    override func handleNewFlow(_ flow: NEFilterFlow) -> NEFilterNewFlowVerdict {
        guard let socketFlow = flow as? NEFilterSocketFlow else { return .allow() }

        // Extract remote host + port. NEFilterSocketFlow still vends NWHostEndpoint
        // objects even on macOS 13+; the NWHostEndpoint class is deprecated for
        // creation but is the only way to extract hostname/port here. Suppress warning.
        let remoteHost: String
        let remotePort: UInt16
        switch socketFlow.remoteEndpoint {
        case let ep as NWHostEndpoint:  // swiftlint:disable:this legacy_objc_type
            remoteHost = ep.hostname
            remotePort = UInt16(ep.port) ?? 0
        default:
            return .allow()  // non-host endpoints (e.g. Bonjour) — pass through
        }

        guard !remoteHost.isEmpty else { return .allow() }

        let info = buildConnectionInfo(from: socketFlow,
                                       remoteHost: remoteHost, remotePort: remotePort)

        // Fast path: cached rule.
        if let (v, rule) = ruleCache.verdict(for: info) {
            let verdict: Verdict = v == .allow ? .allow : .deny
            // Log cached decision asynchronously
            if let proxy = appConnection?.remoteObjectProxy as? MacSnitchAppXPCProtocol {
                let entry = ConnectionLogEntry(connection: info, verdict: verdict, ruleID: rule?.id)
                if let data = try? JSONEncoder().encode(entry) {
                    proxy.logConnection(entryData: data)
                }
            }
            return v == .allow ? .allow() : .drop()
        }

        // Slow path: pause and ask the user.
        let flowID = UUID()
        pendingQueue.async(flags: .barrier) { self.pendingFlows[flowID] = flow }

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
            resume(flowID: flowID, verdict: .allow)
            return
        }

        proxy.promptForVerdict(connectionData: data) { [weak self] replyData in
            guard let self else { return }
            if let reply = try? JSONDecoder().decode(VerdictReply.self, from: replyData) {
                if let rule = reply.rule, rule.duration != .once {
                    self.ruleCache.insert(rule)
                }
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

    // MARK: - XPC Listener (app → extension)

    private func startXPCListener() {
        let listener = NSXPCListener(machServiceName: XPC.machServiceName)
        listener.delegate = self
        listener.resume()
        xpcListener = listener
        log.info("Extension XPC listener started on \(XPC.machServiceName)")
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: MacSnitchExtensionXPCProtocol.self)
        conn.exportedObject = ExtensionXPCHandler(cache: ruleCache)
        conn.resume()
        return true
    }

    // MARK: - XPC connection to app

    private func connectToApp() {
        let conn = NSXPCConnection(machServiceName: XPC.appMachServiceName, options: [])
        conn.remoteObjectInterface = NSXPCInterface(with: MacSnitchAppXPCProtocol.self)
        conn.invalidationHandler = { [weak self] in
            log.warning("XPC connection to app lost — fail-safe allow all pending flows")
            guard let self else { return }
            
            self.pendingQueue.async(flags: .barrier) {
                for flow in self.pendingFlows.values {
                    self.resumeFlow(flow, withVerdict: .allow())
                }
                self.pendingFlows.removeAll()
            }
            
            self.appConnection = nil
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                self.connectToApp()
            }
        }
        conn.resume()
        appConnection = conn
    }

    // MARK: - ConnectionInfo builder

    private func buildConnectionInfo(from flow: NEFilterSocketFlow,
                                     remoteHost: String,
                                     remotePort: UInt16) -> ConnectionInfo {
        let localHost: String
        let localPort: UInt16
        switch flow.localEndpoint {
        case let ep as NWHostEndpoint:  // swiftlint:disable:this legacy_objc_type
            localHost = ep.hostname
            localPort = UInt16(ep.port) ?? 0
        default:
            localHost = "0.0.0.0"
            localPort = 0
        }

        let signingID = flow.sourceAppSigningIdentifier
        let pid = flow.sourceAppUniqueIdentifier.flatMap { Self.pid(fromAuditToken: $0) } ?? -1
        let proto: TransportProtocol = flow is NEFilterUDPFlow ? .udp : .tcp

        // Try to get actual process path via pid
        var processPath = signingID
        if pid > 0 {
            let pathBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
            defer { pathBuffer.deallocate() }
            let pathLength = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
            if pathLength > 0 {
                processPath = String(cString: pathBuffer)
            }
        }

        let processName = URL(fileURLWithPath: processPath).lastPathComponent
        
        return ConnectionInfo(
            pid: pid,
            processName: processName.isEmpty ? signingID : processName,
            processPath: processPath,
            sourceAddress: localHost,
            sourcePort: localPort,
            destinationAddress: remoteHost,
            destinationPort: remotePort,
            protocol: proto
        )
    }

    /// Extract PID from an audit token (opaque 32-byte struct; PID is at bytes 20–23).
    private static func pid(fromAuditToken token: Data) -> Int32? {
        guard token.count >= 24 else { return nil }
        return token.withUnsafeBytes { ptr in
            ptr.load(fromByteOffset: 20, as: Int32.self)
        }
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

    func updateRules(ruleDatas: [Data], reply: @escaping (Bool) -> Void) {
        let decoder = JSONDecoder()
        var count = 0
        for data in ruleDatas {
            if let rule = try? decoder.decode(Rule.self, from: data) {
                cache.insert(rule)
                count += 1
            }
        }
        log.info("Batch rule update: \(count) rules")
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

// C-bridge for proc_pidpath
@_silgen_name("proc_pidpath")
func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutablePointer<Int8>, _ bufferSize: UInt32) -> Int32
