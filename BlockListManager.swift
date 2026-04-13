// MacSnitchApp/Services/BlockListManager.swift
// Imports domain blocklists (hosts format or plain newline-separated)
// and creates deny rules for every domain in the list.
//
// Supports:
//   - Standard hosts format:  0.0.0.0 ads.example.com
//   - Plain list:             ads.example.com
//   - URLs to fetch remotely
//
// Well-known free blocklists:
//   https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
//   https://someonewhocares.org/hosts/hosts

import Foundation
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "BlockList")

// MARK: - BlockList

struct BlockList: Identifiable, Codable {
    let id: UUID
    var name: String
    var source: BlockListSource
    var isEnabled: Bool
    var domainCount: Int
    var lastUpdated: Date?

    init(id: UUID = UUID(), name: String, source: BlockListSource,
         isEnabled: Bool = true, domainCount: Int = 0, lastUpdated: Date? = nil) {
        self.id = id; self.name = name; self.source = source
        self.isEnabled = isEnabled; self.domainCount = domainCount
        self.lastUpdated = lastUpdated
    }
}

enum BlockListSource: Codable {
    case url(String)
    case file(String)   // absolute path

    var displayString: String {
        switch self {
        case .url(let u):  return u
        case .file(let p): return URL(fileURLWithPath: p).lastPathComponent
        }
    }
}

// MARK: - BlockListManager

@MainActor
final class BlockListManager: ObservableObject {
    @Published private(set) var lists: [BlockList] = []
    @Published var isImporting = false
    @Published var lastError: String?

    private let ruleStore: RuleStore
    private let extensionClient: ExtensionClient
    private let storageURL: URL

    static let builtIn: [(name: String, url: String)] = [
        ("StevenBlack Unified Hosts",
         "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"),
        ("Dan Pollock's Hosts",
         "https://someonewhocares.org/hosts/zero/hosts"),
        ("AdGuard DNS filter",
         "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt"),
    ]

    init(ruleStore: RuleStore, extensionClient: ExtensionClient) {
        self.ruleStore = ruleStore
        self.extensionClient = extensionClient
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacSnitch")
        self.storageURL = dir.appendingPathComponent("blocklists.json")
        load()
    }

    // MARK: - Public API

    /// Import a remote URL blocklist.
    func addRemote(name: String, urlString: String) async {
        guard let url = URL(string: urlString) else {
            lastError = "Invalid URL: \(urlString)"; return
        }
        isImporting = true
        defer { isImporting = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let domains = parse(data: data)
            var list = BlockList(name: name, source: .url(urlString), domainCount: domains.count,
                                 lastUpdated: Date())
            lists.append(list)
            save()
            await applyDomains(domains, listID: list.id)
            log.info("Imported \(domains.count) domains from \(urlString)")
        } catch {
            lastError = "Failed to fetch \(urlString): \(error.localizedDescription)"
            log.error("\(error)")
        }
    }

    /// Import a local file blocklist.
    func addFile(name: String, fileURL: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let data = try Data(contentsOf: fileURL)
            let domains = parse(data: data)
            let list = BlockList(name: name, source: .file(fileURL.path),
                                 domainCount: domains.count, lastUpdated: Date())
            lists.append(list)
            save()
            await applyDomains(domains, listID: list.id)
            log.info("Imported \(domains.count) domains from \(fileURL.lastPathComponent)")
        } catch {
            lastError = "Failed to read file: \(error.localizedDescription)"
        }
    }

    /// Re-fetch and re-apply all enabled remote lists.
    func refreshAll() async {
        for list in lists where list.isEnabled {
            if case .url(let urlString) = list.source {
                await addRemote(name: list.name, urlString: urlString)
            }
        }
    }

    func remove(id: UUID) {
        lists.removeAll { $0.id == id }
        // Remove all rules whose notes reference this list ID.
        let toRemove = ruleStore.rules.filter { $0.notes.contains(id.uuidString) }
        for rule in toRemove {
            extensionClient.remove(ruleID: rule.id)
            ruleStore.remove(id: rule.id)
        }
        save()
    }

    func toggle(id: UUID) {
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[idx].isEnabled.toggle()
        // Enable/disable all rules belonging to this list.
        let listID = id.uuidString
        for rule in ruleStore.rules where rule.notes.contains(listID) {
            var updated = rule
            updated = Rule(id: rule.id, created: rule.created,
                           processName: rule.processName, processPath: rule.processPath,
                           action: rule.action, duration: rule.duration, match: rule.match,
                           isEnabled: lists[idx].isEnabled, notes: rule.notes)
            ruleStore.update(updated)
            extensionClient.push(rule: updated)
        }
        save()
    }

    // MARK: - Parsing

    private func parse(data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var domains: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces)
            if parts.count >= 2 {
                // hosts format: 0.0.0.0 domain.com
                let domain = parts[1].lowercased()
                if isValidDomain(domain) { domains.append(domain) }
            } else if parts.count == 1 {
                // plain list
                let domain = parts[0].lowercased()
                if isValidDomain(domain) { domains.append(domain) }
            }
        }
        return Array(Set(domains)).sorted() // deduplicate
    }

    private func isValidDomain(_ d: String) -> Bool {
        guard d.count > 3, d.contains("."),
              !d.hasPrefix("localhost"), !d.hasPrefix("0.0.0.0"),
              !d.hasPrefix("127."), !d.hasPrefix("::") else { return false }
        return d.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
    }

    // MARK: - Applying domains as rules

    private func applyDomains(_ domains: [String], listID: UUID) async {
        let noteTag = "blocklist:\(listID.uuidString)"
        // Remove old rules for this list first.
        let old = ruleStore.rules.filter { $0.notes.contains(noteTag) }
        for rule in old { extensionClient.remove(ruleID: rule.id); ruleStore.remove(id: rule.id) }

        // Bulk-insert new deny rules (wildcard process).
        for domain in domains {
            let rule = Rule(
                processName: "*",
                processPath: "*",
                action: .deny,
                duration: .permanent,
                match: .destination(host: domain),
                notes: noteTag)
            ruleStore.add(rule)
            extensionClient.push(rule: rule)
        }
        log.info("Applied \(domains.count) block rules for list \(listID)")
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([BlockList].self, from: data)
        else { return }
        lists = loaded
    }

    private func save() {
        try? JSONEncoder().encode(lists).write(to: storageURL, options: .atomic)
    }
}
