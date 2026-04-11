// MacSnitchApp/Services/FilterExtensionManager.swift
// Manages activation and deactivation of the MacSnitch System Extension
// using the SystemExtensions framework.

import Foundation
import SystemExtensions
import NetworkExtension
import OSLog

private let log = Logger(subsystem: "com.macsnitch.app", category: "ExtensionManager")

final class FilterExtensionManager: NSObject {
    private let extensionBundleID = "com.macsnitch.extension"

    // MARK: - Activation

    func activateIfNeeded() {
        NEFilterManager.shared().loadFromPreferences { [weak self] error in
            guard let self else { return }
            if let error {
                log.error("Failed to load filter preferences: \(error)")
                return
            }
            if NEFilterManager.shared().isEnabled {
                log.info("Filter already enabled")
            } else {
                self.activateExtension()
            }
        }
    }

    private func activateExtension() {
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
        log.info("Submitted activation request for \(self.extensionBundleID)")
    }

    func deactivate() {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: extensionBundleID,
            queue: .main
        )
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    // MARK: - Filter Configuration

    private func enableContentFilter() {
        let filterManager = NEFilterManager.shared()
        filterManager.localizedDescription = "MacSnitch Application Firewall"

        let providerConfig = NEFilterProviderConfiguration()
        providerConfig.filterSockets = true
        providerConfig.filterPackets = false

        filterManager.providerConfiguration = providerConfig
        filterManager.isEnabled = true

        filterManager.saveToPreferences { error in
            if let error {
                log.error("Failed to save filter preferences: \(error)")
            } else {
                log.info("Content filter enabled successfully")
            }
        }
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension FilterExtensionManager: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        log.info("Extension request finished with result: \(result.rawValue)")
        if result == .completed {
            enableContentFilter()
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        log.error("Extension request failed: \(error)")
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        log.info("Extension requires user approval in System Settings")
        // TODO: Show a notification guiding the user to System Settings > Privacy & Security
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        log.info("Replacing extension \(existing.bundleShortVersion) with \(ext.bundleShortVersion)")
        return .replace
    }
}
