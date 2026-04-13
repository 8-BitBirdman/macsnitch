// MacSnitchApp/Views/RuleCreatorView.swift
// Sheet for manually creating a new firewall rule from scratch.
// Accessible from the Rules tab toolbar.

import SwiftUI

struct RuleCreatorView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @EnvironmentObject var extensionClient: ExtensionClient
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var processPath  = ""
    @State private var processName  = ""
    @State private var action       = RuleAction.allow
    @State private var duration     = RuleDuration.permanent
    @State private var matchType    = MatchType.process
    @State private var hostField    = ""
    @State private var portField    = ""
    @State private var notes        = ""

    @State private var validationError: String?
    @State private var showingFilePicker = false

    enum MatchType: String, CaseIterable {
        case process            = "Any connection from this app"
        case destination        = "Specific destination host / IP"
        case destinationPort    = "Specific port"
        case destinationAndPort = "Host and port (exact)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                processSection
                matchSection
                actionSection
                notesSection
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 500, height: 560)
        .navigationTitle("New Rule")
    }

    // MARK: - Process section

    private var processSection: some View {
        Section("Application") {
            HStack {
                TextField("Path to executable", text: $processPath)
                    .onChange(of: processPath) { _, path in
                        processName = URL(fileURLWithPath: path).lastPathComponent
                    }
                Button("Browse…") { showingFilePicker = true }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.application, .unixExecutable],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    processPath = url.path
                }
            }

            if !processName.isEmpty {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: processPath))
                        .resizable().frame(width: 20, height: 20)
                    Text(processName).foregroundStyle(.secondary)
                }
            }

            Toggle("Apply to all apps (wildcard)", isOn: Binding(
                get: { processPath == "*" },
                set: { processPath = $0 ? "*" : "" }
            ))
        }
    }

    // MARK: - Match section

    private var matchSection: some View {
        Section("Match") {
            Picker("Scope", selection: $matchType) {
                ForEach(MatchType.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }

            switch matchType {
            case .process:
                EmptyView()
            case .destination, .destinationAndPort:
                TextField("Hostname or IP address", text: $hostField)
                    .textContentType(.URL)
                if matchType == .destinationAndPort { portFieldView }
            case .destinationPort:
                portFieldView
            }
        }
    }

    private var portFieldView: some View {
        TextField("Port (1–65535)", text: $portField)
            .onChange(of: portField) { _, v in
                portField = String(v.filter(\.isNumber).prefix(5))
            }
    }

    // MARK: - Action section

    private var actionSection: some View {
        Section("Decision") {
            Picker("Action", selection: $action) {
                Label("Allow", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green).tag(RuleAction.allow)
                Label("Deny", systemImage: "xmark.shield.fill")
                    .foregroundStyle(.red).tag(RuleAction.deny)
            }
            .pickerStyle(.radioGroup)

            Picker("Duration", selection: $duration) {
                Text("Session (until quit)").tag(RuleDuration.session)
                Text("Permanent").tag(RuleDuration.permanent)
            }
            .pickerStyle(.radioGroup)
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        Section("Notes (optional)") {
            TextField("Description or reason for this rule", text: $notes, axis: .vertical)
                .lineLimit(2...)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let err = validationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                Divider()
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Rule") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    // MARK: - Save

    private func save() {
        validationError = nil

        // Validate process path.
        guard !processPath.isEmpty else {
            validationError = "Please choose an application or enter a path."
            return
        }

        // Build match.
        let match: RuleMatch
        switch matchType {
        case .process:
            match = .process
        case .destination:
            guard !hostField.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "Please enter a hostname or IP address."
                return
            }
            match = .destination(host: hostField.trimmingCharacters(in: .whitespaces))
        case .destinationPort:
            guard let port = UInt16(portField), port > 0 else {
                validationError = "Please enter a valid port number (1–65535)."
                return
            }
            match = .destinationPort(port: port)
        case .destinationAndPort:
            guard !hostField.trimmingCharacters(in: .whitespaces).isEmpty else {
                validationError = "Please enter a hostname or IP address."
                return
            }
            guard let port = UInt16(portField), port > 0 else {
                validationError = "Please enter a valid port number (1–65535)."
                return
            }
            match = .destinationAndPort(
                host: hostField.trimmingCharacters(in: .whitespaces),
                port: port)
        }

        let name = processPath == "*"
            ? "All Apps"
            : (processName.isEmpty ? URL(fileURLWithPath: processPath).lastPathComponent : processName)

        let rule = Rule(
            processName: name,
            processPath: processPath,
            action: action,
            duration: duration,
            match: match,
            notes: notes)

        ruleStore.add(rule)
        extensionClient.push(rule: rule)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    RuleCreatorView()
        .environmentObject(RuleStore())
        .environmentObject(ExtensionClient())
}
