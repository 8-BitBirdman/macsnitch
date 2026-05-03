// NetworkExtension/main.swift
// Entry point for the MacSnitch System Extension process.
// NEProvider subclasses are registered here and started by the system.

import NetworkExtension

// Register both providers. The system will instantiate whichever is needed.
NEProvider.startSystemExtensionMode()

// Keep the process alive — NEProvider.startSystemExtensionMode() sets up the
// runloop internally, so we just need dispatchMain() to park this thread.
dispatchMain()
