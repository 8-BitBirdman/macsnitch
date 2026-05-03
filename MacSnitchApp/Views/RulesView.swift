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
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                Divider().opacity(0.5)
                if filteredRules.isEmpty {
                    emptyState
                } else {
                    ruleList
                }
            }
            .frame(minWidth: 300, maxWidth: 400)
            .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
            
            Divider()
            
            detailPanel
                .frame(maxWidth: .infinity)
        }
        .toolbar { sidebarToolbar }
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

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search rules…", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .padding(16)
    }

    private var ruleList: some View {
        List(filteredRules, selection: $selection) { rule in
            RuleRow(rule: rule)
                .tag(rule.id)
                .listRowSeparator(.hidden)
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selection == rule.id ? Color.accentColor.opacity(0.1) : Color.clear)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                )
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
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.slash")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "No Rules" : "No Results")
                .font(.headline)
            Text(searchText.isEmpty 
                 ? "Rules you create will appear here." 
                 : "Try a different search.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingRuleCreator = true } label: {
                Label("Add Rule", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Import Rules…") { importRules() }
                Button("Export Rules…") { exportRules() }
                Divider()
                Picker("Filter", selection: $filterAction) {
                    Text("All Actions").tag(nil as RuleAction?)
                    Text("Allow Only").tag(RuleAction.allow as RuleAction?)
                    Text("Deny Only").tag(RuleAction.deny as RuleAction?)
                }
            } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
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
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(.quaternary)
                Text("Select a rule to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }

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
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: rule.processPath))
                .resizable()
                .interpolation(.high)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.processName)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.semibold)
                Text(rule.match.displayString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(rule.action == .allow ? "ALLOW" : "DENY")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(rule.action == .allow ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                    .foregroundStyle(rule.action == .allow ? .green : .red)
                    .cornerRadius(4)
                
                Text(rule.duration.rawValue.uppercased())
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .opacity(rule.isEnabled ? 1 : 0.5)
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
                LabeledContent("Hits", value: "\(rule.hitCount)")
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
