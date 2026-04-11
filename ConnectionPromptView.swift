// MacSnitchApp/Views/ConnectionPromptView.swift
// Modal shown when the extension intercepts an unknown connection.

import SwiftUI

struct ConnectionPromptView: View {
    let connection: ConnectionInfo
    let onDecision: (UserDecision) -> Void

    @State private var selectedDuration: RuleDuration = .permanent
    @State private var selectedScope: PromptScope = .process

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 12) {
                AppIconView(processPath: connection.processPath)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.processName)
                        .font(.headline)
                    Text("wants to connect to the internet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Connection details
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Destination").foregroundStyle(.secondary)
                    Text("\(connection.destinationAddress):\(connection.destinationPort)")
                        .fontDesign(.monospaced)
                }
                GridRow {
                    Text("Protocol").foregroundStyle(.secondary)
                    Text(connection.protocol.rawValue)
                }
                GridRow {
                    Text("Process").foregroundStyle(.secondary)
                    Text(connection.processPath)
                        .fontDesign(.monospaced)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                GridRow {
                    Text("PID").foregroundStyle(.secondary)
                    Text("\(connection.pid)")
                        .fontDesign(.monospaced)
                }
            }
            .font(.callout)

            Divider()

            // Rule options
            VStack(alignment: .leading, spacing: 10) {
                Text("If I allow or deny, apply this rule…")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker("Scope", selection: $selectedScope) {
                    Text("For any connection from \(connection.processName)").tag(PromptScope.process)
                    Text("For connections to \(connection.destinationAddress)").tag(PromptScope.destination)
                    Text("For connections to port \(connection.destinationPort)").tag(PromptScope.port)
                    Text("For this exact connection only").tag(PromptScope.exact)
                }
                .pickerStyle(.radioGroup)

                Picker("Duration", selection: $selectedDuration) {
                    Text("Once").tag(RuleDuration.once)
                    Text("Until quit").tag(RuleDuration.session)
                    Text("Always").tag(RuleDuration.permanent)
                }
                .pickerStyle(.segmented)
            }

            Divider()

            // Action buttons
            HStack {
                Button(role: .destructive) {
                    onDecision(.deny(scope: selectedScope, duration: selectedDuration))
                } label: {
                    Label("Deny", systemImage: "xmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.escape)
                .controlSize(.large)

                Button {
                    onDecision(.allow(scope: selectedScope, duration: selectedDuration))
                } label: {
                    Label("Allow", systemImage: "checkmark.shield.fill")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.return)
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

// MARK: - Supporting types

enum PromptScope {
    case process, destination, port, exact
}

enum UserDecision {
    case allow(scope: PromptScope, duration: RuleDuration)
    case deny(scope: PromptScope, duration: RuleDuration)
}

// MARK: - App icon placeholder

struct AppIconView: View {
    let processPath: String

    var body: some View {
        Group {
            if let icon = NSWorkspace.shared.icon(forFile: processPath).cgImage(forProposedRect: nil, context: nil, hints: nil) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: processPath))
                    .resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 48)
    }
}

// MARK: - Preview

#Preview {
    ConnectionPromptView(
        connection: ConnectionInfo(
            pid: 1234,
            processName: "curl",
            processPath: "/usr/bin/curl",
            sourceAddress: "192.168.1.5",
            sourcePort: 54321,
            destinationAddress: "142.250.185.46",
            destinationPort: 443,
            protocol: .tcp
        )
    ) { decision in
        print("Decision: \(decision)")
    }
}
