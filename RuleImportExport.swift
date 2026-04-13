// MacSnitchApp/Services/RuleImportExport.swift
// Handles import and export of rules as JSON files via NSSavePanel / NSOpenPanel.

import AppKit
import UniformTypeIdentifiers

enum ImportExportError: LocalizedError {
    case exportFailed(Error)
    case importFailed(Error)
    case noFileSelected

    var errorDescription: String? {
        switch self {
        case .exportFailed(let e): return "Export failed: \(e.localizedDescription)"
        case .importFailed(let e): return "Import failed: \(e.localizedDescription)"
        case .noFileSelected:      return "No file was selected."
        }
    }
}

final class RuleImportExport {
    private let store: RuleStore
    private let extensionClient: ExtensionClient

    init(store: RuleStore, extensionClient: ExtensionClient) {
        self.store = store
        self.extensionClient = extensionClient
    }

    // MARK: - Export

    @MainActor
    func exportRules() async throws {
        let data = try store.exportRules()

        let panel = NSSavePanel()
        panel.title = "Export MacSnitch Rules"
        panel.nameFieldStringValue = "macsnitch-rules.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow!)
        guard response == .OK, let url = panel.url else { throw ImportExportError.noFileSelected }

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImportExportError.exportFailed(error)
        }
    }

    // MARK: - Import

    @MainActor
    func importRules() async throws -> Int {
        let panel = NSOpenPanel()
        panel.title = "Import MacSnitch Rules"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow!)
        guard response == .OK, let url = panel.url else { throw ImportExportError.noFileSelected }

        do {
            let data = try Data(contentsOf: url)
            let added = try store.importRules(from: data)
            // Push newly imported rules into the extension.
            for rule in store.rules.suffix(added) {
                extensionClient.push(rule: rule)
            }
            return added
        } catch let err as ImportExportError {
            throw err
        } catch {
            throw ImportExportError.importFailed(error)
        }
    }
}
