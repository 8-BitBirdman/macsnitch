// MacSnitchApp/Services/FilterExtensionManager.swift
// Installs and enables the MacSnitch Network Extension.
// All @Published mutations are dispatched to the main queue because
// NEFilterManager and OSSystemExtensionRequest callbacks fire on arbitrary queues.

import NetworkExtension
import SystemExtensions
import UserNotifications
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "ExtensionManager")

@MainActor
final class FilterExtensionManager: NSObject, ObservableObject {
    @Published private(set) var isEnabled    = false
    @Published private(set) var statusMessage = "Checking…"

    private let extensionBundleID = "com.macsnitch.extension"

    // MARK: - Public

    func checkStatus() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    log.error("loadFromPreferences: \(error)")
                    self?.statusMessage = "Error loading preferences"
                    return
                }
                let enabled = NEFilterManager.shared().isEnabled
                self?.isEnabled      = enabled
                self?.statusMessage  = enabled ? "Active" : "Inactive"
            }
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
            DispatchQueue.main.async {
                if let error {
                    log.error("saveToPreferences: \(error)")
                } else {
                    self?.isEnabled      = false
                    self?.statusMessage  = "Inactive"
                }
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
        cfg.filterSockets  = true
        cfg.filterPackets  = false
        fm.providerConfiguration = cfg
        fm.isEnabled = true
        fm.saveToPreferences { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    log.error("saveToPreferences: \(error)")
                    self?.statusMessage = "Failed to enable"
                } else {
                    self?.isEnabled     = true
                    self?.statusMessage = "Active"
                    log.info("Content filter enabled")
                }
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate
// Callbacks from OSSystemExtensionManager fire on the queue passed to the request
// (we pass .main above), so @MainActor properties are safe to mutate directly here.

extension FilterExtensionManager: OSSystemExtensionRequestDelegate {

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("Extension request result: \(result.rawValue)")
        if result == .completed {
            Task { @MainActor in self.enableContentFilter() }
        }
    }

    nonisolated func request(_ request: OSSystemExtensionRequest,
                             didFailWithError error: Error) {
        log.error("Extension request failed: \(error)")
        Task { @MainActor in
            self.statusMessage = "Extension error: \(error.localizedDescription)"
        }
    }

    nonisolated func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("Needs user approval")
        Task { @MainActor in
            self.statusMessage = "Approval needed in System Settings → Privacy & Security"
            NotificationManager.shared.notifyNeedsApproval()
        }
    }

    nonisolated func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing extension \(existing.bundleShortVersion) → \(ext.bundleShortVersion)")
        return .replace
    }
}
