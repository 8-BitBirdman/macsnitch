// MacSnitchApp/Views/ConnectionLogView.swift
// Live connection log with working pause, search, verdict filter, and row detail.

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionLogView: View {
    @EnvironmentObject var logger: ConnectionLogger

    @State private var searchText       = ""
    @State private var filterVerdict: Verdict? = nil
    @State private var selection: ConnectionLogEntry.ID?
    @State private var showingClearConfirm = false
    @State private var isPaused         = false
    @State private var frozenEntries: [ConnectionLogEntry] = []

    // When paused we display the frozen snapshot; otherwise live.
    private var activeEntries: [ConnectionLogEntry] {
        isPaused ? frozenEntries : logger.entries
    }

    private var displayedEntries: [ConnectionLogEntry] {
        activeEntries.filter { entry in
            (filterVerdict == nil || entry.verdict == filterVerdict) &&
            (searchText.isEmpty
             || entry.connection.processName.localizedCaseInsensitiveContains(searchText)
             || entry.connection.displayDestination.localizedCaseInsensitiveContains(searchText)
             || entry.connection.destinationAddress.localizedCaseInsensitiveContains(searchText)
             || String(entry.connection.destinationPort).hasPrefix(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if displayedEntries.isEmpty {
                emptyState
            } else {
                logTable
            }
        }
        .navigationTitle("Connection Log")
        .confirmationDialog("Clear all log entries?", isPresented: $showingClearConfirm,
                            titleVisibility: .visible) {
            Button("Clear Log", role: .destructive) {
                logger.clearAll()
                frozenEntries = []
                selection = nil
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {

            // Verdict filter
            Picker("Filter", selection: $filterVerdict) {
                Text("All").tag(nil as Verdict?)
                Label("Allowed", systemImage: "checkmark.shield.fill")
                    .tag(Verdict.allow as Verdict?)
                Label("Denied",  systemImage: "xmark.shield.fill")
                    .tag(Verdict.deny as Verdict?)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)

            Spacer()

            // Live counters — always reflect the full live log even when paused
            HStack(spacing: 14) {
                CountBadge(count: logger.entries.filter { $0.verdict == .allow }.count,
                           label: "allowed", color: .green)
                CountBadge(count: logger.entries.filter { $0.verdict == .deny }.count,
                           label: "denied",  color: .red)
            }

            Divider().frame(height: 18)

            // Pause / Resume
            Button {
                if isPaused {
                    isPaused = false
                    frozenEntries = []
                } else {
                    frozenEntries = logger.entries   // snapshot current state
                    isPaused = true
                }
            } label: {
                Label(isPaused ? "Resume" : "Pause",
                      systemImage: isPaused ? "play.fill" : "pause.fill")
            }
            .help(isPaused ? "Resume live updates" : "Pause the log display")
            .foregroundStyle(isPaused ? .orange : .primary)

            // Export visible entries to CSV
            Button { exportCSV() } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Export log as CSV")

            // Clear
            Button(role: .destructive) { showingClearConfirm = true } label: {
                Image(systemName: "trash")
            }
            .help("Clear all log entries")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Table

    private var logTable: some View {
        Table(displayedEntries, selection: $selection) {

            TableColumn("Time") { entry in
                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(80)

            TableColumn("Verdict") { entry in
                VerdictBadge(verdict: entry.verdict)
            }
            .width(72)

            TableColumn("App") { entry in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.connection.processPath))
                        .resizable().frame(width: 16, height: 16)
                    Text(entry.connection.processName)
                        .lineLimit(1)
                }
            }
            .width(min: 100, ideal: 160)

            TableColumn("Destination") { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.connection.displayDestination)
                        .lineLimit(1)
                    if let hostname = entry.connection.resolvedHostname,
                       hostname != entry.connection.destinationAddress {
                        Text(entry.connection.destinationAddress)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("Port") { entry in
                Text("\(entry.connection.destinationPort)")
                    .font(.callout.monospaced())
            }
            .width(52)

            TableColumn("Proto") { entry in
                Text(entry.connection.protocol.rawValue)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(50)
        }
        .searchable(text: $searchText, prompt: "Filter log…")
        // Show a detail popover when a row is selected
        .popover(item: selectedEntry) { entry in
            ConnectionDetailPopover(entry: entry)
                .padding(16)
                .frame(width: 340)
        }
    }

    private var selectedEntry: Binding<ConnectionLogEntry?> {
        Binding(
            get: { displayedEntries.first { $0.id == selection } },
            set: { selection = $0?.id }
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView(
            isPaused ? "Log paused" : "No Connections Logged",
            systemImage: isPaused ? "pause.circle" : "network",
            description: Text(isPaused
                ? "Resume to see new connections."
                : "Intercepted connections will appear here in real time.")
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Export to CSV

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.title = "Export Connection Log"
        panel.nameFieldStringValue = "macsnitch-log.csv"
        panel.allowedContentTypes = [.commaSeparatedText]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        var lines = ["Time,Verdict,App,Process Path,Destination,IP,Port,Protocol"]
        for entry in displayedEntries {
            let c = entry.connection
            lines.append([
                entry.timestamp.formatted(),
                entry.verdict.rawValue,
                c.processName,
                c.processPath,
                c.displayDestination,
                c.destinationAddress,
                "\(c.destinationPort)",
                c.protocol.rawValue
            ].map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ","))
        }

        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Connection Detail Popover

struct ConnectionDetailPopover: View {
    let entry: ConnectionLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.connection.processPath))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.connection.processName).font(.headline)
                    VerdictBadge(verdict: entry.verdict)
                }
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                DetailGridRow(label: "Time",
                    value: entry.timestamp.formatted(date: .abbreviated, time: .standard))
                DetailGridRow(label: "Destination",
                    value: entry.connection.displayDestination)
                if let h = entry.connection.resolvedHostname,
                   h != entry.connection.destinationAddress {
                    DetailGridRow(label: "IP", value: entry.connection.destinationAddress)
                }
                DetailGridRow(label: "Port",
                    value: "\(entry.connection.destinationPort)")
                DetailGridRow(label: "Protocol",
                    value: entry.connection.protocol.rawValue)
                DetailGridRow(label: "Process",
                    value: entry.connection.processPath, monospaced: true)
                if entry.connection.pid > 0 {
                    DetailGridRow(label: "PID",
                        value: "\(entry.connection.pid)")
                }
            }
            .font(.callout)
        }
    }
}

private struct DetailGridRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value)
                .font(monospaced ? .callout.monospaced() : .callout)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Shared badge views

struct VerdictBadge: View {
    let verdict: Verdict
    var body: some View {
        Text(verdict == .allow ? "Allow" : "Deny")
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(
                verdict == .allow ? Color.green.opacity(0.15) : Color.red.opacity(0.15),
                in: Capsule())
            .foregroundStyle(verdict == .allow ? .green : .red)
    }
}

struct CountBadge: View {
    let count: Int
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)").fontWeight(.semibold).foregroundStyle(color)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

