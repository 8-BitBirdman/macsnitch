// MacSnitchApp/Views/StatusView.swift
// Status tab: extension health card, session stats, per-process breakdown, top destinations.

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var extensionManager: FilterExtensionManager
    @EnvironmentObject var logger: ConnectionLogger

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                extensionSection
                statsOverview
                
                VStack(spacing: 32) {
                    processBreakdownCard
                    topDestinationsCard
                    launchAtLoginCard
                }
            }
            .padding(32)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { extensionManager.checkStatus() }
    }

    // MARK: - Extension Section

    private var extensionSection: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(extensionManager.isEnabled ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: extensionManager.isEnabled ? "shield.fill" : "shield.slash.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(extensionManager.isEnabled ? .green : .red)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(extensionManager.isEnabled ? "System Protected" : "Protection Disabled")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(extensionManager.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                extensionManager.isEnabled ? extensionManager.disable() : extensionManager.enable()
            } label: {
                Text(extensionManager.isEnabled ? "Stop Monitoring" : "Start Monitoring")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(extensionManager.isEnabled ? .red : .accentColor)
        }
        .padding(24)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    // MARK: - Stats Overview

    private var statsOverview: some View {
        HStack(spacing: 20) {
            StatCard(title: "Total Flows", value: "\(logger.entries.count)", icon: "arrow.up.arrow.down", color: .blue)
            StatCard(title: "Blocked", value: "\(logger.entries.filter { $0.verdict == .deny }.count)", icon: "hand.raised.fill", color: .red)
            StatCard(title: "Allowed", value: "\(logger.entries.filter { $0.verdict == .allow }.count)", icon: "checkmark.circle.fill", color: .green)
            StatCard(title: "Applications", value: "\(logger.processStats.count)", icon: "app.fill", color: .purple)
        }
    }

    // MARK: - Launch at login card

    private var launchAtLoginCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Launch at Login")
                    .fontWeight(.bold)
                Text("Start MacSnitch automatically when you log in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { LaunchAtLoginManager.shared.isEnabled },
                set: { _ in LaunchAtLoginManager.shared.toggle() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(20)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(16)
    }

    // MARK: - Per-process breakdown

    private var processBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("By Application", systemImage: "apps.iphone")
            
            if logger.processStats.isEmpty {
                emptyHint("No connections recorded yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(logger.processStats.prefix(15)) { stat in
                        ProcessStatRow(stat: stat)
                        if stat.id != logger.processStats.prefix(15).last?.id { Divider().opacity(0.5) }
                    }
                }
            }
        }
        .padding(24)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(20)
    }

    private var topDestinationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Top Destinations", systemImage: "globe")
            
            if logger.destinationStats.isEmpty {
                emptyHint("No connections recorded yet.")
            } else {
                VStack(spacing: 12) {
                    ForEach(logger.destinationStats.prefix(10)) { dest in
                        DestinationRow(stat: dest, maxCount: logger.destinationStats.first?.count ?? 1)
                    }
                }
            }
        }
        .padding(24)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(20)
    }

    // MARK: - Helpers

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }
}

// MARK: - Sub-views

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct ProcessStatRow: View {
    let stat: ProcessStats

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: stat.processPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.processName)
                    .fontWeight(.medium)
                Text("\(stat.total) total connections")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if stat.denied > 0 {
                    Text("\(stat.denied) blocked")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Text("\(stat.allowed) allowed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct DestinationRow: View {
    let stat: DestinationStats
    let maxCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stat.host)
                    .font(.system(.subheadline, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text("\(stat.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            GeometryReader { geo in
                let fraction = maxCount > 0 ? CGFloat(stat.count) / CGFloat(maxCount) : 0
                Capsule()
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: geo.size.width * fraction, height: 6)
            }
            .frame(height: 6)
        }
    }
}

// MARK: - StatusHeaderView for menu bar (NSView)

final class StatusHeaderView: NSView {
    init(manager: FilterExtensionManager) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let dot = NSView(frame: NSRect(x: 16, y: 17, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = manager.isEnabled
            ? NSColor.systemGreen.cgColor
            : NSColor.systemOrange.cgColor
        addSubview(dot)

        let label = NSTextField(labelWithString: manager.isEnabled
            ? "MacSnitch — Active" : "MacSnitch — Inactive")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 34, y: 13, width: 200, height: 18)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }
}

