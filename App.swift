// MacSnitchApp/App.swift
// Menu bar application entry point.

import SwiftUI
import NetworkExtension
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "App")

@main
struct MacSnitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — we live in the menu bar.
        Settings {
            RulesView()
                .environmentObject(appDelegate.ruleStore)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let ruleStore = RuleStore()
    private var xpcServer: XPCServer?
    private var extensionManager: FilterExtensionManager?
    private var pendingPrompts: [UUID: CheckedContinuation<VerdictReply, Never>] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        xpcServer = XPCServer(delegate: self)
        xpcServer?.start()
        extensionManager = FilterExtensionManager()
        extensionManager?.activateIfNeeded()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "shield.fill", accessibilityDescription: "MacSnitch")
            button.action = #selector(togglePopover)
            button.target = self
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Rules…", action: #selector(openRules), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MacSnitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func togglePopover() {}
    @objc private func openRules() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - XPC Delegate

extension AppDelegate: XPCServerDelegate {
    func didReceivePrompt(connectionInfo: ConnectionInfo) async -> VerdictReply {
        // Show prompt UI and await user decision.
        return await ConnectionPromptCoordinator.shared.prompt(for: connectionInfo)
    }
}
