// MacSnitchApp/Services/XPCServer.swift
// NSXPCListener hosted in the app. The Network Extension calls in here
// to (a) prompt for a verdict and (b) log connection decisions.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "XPCServer")

// MARK: - Delegate

protocol XPCServerDelegate: AnyObject {
    func didReceivePrompt(connectionInfo: ConnectionInfo) async -> VerdictReply
    func didReceiveLogEntry(_ entry: ConnectionLogEntry)
}

// MARK: - XPCServer

final class XPCServer: NSObject {
    private var listener: NSXPCListener?
    weak var delegate: XPCServerDelegate?

    init(delegate: XPCServerDelegate) {
        self.delegate = delegate
        super.init()
    }

    func start() {
        let l = NSXPCListener(machServiceName: XPC.appMachServiceName)
        l.delegate = self
        l.resume()
        listener = l
        log.info("XPC listener started")
    }

    func stop() {
        listener?.invalidate()
    }
}

extension XPCServer: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: MacSnitchAppXPCProtocol.self)
        connection.exportedObject = AppXPCHandler(delegate: delegate)
        connection.resume()
        log.info("Accepted new XPC connection from extension")
        return true
    }
}

// MARK: - Handler (exported object)

private final class AppXPCHandler: NSObject, MacSnitchAppXPCProtocol {
    weak var delegate: XPCServerDelegate?
    init(delegate: XPCServerDelegate?) { self.delegate = delegate }

    func promptForVerdict(connectionData: Data, reply: @escaping (Data) -> Void) {
        guard let conn = try? JSONDecoder().decode(ConnectionInfo.self, from: connectionData) else {
            log.error("Failed to decode ConnectionInfo")
            let r = VerdictReply(verdict: .allow)
            reply((try? JSONEncoder().encode(r)) ?? Data())
            return
        }

        Task { @MainActor in
            let verdictReply = await self.delegate?.didReceivePrompt(connectionInfo: conn)
                ?? VerdictReply(verdict: .allow)
            reply((try? JSONEncoder().encode(verdictReply)) ?? Data())
        }
    }
}
