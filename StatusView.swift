// MacSnitchApp/Views/StatusView.swift
// Status tab: extension health card, session stats, per-process breakdown, top destinations.

import SwiftUI

struct StatusView: View {
    @EnvironmentObject var extensionManager: FilterExtensionManager
    @EnvironmentObject var logger: ConnectionLogger

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                extensionCard
                sessionStatsCard
                processBreakdownCard
                topDestinationsCard
            }
            .padding(20)
        }
        .navigationTitle("Status")
        .onAppear { extensionManager.checkStatus() }
    }

    // MARK: - Extension status card

    private var extensionCard: some View {
        GroupBox {
            HStack(spacing: 20) {
                // Animated status indicator
                ZStack {
                    Circle()
                        .fill(extensionManager.isEnabled
                              ? Color.green.opacity(0.15)
                              : Color.orange.opacity(0.12))
                        .frame(width: 68, height: 68)
                    if extensionManager.isEnabled {
                        Circle()
                            .fill(Color.green.opacity(0.08))
                            .frame(width: 84, height: 84)
                    }
                    Image(systemName: extensionManager.isEnabled
                          ? "shield.fill" : "shield.slash.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(extensionManager.isEnabled ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(extensionManager.isEnabled ? "Protection Active" : "Protection Off")
                        .font(.title2).fontWeight(.semibold)
                    Text(extensionManager.statusMessage)
                        .font(.callout).foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    extensionManager.isEnabled
                        ? extensionManager.disable()
                        : extensionManager.enable()
                } label: {
                    Text(extensionManager.isEnabled ? "Disable" : "Enable")
                        .frame(width: 90)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .tint(extensionManager.isEnabled ? .secondary : .accentColor)
            }
            .padding(6)
        } label: {
            Label("MacSnitch Extension", systemImage: "network.badge.shield.half.filled")
                .font(.headline)
        }
    }

    // MARK: - Session stats card

    private var sessionStatsCard: some View {
        GroupBox {
            HStack(spacing: 0) {
                StatCell(value: "\(logger.entries.count)",
                         label: "Total", icon: "network", color: .blue)
                Divider().frame(height: 60)
                StatCell(value: "\(logger.entries(verdict: .allow).count)",
                         label: "Allowed", icon: "checkmark.shield.fill", color: .green)
                Divider().frame(height: 60)
                StatCell(value: "\(logger.entries(verdict: .deny).count)",
                         label: "Denied", icon: "xmark.shield.fill", color: .red)
                Divider().frame(height: 60)
                StatCell(value: uniqueApps,
                         label: "Apps seen", icon: "app.badge", color: .purple)
            }
        } label: {
            Label("This Session", systemImage: "chart.bar.fill")
                .font(.headline)
        }
    }

    private var uniqueApps: String {
        "\(Set(logger.entries.map(\.connection.processPath)).count)"
    }

    // MARK: - Per-process breakdown

    private var processBreakdownCard: some View {
        GroupBox {
            if logger.entries.isEmpty {
                emptyHint("No connections recorded yet.")
            } else {
                VStack(spacing: 0) {
                    // Header row
                    HStack {
                        Text("App").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Allowed").frame(width: 70, alignment: .trailing)
                        Text("Denied").frame(width: 70, alignment: .trailing)
                        Text("Total").frame(width: 60, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                    Divider()

                    ForEach(processStatsFromLog) { stat in
                        ProcessStatRow(stat: stat)
                        if stat.id != processStatsFromLog.last?.id { Divider() }
                    }
                }
            }
        } label: {
            Label("By Application", systemImage: "apps.iphone")
                .font(.headline)
        }
    }

    // Compute inline so we always have logger available.
    private var processStatsFromLog: [ProcessStats] {
        var byProcess: [String: (name: String, allowed: Int, denied: Int)] = [:]
        for entry in logger.entries {
            let path = entry.connection.processPath
            var s = byProcess[path] ?? (name: entry.connection.processName, allowed: 0, denied: 0)
            entry.verdict == .allow ? (s.allowed += 1) : (s.denied += 1)
            byProcess[path] = s
        }
        return byProcess
            .map { path, s in
                ProcessStats(id: path, processName: s.name, processPath: path,
                             allowed: s.allowed, denied: s.denied)
            }
            .sorted()
            .prefix(15)
            .map { $0 }
    }

    // MARK: - Top destinations

    private var topDestinationsCard: some View {
        GroupBox {
            if logger.entries.isEmpty {
                emptyHint("No connections recorded yet.")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Destination").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Connections").frame(width: 100, alignment: .trailing)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)

                    Divider()

                    ForEach(topDestinationsFromLog) { dest in
                        DestinationRow(stat: dest, maxCount: topDestinationsFromLog.first?.count ?? 1)
                        if dest.id != topDestinationsFromLog.last?.id { Divider() }
                    }
                }
            }
        } label: {
            Label("Top Destinations", systemImage: "globe")
                .font(.headline)
        }
    }

    private var topDestinationsFromLog: [DestinationStats] {
        var byDest: [String: Int] = [:]
        for entry in logger.entries {
            let h = entry.connection.displayDestination
            byDest[h, default: 0] += 1
        }
        return byDest
            .map { DestinationStats(id: $0.key, host: $0.key, count: $0.value) }
            .sorted()
            .prefix(10)
            .map { $0 }
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

private struct StatCell: View {
    let value: String
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title2).fontWeight(.bold)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

private struct ProcessStatRow: View {
    let stat: ProcessStats

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: stat.processPath))
                .resizable().frame(width: 18, height: 18)
            Text(stat.processName)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(stat.allowed)").frame(width: 70, alignment: .trailing)
                .foregroundStyle(.green)
            Text("\(stat.denied)").frame(width: 70, alignment: .trailing)
                .foregroundStyle(.red)
            Text("\(stat.total)").frame(width: 60, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

private struct DestinationRow: View {
    let stat: DestinationStats
    let maxCount: Int

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(stat.host)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(stat.count)")
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
            GeometryReader { geo in
                let fraction = maxCount > 0
                    ? CGFloat(stat.count) / CGFloat(maxCount) : 0
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue.opacity(0.25))
                    .frame(width: geo.size.width * fraction, height: 4)
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
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
