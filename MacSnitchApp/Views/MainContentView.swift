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

    @State private var selectedTab: MainTab? = .rules

    var body: some View {
        NavigationSplitView {
            List(MainTab.allCases, id: \.self, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    Label(tab.rawValue, systemImage: tab.icon)
                        .font(.body.weight(.medium))
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        } detail: {
            if let tab = selectedTab {
                detailView(for: tab)
                    .navigationTitle(tab.rawValue)
                    .toolbar {
                        ToolbarItem(placement: .status) {
                            StatusIndicator(manager: extensionManager)
                        }
                    }
            } else {
                Text("Select a section")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    @ViewBuilder
    private func detailView(for tab: MainTab) -> some View {
        switch tab {
        case .rules:
            RulesView()
                .environmentObject(ruleStore)
                .environmentObject(extensionClient)
        case .log:
            ConnectionLogView()
                .environmentObject(logger)
        case .blockLists:
            BlockListView()
                .environmentObject(blockListManager)
        case .status:
            StatusView()
                .environmentObject(extensionManager)
                .environmentObject(logger)
        }
    }
}

private struct StatusIndicator: View {
    @ObservedObject var manager: FilterExtensionManager
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.isEnabled ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(manager.isEnabled ? "Monitoring Active" : "Monitoring Inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(100)
    }
}

extension MainTab {
    var icon: String {
        switch self {
        case .rules: return "shield.fill"
        case .log: return "list.bullet.rectangle.portrait"
        case .blockLists: return "xmark.shield.fill"
        case .status: return "info.circle.fill"
        }
    }
}

