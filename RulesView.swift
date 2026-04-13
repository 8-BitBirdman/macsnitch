// MacSnitchApp/Views/RulesView.swift
// Full rules management UI — list, detail, enable/disable, delete, import/export.

import SwiftUI

struct RulesView: View {
    @EnvironmentObject var ruleStore: RuleStore
    @EnvironmentObject var extensionClient: ExtensionClient
    @State private var searchText = ""
    @State private var selection: Rule.ID?
    @State private var filterAction: RuleAction? = nil
    @State private var showingImportError = false
    @State private var showingImportSuccess = false
    @State private var importedCount = 0
    @State private var errorMessage = ""

    @State private var showingRuleCreator = false

    private var importExport: RuleImportExport {
        RuleImportExport(store: ruleStore, extensionClient: extensionClient)
    }

    var filteredRules: [Rule] {
        ruleStore.rules
            .filter { rule in
                (filterAction == nil || rule.action == filterAction) &&
                (searchText.isEmpty
                 || rule.processName.localizedCaseInsensitiveContains(searchText)
                 || rule.processPath.localizedCaseInsensitiveContains(searchText)
                 || rule.match.displayString.localizedCaseInsensitiveContains(searchText))
            }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebar
        } detail: {
            detailPanel
        }
        .navigationTitle("MacSnitch Rules")
        .frame(minWidth: 750, minHeight: 450)
        .sheet(isPresented: $showingRuleCreator) {
            RuleCreatorView()
                .environmentObject(ruleStore)
                .environmentObject(extensionClient)
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: { Text(errorMessage) }
        .alert("Import Complete", isPresented: $showingImportSuccess) {
            Button("OK") {}
        } message: { Text("Imported \(importedCount) new rule(s).") }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filteredRules.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        .navigationTitle("Rules")
        .toolbar { sidebarToolbar }
        .searchable(text: $searchText, prompt: "Search rules…")
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Text("Show:")
                .font(.callout)
                .foregroundStyle(.secondary)
            Picker("Filter", selection: $filterAction) {
                Text("All").tag(nil as RuleAction?)
                Text("Allow").tag(RuleAction.allow as RuleAction?)
                Text("Deny").tag(RuleAction.deny as RuleAction?)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var ruleList: some View {
        List(filteredRules, selection: $selection) { rule in
            RuleRow(rule: rule)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteRule(rule)
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .contextMenu {
                    Toggle(isOn: Binding(
                        get: { rule.isEnabled },
                        set: { _ in toggleRule(rule) }
                    )) { Label("Enabled", systemImage: "checkmark") }
                    Divider()
                    Button(role: .destructive) { deleteRule(rule) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            searchText.isEmpty ? "No Rules" : "No Results",
            systemImage: "shield",
            description: Text(searchText.isEmpty
                ? "Rules you create will appear here."
                : "No rules match "\(searchText)".")
        )
        .frame(maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingRuleCreator = true } label: {
                Image(systemName: "plus")
            }
            .help("Create new rule")
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Import Rules…") { importRules() }
                Button("Export Rules…") { exportRules() }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        ToolbarItem(placement: .destructiveAction) {
            Button(role: .destructive) {
                if let id = selection { deleteRuleByID(id) }
            } label: {
                Image(systemName: "trash")
            }
            .disabled(selection == nil)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPanel: some View {
        if let id = selection, let rule = ruleStore.rules.first(where: { $0.id == id }) {
            RuleDetailView(rule: rule, onSave: { updated in
                ruleStore.update(updated)
                extensionClient.push(rule: updated)
            })
        } else {
            ContentUnavailableView("Select a Rule", systemImage: "shield.lefthalf.filled")
        }
    }

    // MARK: - Actions

    private func deleteRule(_ rule: Rule) {
        extensionClient.remove(ruleID: rule.id)
        ruleStore.remove(id: rule.id)
        if selection == rule.id { selection = nil }
    }

    private func deleteRuleByID(_ id: Rule.ID) {
        if let rule = ruleStore.rules.first(where: { $0.id == id }) { deleteRule(rule) }
    }

    private func toggleRule(_ rule: Rule) {
        var updated = rule
        updated = Rule(id: rule.id, created: rule.created,
                       processName: rule.processName, processPath: rule.processPath,
                       action: rule.action, duration: rule.duration, match: rule.match,
                       isEnabled: !rule.isEnabled, notes: rule.notes)
        ruleStore.update(updated)
        extensionClient.push(rule: updated)
    }

    private func exportRules() {
        Task {
            do { try await importExport.exportRules() }
            catch { errorMessage = error.localizedDescription; showingImportError = true }
        }
    }

    private func importRules() {
        Task {
            do {
                importedCount = try await importExport.importRules()
                showingImportSuccess = true
            } catch {
                errorMessage = error.localizedDescription
                showingImportError = true
            }
        }
    }
}

// MARK: - Rule Row

struct RuleRow: View {
    let rule: Rule

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(rule.isEnabled
                    ? (rule.action == .allow ? Color.green : Color.red)
                    : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(rule.processName)
                        .fontWeight(.medium)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    if !rule.isEnabled {
                        Text("disabled")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(rule.match.displayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(rule.action == .allow ? "Allow" : "Deny")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(rule.action == .allow ? .green : .red)
                Text(rule.duration.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
        .opacity(rule.isEnabled ? 1 : 0.6)
    }
}

// MARK: - Rule Detail / Edit View

struct RuleDetailView: View {
    @State var rule: Rule
    let onSave: (Rule) -> Void

    @State private var isDirty = false

    var body: some View {
        Form {
            Section("Process") {
                LabeledContent("Name", value: rule.processName)
                LabeledContent("Path", value: rule.processPath)
            }
            Section("Decision") {
                Picker("Action", selection: $rule.action) {
                    Text("Allow").tag(RuleAction.allow)
                    Text("Deny").tag(RuleAction.deny)
                }
                .onChange(of: rule.action) { _, _ in isDirty = true }

                Picker("Duration", selection: $rule.duration) {
                    ForEach(RuleDuration.allCases, id: \.self) { d in
                        Text(d.rawValue.capitalized).tag(d)
                    }
                }
                .onChange(of: rule.duration) { _, _ in isDirty = true }

                Toggle("Enabled", isOn: $rule.isEnabled)
                    .onChange(of: rule.isEnabled) { _, _ in isDirty = true }
            }
            Section("Match") {
                LabeledContent("Scope", value: rule.match.displayString)
            }
            Section("Notes") {
                TextField("Notes", text: $rule.notes, axis: .vertical)
                    .lineLimit(3...)
                    .onChange(of: rule.notes) { _, _ in isDirty = true }
            }
            Section("Metadata") {
                LabeledContent("Created", value: rule.created.formatted())
                LabeledContent("ID", value: rule.id.uuidString)
                    .font(.caption.monospaced())
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave(rule); isDirty = false }
                    .disabled(!isDirty)
            }
        }
    }
}
