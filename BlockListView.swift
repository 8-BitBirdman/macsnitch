// MacSnitchApp/Views/BlockListView.swift
// UI for managing domain blocklists — add, remove, refresh, toggle.

import SwiftUI

struct BlockListView: View {
    @EnvironmentObject var blockListManager: BlockListManager

    @State private var showingAddSheet   = false
    @State private var showingFilePicker = false
    @State private var showingError      = false

    var body: some View {
        VStack(spacing: 0) {
            if blockListManager.lists.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("Block Lists")
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

    // MARK: - List

    private var listContent: some View {
        List {
            ForEach(blockListManager.lists) { list in
                BlockListRow(list: list)
                    .environmentObject(blockListManager)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Block Lists", systemImage: "xmark.shield")
        } description: {
            Text("Add a block list to automatically deny connections to known ad, tracker, or malware domains.")
        } actions: {
            Button("Add Built-in List") { showingAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Add from URL…")  { showingAddSheet = true }
                Button("Import File…")  { showingFilePicker = true }
            } label: { Image(systemName: "plus") }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                Task { await blockListManager.refreshAll() }
            } label: {
                Label("Refresh All", systemImage: "arrow.clockwise")
            }
            .disabled(blockListManager.isImporting || blockListManager.lists.isEmpty)
            .help("Re-fetch and apply all remote lists")
        }
        if blockListManager.isImporting {
            ToolbarItem(placement: .automatic) {
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - Row

private struct BlockListRow: View {
    let list: BlockList
    @EnvironmentObject var blockListManager: BlockListManager

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { list.isEnabled },
                set: { _ in blockListManager.toggle(id: list.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 3) {
                Text(list.name).fontWeight(.medium)
                    .foregroundStyle(list.isEnabled ? .primary : .secondary)
                Text(list.source.displayString)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(list.domainCount) domains")
                    .font(.callout).foregroundStyle(.secondary)
                if let updated = list.lastUpdated {
                    Text(updated.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                blockListManager.remove(id: list.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            if case .url(let urlString) = list.source,
               let url = URL(string: urlString) {
                Button("Open in Browser") { NSWorkspace.shared.open(url) }
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
            Form {
                Section("Built-in Lists") {
                    ForEach(BlockListManager.builtIn.indices, id: \.self) { i in
                        let item = BlockListManager.builtIn[i]
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).fontWeight(.medium)
                                Text(item.url)
                                    .font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if selectedBuiltIn == i {
                                Image(systemName: "checkmark").foregroundStyle(.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectedBuiltIn = i; customURL = ""; customName = "" }
                    }
                }

                Section("Custom URL") {
                    TextField("Name", text: $customName)
                        .onChange(of: customName) { _, _ in selectedBuiltIn = nil }
                    TextField("https://…", text: $customURL)
                        .onChange(of: customURL)  { _, _ in selectedBuiltIn = nil }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add") { add() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canAdd || isAdding)
            }
            .padding(16)
        }
        .frame(width: 480, height: 420)
        .navigationTitle("Add Block List")
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
