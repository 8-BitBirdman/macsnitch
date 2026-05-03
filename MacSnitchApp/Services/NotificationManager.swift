// MacSnitchApp/Services/NotificationManager.swift
// Delivers macOS User Notifications when connections are blocked or when
// MacSnitch needs the user's attention (e.g. extension needs approval).

import UserNotifications
import AppKit
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "Notifications")

final class NotificationManager: NSObject {

    static let shared = NotificationManager()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { log.error("Notification auth error: \(error)") }
            log.info("Notification permission granted: \(granted)")
        }
    }

    // MARK: - Connection blocked notification

    /// Fired when a connection is auto-denied by a permanent rule while the app
    /// is in the background (i.e. the user didn't actively see a prompt).
    func notifyBlocked(connection: ConnectionInfo) {
        let content = UNMutableNotificationContent()
        content.title = "\(connection.processName) blocked"
        content.body  = "Attempted to connect to \(connection.displayDestination):\(connection.destinationPort)"
        content.sound = .default
        content.categoryIdentifier = Category.blocked
        content.userInfo = [
            "processPath": connection.processPath,
            "destination": connection.displayDestination,
        ]

        let req = UNNotificationRequest(
            identifier: "blocked-\(connection.id)",
            content: content,
            trigger: nil)   // deliver immediately

        center.add(req) { error in
            if let error { log.error("Failed to deliver notification: \(error)") }
        }
    }

    // MARK: - Extension needs approval

    func notifyNeedsApproval() {
        let content = UNMutableNotificationContent()
        content.title = "MacSnitch needs your approval"
        content.body  = "Open System Settings → Privacy & Security to allow the MacSnitch extension."
        content.sound = .default
        content.categoryIdentifier = Category.approval

        let req = UNNotificationRequest(
            identifier: "approval-needed",
            content: content,
            trigger: nil)
        center.add(req) { error in
            if let error { log.error("Failed to deliver notification: \(error)") }
        }
    }

    // MARK: - Categories

    private enum Category {
        static let blocked  = "BLOCKED"
        static let approval = "APPROVAL"
    }

    func registerCategories() {
        let showRule = UNNotificationAction(
            identifier: "SHOW_RULE",
            title: "Manage Rules",
            options: [.foreground])

        let blockedCategory = UNNotificationCategory(
            identifier: Category.blocked,
            actions: [showRule],
            intentIdentifiers: [],
            options: [])

        let openSettings = UNNotificationAction(
            identifier: "OPEN_SETTINGS",
            title: "Open System Settings",
            options: [.foreground])

        let approvalCategory = UNNotificationCategory(
            identifier: Category.approval,
            actions: [openSettings],
            intentIdentifiers: [],
            options: [])

        center.setNotificationCategories([blockedCategory, approvalCategory])
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Only show banner+sound if the main window is hidden.
        let windowVisible = NSApp.windows.contains { $0.isVisible }
        handler(windowVisible ? [] : [.banner, .sound])
    }

    /// Handle notification action taps.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler handler: @escaping () -> Void
    ) {
        switch response.actionIdentifier {
        case "SHOW_RULE":
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .switchTab, object: MainTab.rules)
                NSApp.activate(ignoringOtherApps: true)
            }
        case "OPEN_SETTINGS":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
        handler()
    }
}
