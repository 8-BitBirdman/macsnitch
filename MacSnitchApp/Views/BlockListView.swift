// MacSnitchApp/Views/BlockListView.swift
// UI for managing domain blocklists — add, remove, refresh, toggle.

import SwiftUI
import UniformTypeIdentifiers

struct BlockListView: View {
    @EnvironmentObject var blockListManager: BlockListManager

    @State private var showingAddSheet   = false
    @State private var showingFilePicker = false
    @State private var showingError      = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerView
                
                if blockListManager.lists.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(blockListManager.lists) { list in
                            BlockListRow(list: list)
                                .environmentObject(blockListManager)
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar { toolbarItems }
        .sheet(isPresented: $showingAddSheet) {
            AddBlockListSheet()
                .environmentObject(blockListManager)
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await blockListManager.addFile(name: url.lastPathComponent, fileURL: url) }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { blockListManager.lastError = nil }
        } message: {
            Text(blockListManager.lastError ?? "")
        }
        .onChange(of: blockListManager.lastError) { _, err in
            showingError = err != nil
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Block Lists")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Automatically block known trackers and ads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            
            if blockListManager.isImporting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "xmark.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.quaternary)
            
            VStack(spacing: 8) {
                Text("No Block Lists Active")
                    .font(.headline)
                Text("Add a list to enhance your privacy automatically.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Browse Built-in Lists") { showingAddSheet = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingAddSheet = true } label: {
                Label("Add List", systemImage: "plus")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await blockListManager.refreshAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(blockListManager.isImporting || blockListManager.lists.isEmpty)
        }
    }
}

// MARK: - Row

private struct BlockListRow: View {
    let list: BlockList
    @EnvironmentObject var blockListManager: BlockListManager

    var body: some View {
        HStack(spacing: 16) {
            Toggle("", isOn: Binding(
                get: { list.isEnabled },
                set: { _ in blockListManager.toggle(id: list.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 4) {
                Text(list.name)
                    .font(.headline)
                    .foregroundStyle(list.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 6) {
                    Image(systemName: "link")
                    Text(list.source.displayString)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(list.domainCount) domains")
                    .font(.system(.subheadline, design: .rounded))
                    .fontWeight(.semibold)
                
                if let updated = list.lastUpdated {
                    Text("Updated \(updated.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .contextMenu {
            if case .url(let urlString) = list.source,
               let url = URL(string: urlString) {
                Button("Open Source…") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button(role: .destructive) { blockListManager.remove(id: list.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add sheet

private struct AddBlockListSheet: View {
    @EnvironmentObject var blockListManager: BlockListManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBuiltIn: Int? = nil
    @State private var customName = ""
    @State private var customURL  = ""
    @State private var isAdding   = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Block List")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Select a recommended list or enter a custom URL.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            List {
                Section("Recommended") {
                    ForEach(BlockListManager.builtIn.indices, id: \.self) { i in
                        let item = BlockListManager.builtIn[i]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.url)
                                    .font(.caption2).foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if selectedBuiltIn == i {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedBuiltIn = i; customURL = ""; customName = "" }
                    }
                }

                Section("Custom") {
                    TextField("List Name", text: $customName)
                        .onChange(of: customName) { _, _ in selectedBuiltIn = nil }
                    TextField("URL (https://…)", text: $customURL)
                        .onChange(of: customURL)  { _, _ in selectedBuiltIn = nil }
                }
            }
            .listStyle(.insetGrouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: add) {
                    if isAdding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Add List")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdd || isAdding)
            }
            .padding(24)
            .background(VisualEffectView(material: .content, blendingMode: .withinWindow))
        }
        .frame(width: 500, height: 500)
    }

    private var canAdd: Bool {
        selectedBuiltIn != nil || (!customName.isEmpty && !customURL.isEmpty)
    }

    private func add() {
        isAdding = true
        if let i = selectedBuiltIn {
            let item = BlockListManager.builtIn[i]
            Task {
                await blockListManager.addRemote(name: item.name, urlString: item.url)
                dismiss()
            }
        } else {
            Task {
                await blockListManager.addRemote(name: customName, urlString: customURL)
                dismiss()
            }
        }
    }
}
