// MacSnitchApp/App.swift
// Main entry point. Owns all service singletons and wires them together.

import SwiftUI
import AppKit
import NetworkExtension
import Combine

@main
struct MacSnitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MacSnitch", id: "main") {
            MainContentView()
                .environmentObject(appDelegate.ruleStore)
                .environmentObject(appDelegate.logger)
                .environmentObject(appDelegate.extensionManager)
                .environmentObject(appDelegate.extensionClient)
                .environmentObject(appDelegate.blockListManager)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rules…")          { appDelegate.openMainWindow(tab: .rules) }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Connection Log…") { appDelegate.openMainWindow(tab: .log) }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Block Lists…")    { appDelegate.openMainWindow(tab: .blockLists) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Status")          { appDelegate.openMainWindow(tab: .status) }
                    .keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}

// MARK: - AppDelegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    // All services owned here — single lifecycle, shared across the whole app.
    let ruleStore        = RuleStore()
    let extensionClient  = ExtensionClient()
    let extensionManager = FilterExtensionManager()
    lazy var logger           = ConnectionLogger(store: ruleStore)
    lazy var blockListManager = BlockListManager(ruleStore: ruleStore, extensionClient: extensionClient)
    private lazy var xpcServer = XPCServer(delegate: self)

    // Status bar
    private var statusItem: NSStatusItem?
    private var toggleMenuItem: NSMenuItem?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon

        NotificationManager.shared.registerCategories()
        NotificationManager.shared.requestAuthorization()

        setupStatusBar()
        xpcServer.start()
        extensionClient.connect()

        // Seed extension cache with all stored permanent rules.
        for rule in ruleStore.rules { extensionClient.push(rule: rule) }

        extensionManager.checkStatus()

        // Keep the toggle menu item title in sync with extension state.
        extensionManager.$isEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.toggleMenuItem?.title = enabled ? "Disable MacSnitch" : "Enable MacSnitch"
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        extensionClient.clearSessionRules()
        ruleStore.clearSessionRules()
        xpcServer.stop()
    }

    // MARK: - Status bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "shield.fill",
                               accessibilityDescription: "MacSnitch")

        let menu = NSMenu()

        // Header showing current state
        let headerItem = NSMenuItem()
        headerItem.view = StatusHeaderView(manager: extensionManager)
        menu.addItem(headerItem)
        menu.addItem(.separator())

        // Navigation
        let rulesItem = NSMenuItem(title: "Rules…",
                                   action: #selector(openRules), keyEquivalent: "")
        rulesItem.target = self
        menu.addItem(rulesItem)

        let logItem = NSMenuItem(title: "Connection Log…",
                                 action: #selector(openLog), keyEquivalent: "")
        logItem.target = self
        menu.addItem(logItem)
        menu.addItem(.separator())

        // Toggle — title updates via Combine subscription above
        let toggle = NSMenuItem(title: "Disable MacSnitch",
                                action: #selector(toggleExtension), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        toggleMenuItem = toggle

        let loginItem = NSMenuItem(title: "Launch at Login",
                                   action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit MacSnitch",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func toggleLaunchAtLogin() {
        LaunchAtLoginManager.shared.toggle()
        // Update checkmark on next menu open
        if let menu = statusItem?.menu {
            for item in menu.items where item.action == #selector(toggleLaunchAtLogin) {
                item.state = LaunchAtLoginManager.shared.isEnabled ? .on : .off
            }
        }
    }

    @objc private func openRules()   { openMainWindow(tab: .rules) }
    @objc private func openLog()     { openMainWindow(tab: .log) }

    @objc private func toggleExtension() {
        extensionManager.isEnabled
            ? extensionManager.disable()
            : extensionManager.enable()
    }

    func openMainWindow(tab: MainTab) {
        NotificationCenter.default.post(name: .switchTab, object: tab)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - XPCServerDelegate

extension AppDelegate: XPCServerDelegate {

    func didReceivePrompt(connectionInfo: ConnectionInfo) async -> VerdictReply {
        // Fast path: existing rule matches — no prompt needed.
        if let match = ruleStore.verdict(for: connectionInfo) {
            let verdict: Verdict = match.action == .allow ? .allow : .deny
            logger.appendEntry(ConnectionLogEntry(
                connection: connectionInfo, verdict: verdict, ruleID: match.rule.id))
            if verdict == .deny {
                NotificationManager.shared.notifyBlocked(connection: connectionInfo)
            }
            return VerdictReply(verdict: verdict, rule: match.rule)
        }

        // Slow path: show the allow/deny prompt to the user.
        let reply = await ConnectionPromptCoordinator.shared.prompt(for: connectionInfo)

        if let rule = reply.rule {
            ruleStore.add(rule)
            if rule.duration != .once { extensionClient.push(rule: rule) }
        }

        logger.appendEntry(ConnectionLogEntry(
            connection: connectionInfo,
            verdict: reply.verdict,
            ruleID: reply.rule?.id))

        return reply
    }

    func didReceiveLogEntry(_ entry: ConnectionLogEntry) {
        logger.appendEntry(entry)
    }
}

// MARK: - Supporting types

enum MainTab: String, CaseIterable {
    case rules      = "Rules"
    case log        = "Log"
    case blockLists = "Block Lists"
    case status     = "Status"
}

extension Notification.Name {
    static let switchTab = Notification.Name("MacSnitch.switchTab")
}
