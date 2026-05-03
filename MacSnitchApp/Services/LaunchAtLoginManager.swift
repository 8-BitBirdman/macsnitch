// MacSnitchApp/Services/LaunchAtLoginManager.swift
// Controls whether MacSnitch launches automatically at login using SMAppService
// (macOS 13+ replacement for the deprecated SMLoginItemSetEnabled).

import ServiceManagement
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "LaunchAtLogin")

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published private(set) var isEnabled: Bool = false

    private let service = SMAppService.mainApp

    private init() {
        refresh()
    }

    // MARK: - Public

    func enable() {
        do {
            try service.register()
            isEnabled = true
            log.info("Launch at login enabled")
        } catch {
            log.error("Failed to enable launch at login: \(error)")
        }
    }

    func disable() {
        do {
            try service.unregister()
            isEnabled = false
            log.info("Launch at login disabled")
        } catch {
            log.error("Failed to disable launch at login: \(error)")
        }
    }

    func toggle() {
        isEnabled ? disable() : enable()
    }

    func refresh() {
        isEnabled = service.status == .enabled
    }
}
