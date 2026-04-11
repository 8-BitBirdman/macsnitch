// MacSnitchApp/Views/RulesView.swift
// Settings window for viewing and managing persisted rules.

import SwiftUI

struct RulesView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @State private var searchText = ""
    @State private var selection: Rule.ID? = nil

    var filteredRules: [Rule] {
        guard !searchText.isEmpty else { return ruleStore.rules }
        return ruleStore.rules.filter {
            $0.processPath.localizedCaseInsensitiveContains(searchText) ||
            $0.action.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(filteredRules, selection: $selection) { rule in
                RuleRow(rule: rule)
            }
            .searchable(text: $searchText, prompt: "Filter rules…")
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        if let id = selection {
                            ruleStore.remove(id: id)
                            selection = nil
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selection == nil)
                }
            }
        } detail: {
            if let id = selection, let rule = ruleStore.rules.first(where: { $0.id == id }) {
                RuleDetailView(rule: rule)
            } else {
                ContentUnavailableView("Select a rule", systemImage: "shield.lefthalf.filled")
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

// MARK: - Row

struct RuleRow: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: rule.action == .allow ? "checkmark.shield.fill" : "xmark.shield.fill")
                .foregroundStyle(rule.action == .allow ? .green : .red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: rule.processPath).lastPathComponent)
                    .fontWeight(.medium)
                Text(matchDescription(rule.match))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(rule.duration.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
    }

    func matchDescription(_ match: RuleMatch) -> String {
        switch match {
        case .process: return "All connections"
        case .destination(let host): return "→ \(host)"
        case .destinationPort(let port): return "→ port \(port)"
        case .destinationAndPort(let host, let port): return "→ \(host):\(port)"
        }
    }
}

// MARK: - Detail

struct RuleDetailView: View {
    let rule: Rule

    var body: some View {
        Form {
            Section("Process") {
                LabeledContent("Path", value: rule.processPath)
            }
            Section("Action") {
                LabeledContent("Decision", value: rule.action.rawValue.capitalized)
                LabeledContent("Duration", value: rule.duration.rawValue.capitalized)
            }
            Section("Match") {
                LabeledContent("Scope", value: matchDescription(rule.match))
            }
            Section("Metadata") {
                LabeledContent("Created", value: rule.created.formatted())
                LabeledContent("ID", value: rule.id.uuidString)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    func matchDescription(_ match: RuleMatch) -> String {
        switch match {
        case .process: return "Any outbound connection"
        case .destination(let host): return "Destination \(host)"
        case .destinationPort(let port): return "Port \(port)"
        case .destinationAndPort(let host, let port): return "\(host):\(port)"
        }
    }
}
