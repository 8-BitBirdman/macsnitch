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
        VStack(spacing: 24) {
            header
            
            VStack(spacing: 20) {
                connectionDetails
                ruleOptions
            }
            .padding(.horizontal, 24)
            
            actionButtons
        }
        .padding(.vertical, 24)
        .frame(width: 480)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .withinWindow))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            appIcon
                .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            
            VStack(spacing: 4) {
                Text(connection.processName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                
                Text("Connection Request")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)
            }
        }
        .padding(.top, 8)
    }

    private var appIcon: some View {
        Group {
            let icon = NSWorkspace.shared.icon(forFile: connection.processPath)
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
        }
    }

    // MARK: - Connection details

    private var connectionDetails: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Destination")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(connection.displayDestination)
                        .font(.system(.body, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Service")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    Text(wellKnownService(connection.destinationPort))
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.accent)
                }
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .cornerRadius(12)
        }
    }

    // MARK: - Rule options

    private var ruleOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Scope")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                Picker("Scope", selection: $scope) {
                    ForEach(PromptScope.allCases, id: \.self) { s in
                        Text(scopeLabel(s)).tag(s)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Remember for")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                
                Picker("Duration", selection: $duration) {
                    Text("Once").tag(RuleDuration.once)
                    Text("Session").tag(RuleDuration.session)
                    Text("Always").tag(RuleDuration.permanent)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                onDecision(.deny(scope: scope, duration: duration))
            } label: {
                Text("Deny")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .keyboardShortcut(.escape)

            Button {
                onDecision(.allow(scope: scope, duration: duration))
            } label: {
                Text("Allow")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 24)
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
