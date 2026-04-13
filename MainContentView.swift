// MacSnitchApp/Views/MainContentView.swift
// Root tab container. Receives all service objects via EnvironmentObject
// and distributes them to the appropriate tab views.

import SwiftUI

struct MainContentView: View {
    @EnvironmentObject var ruleStore:        RuleStore
    @EnvironmentObject var logger:           ConnectionLogger
    @EnvironmentObject var extensionManager: FilterExtensionManager
    @EnvironmentObject var extensionClient:  ExtensionClient
    @EnvironmentObject var blockListManager: BlockListManager

    @State private var selectedTab: MainTab = .rules

    var body: some View {
        TabView(selection: $selectedTab) {

            // ── Rules ──────────────────────────────────────────────────────
            RulesView()
                .environmentObject(ruleStore)
                .environmentObject(extensionClient)
                .tabItem { Label("Rules", systemImage: "shield.fill") }
                .tag(MainTab.rules)

            // ── Connection Log ─────────────────────────────────────────────
            ConnectionLogView()
                .environmentObject(logger)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
                .tag(MainTab.log)

            // ── Block Lists ────────────────────────────────────────────────
            BlockListView()
                .environmentObject(blockListManager)
                .tabItem { Label("Block Lists", systemImage: "xmark.shield") }
                .tag(MainTab.blockLists)

            // ── Status ─────────────────────────────────────────────────────
            StatusView()
                .environmentObject(extensionManager)
                .environmentObject(logger)
                .tabItem { Label("Status", systemImage: "info.circle") }
                .tag(MainTab.status)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { note in
            if let tab = note.object as? MainTab { selectedTab = tab }
        }
        .frame(minWidth: 860, minHeight: 520)
    }
}
