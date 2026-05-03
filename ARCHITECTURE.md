# 🏗️ MacSnitch Architecture: Deep Dive

This document provides a comprehensive technical overview of MacSnitch's internal design, data flows, and security model. It is intended for contributors, security researchers, and developers looking to understand how a modern macOS application firewall operates at scale.

---

## 🗺️ High-Level Design

MacSnitch employs a classic Out-of-Process architecture mandated by Apple's Endpoint Security and Network Extension frameworks. This ensures that the core filtering logic remains isolated, secure, and highly privileged.

```text
┌──────────────────────────────┐        XPC (Mach Services)       ┌──────────────────────────────┐
│                              │ ◄──────────────────────────────► │                              │
│       MacSnitchApp           │    com.macsnitch.app.xpc         │    MacSnitchExtension        │
│      (User Interface)        │                                  │     (System Process)         │
│                              │ ◄──────────────────────────────► │                              │
│  • SwiftUI Dashboards         │    com.macsnitch.extension.xpc   │  • NEFilterDataProvider      │
│  • SQLite Persistence (GRDB) │                                  │  • Network Interception      │
│  • Blocklist Management      │                                  │  • In-Memory Rule Cache      │
│  • User Prompts              │                                  │  • DNS Resolution            │
└──────────────────────────────┘                                  └──────────────────────────────┘
```

---

## 🛡️ The System Extension (`NEFilterDataProvider`)

The heart of MacSnitch is the `FilterProvider` class, running as a headless daemon.

### The Interception Lifecycle
1.  **Packet Capture**: The macOS kernel routes every outbound TCP/UDP socket creation request to `FilterProvider.handleNewFlow(_:)`.
2.  **Context Extraction**: The extension extracts the remote IP, remote port, and the originating application's Audit Token.
3.  **Path Resolution**: Using the C-function `proc_pidpath`, the extension converts the Audit Token's PID into an absolute, un-spoofable binary path (e.g., `/usr/bin/curl`).
4.  **The Fast Path ($O(1)$)**: The connection parameters are hashed and checked against the `RuleCache`. If a definitive `Allow` or `Deny` rule exists, the verdict is returned to the kernel in microseconds.
5.  **The Slow Path (Async)**: If no rule exists, the flow is put into a `.pause()` state. The extension performs a reverse-DNS lookup to find the hostname and sends a prompt request to the User App via XPC.

### Consolidation for Reliability
To prevent lifecycle race conditions inherent in macOS System Extensions, MacSnitch consolidates both the Data Provider (packet interception) and the Control Provider (XPC rule updates) into a single, unified `FilterProvider` class.

---

## 🚄 The Rule Engine & Persistence Layer

MacSnitch balances the need for permanent storage with the requirement for microsecond network filtering.

### 1. SQLite Persistence (`MacSnitchApp`)
*   **GRDB.swift**: The app uses GRDB for thread-safe, transactional SQLite database management.
*   **Schema**: Rules and Connection Logs are stored in normalized tables. The database handles complex queries for dashboard rendering (e.g., sorting top destinations or identifying inactive rules).

### 2. In-Memory Cache (`MacSnitchExtension`)
*   **Indexed Lookup**: The extension maintains a highly optimized dictionary: `[String: [Rule]]`, keyed by the absolute process path. This eliminates $O(N)$ linear scanning.
*   **Wildcard Evaluation**: When a process matches, the engine evaluates destination rules, supporting powerful regex-like wildcard suffix matching (e.g., `*.tracking.com`).

### 3. Batched Synchronization
When importing a 50,000-domain blocklist, writing and transmitting rules one-by-one would freeze the OS. MacSnitch uses:
*   **SQL Transactions**: Bulk inserts into SQLite.
*   **Batched XPC**: Transmitting arrays of rules (`[Data]`) over the XPC channel to the extension, reducing IPC overhead by 99%.

---

## 🔐 Inter-Process Communication (XPC) Security

Because the System Extension runs with high privileges, the XPC bridge must be hardened against privilege escalation attacks.

*   **Bidirectional Proxies**: 
    *   The App listens on `com.macsnitch.app.xpc` (to receive prompts and logs).
    *   The Extension listens on `com.macsnitch.extension.xpc` (to receive rule updates).
*   **Audit Token Validation**: The App's `XPCServer` validates the `processIdentifier` of any connecting client, ensuring it only accepts commands from the officially signed extension binary.
*   **Auto-Resync Mechanism**: XPC connections can drop. If the extension crashes or is updated, the App's `ExtensionClient` detects the reconnection and automatically pushes the entire persistent SQLite rule database back into the extension's empty RAM cache.

---

## 📊 Telemetry and UI Performance

A firewall generates massive amounts of data. MacSnitch ensures the UI remains at 60fps regardless of network load.

*   **Asynchronous Logging**: When the extension makes a "Fast Path" decision, it does not block the network flow to log it. Instead, it dispatches an asynchronous XPC message to the app.
*   **Pre-Calculated Aggregation**: The `ConnectionLogger` inside the App doesn't just store logs; it pre-calculates the active `ProcessStats` and `DestinationStats` every time a new log arrives.
*   **Reactive Rendering**: The SwiftUI `StatusView` simply binds to these pre-calculated arrays, meaning rendering the dashboard is an $O(1)$ operation, even if there are millions of connection logs.

---

## 🛠️ Build Tooling (`generate_xcodeproj.py`)

Configuring a macOS System Extension project requires precise orchestration of Entitlements, Build Phases (Embedding), and Mach Service bindings. 

Instead of relying on fragile, manually configured `.xcodeproj` files, MacSnitch uses a custom Python generator. This script:
1.  Scans the directory for all Swift source files.
2.  Generates deterministic UUIDs for PBX targets.
3.  Links necessary System Frameworks and SPM dependencies (GRDB).
4.  Produces a clean, portable `MacSnitch.xcodeproj` tailored exactly to the current source tree.
