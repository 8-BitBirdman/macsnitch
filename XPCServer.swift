// MacSnitchApp/Services/XPCServer.swift
// Hosts the XPC listener so the Network Extension can send connection prompts
// to the main app and receive verdicts back.

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "XPCServer")

// MARK: - Delegate

protocol XPCServerDelegate: AnyObject {
    func didReceivePrompt(connectionInfo: ConnectionInfo) async -> VerdictReply
}

// MARK: - VerdictReply

struct VerdictReply: Codable {
    let verdict: Verdict
    let rule: Rule?
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
        let listener = NSXPCListener(machServiceName: XPC.appMachServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        log.info("XPC listener started on \(XPC.appMachServiceName)")
    }
}

// MARK: - NSXPCListenerDelegate

extension XPCServer: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: MacSnitchAppXPCProtocol.self)
        newConnection.exportedObject = XPCHandler(delegate: delegate)
        newConnection.resume()
        return true
    }
}

// MARK: - XPCHandler

/// The object exported to the extension over XPC.
private final class XPCHandler: NSObject, MacSnitchAppXPCProtocol {
    weak var delegate: XPCServerDelegate?

    init(delegate: XPCServerDelegate?) {
        self.delegate = delegate
    }

    func promptForVerdict(connectionData: Data, reply: @escaping (Data) -> Void) {
        guard let connection = try? JSONDecoder().decode(ConnectionInfo.self, from: connectionData) else {
            log.error("Failed to decode ConnectionInfo from extension")
            let defaultReply = VerdictReply(verdict: .allow, rule: nil)
            reply((try? JSONEncoder().encode(defaultReply)) ?? Data())
            return
        }

        Task { @MainActor in
            let verdictReply = await delegate?.didReceivePrompt(connectionInfo: connection)
                ?? VerdictReply(verdict: .allow, rule: nil)
            let replyData = (try? JSONEncoder().encode(verdictReply)) ?? Data()
            reply(replyData)
        }
    }
}
