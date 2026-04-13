// MacSnitchApp/Services/FilterExtensionManager.swift
// Installs and enables the MacSnitch Network Extension using SystemExtensions framework.

import NetworkExtension
import SystemExtensions
import OSLog
import UserNotifications

private let log = Logger(subsystem: "com.macsnitch.app", category: "ExtensionManager")

final class FilterExtensionManager: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage = "Checking…"

    private let extensionBundleID = "com.macsnitch.extension"

    // MARK: - Public

    func checkStatus() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            guard let self else { return }
            if let error {
                log.error("loadFromPreferences: \(error)")
                self.statusMessage = "Error loading preferences"
                return
            }
            self.isEnabled = NEFilterManager.shared().isEnabled
            self.statusMessage = self.isEnabled ? "Active" : "Inactive"
        }
    }

    func enable() {
        let req = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
        statusMessage = "Requesting activation…"
    }

    func disable() {
        NEFilterManager.shared().isEnabled = false
        NEFilterManager.shared().saveToPreferences { [weak self] error in
            if let error {
                log.error("saveToPreferences: \(error)")
            } else {
                self?.isEnabled = false
                self?.statusMessage = "Inactive"
            }
        }
        let req = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleID, queue: .main)
        req.delegate = self
        OSSystemExtensionManager.shared.submitRequest(req)
    }

    // MARK: - Private

    private func enableContentFilter() {
        let fm = NEFilterManager.shared()
        fm.localizedDescription = "MacSnitch Application Firewall"
        let cfg = NEFilterProviderConfiguration()
        cfg.filterSockets = true
        cfg.filterPackets = false
        fm.providerConfiguration = cfg
        fm.isEnabled = true
        fm.saveToPreferences { [weak self] error in
            if let error {
                log.error("saveToPreferences: \(error)")
                self?.statusMessage = "Failed to enable"
            } else {
                self?.isEnabled = true
                self?.statusMessage = "Active"
                log.info("Content filter enabled")
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension FilterExtensionManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest,
                 didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("Extension request result: \(result.rawValue)")
        if result == .completed { enableContentFilter() }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Extension request failed: \(error)")
        statusMessage = "Extension error: \(error.localizedDescription)"
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        statusMessage = "Approval needed in System Settings → Privacy & Security"
        log.info("Needs user approval")
        NotificationManager.shared.notifyNeedsApproval()
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing extension \(existing.bundleShortVersion) → \(ext.bundleShortVersion)")
        return .replace
    }
}
