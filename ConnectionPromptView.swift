// MacSnitchApp/Views/ConnectionPromptView.swift
// Floating panel shown when the extension intercepts an unknown connection.

import SwiftUI

// MARK: - Decision types

public enum PromptScope: String, CaseIterable {
    case process     = "From this app (any connection)"
    case destination = "To this host"
    case port        = "To this port"
    case exact       = "To this host and port"
}

public enum UserDecision {
    case allow(scope: PromptScope, duration: RuleDuration)
    case deny(scope: PromptScope, duration: RuleDuration)
}

// MARK: - View

struct ConnectionPromptView: View {
    let connection: ConnectionInfo
    let onDecision: (UserDecision) -> Void

    @State private var scope: PromptScope = .process
    @State private var duration: RuleDuration = .permanent
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            connectionDetails
            Divider()
            ruleOptions
            Divider()
            actionButtons
        }
        .frame(width: 460)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            appIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(connection.processName)
                    .font(.title3).fontWeight(.semibold)
                Text("wants to make a network connection")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private var appIcon: some View {
        Group {
            let icon = NSWorkspace.shared.icon(forFile: connection.processPath)
            Image(nsImage: icon)
                .resizable()
                .frame(width: 52, height: 52)
        }
    }

    // MARK: - Connection details

    private var connectionDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Destination", value: connection.displayDestination)
            if let hostname = connection.resolvedHostname,
               hostname != connection.destinationAddress {
                DetailRow(label: "IP Address", value: connection.destinationAddress)
            }
            DetailRow(label: "Port", value: "\(connection.destinationPort) (\(wellKnownService(connection.destinationPort)))")
            DetailRow(label: "Protocol", value: connection.protocol.rawValue)
            DetailRow(label: "Path", value: connection.processPath, monospaced: true)
            if connection.pid > 0 {
                DetailRow(label: "PID", value: "\(connection.pid)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Rule options

    private var ruleOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Apply rule to:")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.bottom, 2)

            Picker("Scope", selection: $scope) {
                ForEach(PromptScope.allCases, id: \.self) { s in
                    Text(scopeLabel(s)).tag(s)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Divider()

            HStack {
                Text("Remember for:")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Picker("Duration", selection: $duration) {
                    Text("This connection only").tag(RuleDuration.once)
                    Text("Until quit").tag(RuleDuration.session)
                    Text("Always").tag(RuleDuration.permanent)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
        }
        .padding(16)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                onDecision(.deny(scope: scope, duration: duration))
            } label: {
                HStack {
                    Image(systemName: "xmark.shield.fill").foregroundStyle(.red)
                    Text(duration == .once ? "Deny Once" : duration == .session ? "Deny Until Quit" : "Always Deny")
                }
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.escape)
            .controlSize(.large)

            Button {
                onDecision(.allow(scope: scope, duration: duration))
            } label: {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                    Text(duration == .once ? "Allow Once" : duration == .session ? "Allow Until Quit" : "Always Allow")
                }
                .frame(maxWidth: .infinity)
            }
            .keyboardShortcut(.return)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private func scopeLabel(_ s: PromptScope) -> String {
        switch s {
        case .process:     return "Any connection from \(connection.processName)"
        case .destination: return "Connections to \(connection.displayDestination)"
        case .port:        return "Connections to port \(connection.destinationPort)"
        case .exact:       return "Connections to \(connection.displayDestination):\(connection.destinationPort)"
        }
    }

    private func wellKnownService(_ port: UInt16) -> String {
        switch port {
        case 80:   return "HTTP"
        case 443:  return "HTTPS"
        case 22:   return "SSH"
        case 25:   return "SMTP"
        case 53:   return "DNS"
        case 143:  return "IMAP"
        case 587:  return "SMTP/TLS"
        case 993:  return "IMAPS"
        case 3306: return "MySQL"
        case 5432: return "PostgreSQL"
        default:   return "unknown"
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 90, alignment: .trailing)
                .foregroundStyle(.secondary)
                .font(.callout)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }
}

// MARK: - Preview

#Preview {
    ConnectionPromptView(connection: ConnectionInfo(
        pid: 1234, processName: "curl", processPath: "/usr/bin/curl",
        sourceAddress: "192.168.1.5", sourcePort: 54321,
        destinationAddress: "140.82.112.6", destinationPort: 443,
        protocol: .tcp, resolvedHostname: "api.github.com")
    ) { d in print(d) }
}
