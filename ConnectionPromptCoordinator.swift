// MacSnitchApp/Services/ConnectionPromptCoordinator.swift
// Serializes incoming connection prompts and shows them one at a time
// in a floating panel above all other windows.

import AppKit
import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "PromptCoordinator")

@MainActor
final class ConnectionPromptCoordinator {
    static let shared = ConnectionPromptCoordinator()

    private var queue: [PromptTask] = []
    private var isPresenting = false
    private var window: NSWindow?

    private struct PromptTask {
        let connection: ConnectionInfo
        let continuation: CheckedContinuation<VerdictReply, Never>
    }

    private init() {}

    // MARK: - Public

    func prompt(for connection: ConnectionInfo) async -> VerdictReply {
        return await withCheckedContinuation { continuation in
            queue.append(PromptTask(connection: connection, continuation: continuation))
            if !isPresenting { presentNext() }
        }
    }

    // MARK: - Private

    private func presentNext() {
        guard !queue.isEmpty else {
            isPresenting = false
            return
        }
        isPresenting = true
        let task = queue.removeFirst()

        let panel = makePromptWindow(connection: task.connection) { [weak self] decision in
            guard let self else { return }
            let reply = self.replyFrom(decision: decision, connection: task.connection)
            task.continuation.resume(returning: reply)
            self.window?.orderOut(nil)
            self.window = nil
            self.presentNext()
        }

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makePromptWindow(connection: ConnectionInfo, onDecision: @escaping (UserDecision) -> Void) -> NSWindow {
        let view = ConnectionPromptView(connection: connection, onDecision: onDecision)
        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .hudWindow],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.center()
        panel.isReleasedWhenClosed = false
        return panel
    }

    private func replyFrom(decision: UserDecision, connection: ConnectionInfo) -> VerdictReply {
        switch decision {
        case .allow(let scope, let duration):
            let rule = duration == .once ? nil : buildRule(action: .allow, scope: scope, duration: duration, connection: connection)
            return VerdictReply(verdict: .allow, rule: rule)
        case .deny(let scope, let duration):
            let rule = duration == .once ? nil : buildRule(action: .deny, scope: scope, duration: duration, connection: connection)
            return VerdictReply(verdict: .deny, rule: rule)
        }
    }

    private func buildRule(action: RuleAction, scope: PromptScope, duration: RuleDuration, connection: ConnectionInfo) -> Rule {
        let match: RuleMatch
        switch scope {
        case .process: match = .process
        case .destination: match = .destination(host: connection.destinationAddress)
        case .port: match = .destinationPort(port: connection.destinationPort)
        case .exact: match = .destinationAndPort(host: connection.destinationAddress, port: connection.destinationPort)
        }
        return Rule(
            processPath: connection.processPath,
            action: action,
            duration: duration,
            match: match
        )
    }
}
