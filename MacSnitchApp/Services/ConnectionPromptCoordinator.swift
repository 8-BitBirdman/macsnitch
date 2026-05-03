// MacSnitchApp/Services/ConnectionPromptCoordinator.swift
// Serialises simultaneous prompts into a queue and presents them one at a time.

import AppKit
import SwiftUI

@MainActor
final class ConnectionPromptCoordinator {
    static let shared = ConnectionPromptCoordinator()

    private struct Task {
        let connection: ConnectionInfo
        let continuation: CheckedContinuation<VerdictReply, Never>
    }

    private var queue: [Task] = []
    private var window: NSWindow?
    private var isShowing = false

    private init() {}

    func prompt(for connection: ConnectionInfo) async -> VerdictReply {
        await withCheckedContinuation { cont in
            queue.append(Task(connection: connection, continuation: cont))
            if !isShowing { showNext() }
        }
    }

    private func showNext() {
        guard !queue.isEmpty else { isShowing = false; return }
        isShowing = true
        let task = queue.removeFirst()

        let view = ConnectionPromptView(connection: task.connection) { [weak self] decision in
            guard let self else { return }
            let reply = self.buildReply(decision: decision, connection: task.connection)
            task.continuation.resume(returning: reply)
            self.window?.orderOut(nil)
            self.window = nil
            self.showNext()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 1),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.contentViewController = NSHostingController(rootView: view)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = panel
    }

    private func buildReply(decision: UserDecision, connection: ConnectionInfo) -> VerdictReply {
        let verdict: Verdict
        let action: RuleAction
        let duration: RuleDuration
        let scope: PromptScope

        switch decision {
        case .allow(let s, let d):
            verdict = .allow; action = .allow; duration = d; scope = s
        case .deny(let s, let d):
            verdict = .deny; action = .deny; duration = d; scope = s
        }

        guard duration != .once else { return VerdictReply(verdict: verdict) }

        let match: RuleMatch
        switch scope {
        case .process:     match = .process
        case .destination: match = .destination(host: connection.displayDestination)
        case .port:        match = .destinationPort(port: connection.destinationPort)
        case .exact:       match = .destinationAndPort(host: connection.displayDestination,
                                                       port: connection.destinationPort)
        }

        let rule = Rule(
            processName: connection.processName,
            processPath: connection.processPath,
            action: action, duration: duration, match: match)
        return VerdictReply(verdict: verdict, rule: rule)
    }
}
