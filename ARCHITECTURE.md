# 🏗️ MacSnitch Architecture

This document provides a deep technical overview of how MacSnitch operates at the system level.

---

## 🛰️ System Extension Design

MacSnitch utilizes a `NEFilterDataProvider` system extension to achieve low-level network interception. Unlike traditional app extensions, this system extension runs as a separate background process managed by `launchd` and the `OSSystemExtensionManager`.

### Why System Extensions?
*   **Persistence**: They run independently of the main app, providing protection even if the UI is closed.
*   **Privilege**: They have the necessary entitlements to intercept all system-wide TCP/UDP traffic.
*   **Security**: They are sandboxed (via the Network Extension sandbox) and require explicit user approval in System Settings.

### The Filter Lifecycle
1.  **Interception**: `FilterProvider.handleNewFlow(_:)` is called for every outbound connection.
2.  **Fast Path**: The extension checks its internal `RuleCache`. If a match is found (Allowed/Blocked), it returns a verdict in $O(1)$ time.
3.  **Slow Path**: If no rule exists, the flow is paused. The extension resolves the destination IP via `DNSResolver` and sends an XPC prompt to the app.
4.  **Verdict**: Once the user decides (or the app's `RuleStore` finds a match), the extension resumes the flow with the final verdict.

---

## 🚄 Rule Matching Engine

The rule matching logic is designed for extreme scale and accuracy.

### Subdomain Wildcards
Rules support the `*.domain.com` pattern. The matching algorithm:
1.  Splits hostnames into domain segments.
2.  Performs reverse suffix matching to catch subdomains.
3.  Ensures that `*.google.com` matches `api.google.com` but not `fakegoogle.com`.

### Multi-Level Caching
*   **Persistent**: All rules are stored in a SQLite database via **GRDB.swift**.
*   **In-Memory (App)**: The `RuleStore` maintains a hot cache of rules for rapid dashboard rendering.
*   **In-Memory (Extension)**: The `RuleCache` maintains a thread-safe, indexed dictionary of rules for $O(1)$ packet filtering.

---

## 🔒 XPC Communication & Security

MacSnitch uses two dedicated Mach services for inter-process communication:

1.  **`com.macsnitch.app.xpc`**: Extension → App (Requesting verdicts, reporting logs).
2.  **`com.macsnitch.extension.xpc`**: App → Extension (Syncing rules, clearing sessions).

### Hardened Handshaking
*   The `XPCServer` validates the `auditToken` of every connecting process.
*   It verifies the `processIdentifier` (PID) to ensure only the authorized MacSnitch extension can communicate with the app.
*   All data is serialized using `Codable` and `JSONEncoder`, ensuring a type-safe and robust protocol.

---

## 📊 Connection Auditing & Stats

Connection logging is performed asynchronously to avoid blocking the network path.

1.  The extension reports every connection to the app's `XPCServer`.
2.  The `ConnectionLogger` batches these updates and pre-calculates dashboard statistics (top apps, traffic ratios).
3.  The UI consumes these pre-calculated stats, allowing the dashboard to remain responsive even with tens of thousands of connections per day.

---

## 🛠️ Project Tooling

### The Project Generator (`generate_xcodeproj.py`)
Because macOS system extensions require complex, deterministic PBXProject configurations (entitlements, system extension embedding, Mach service registration), we use a custom Python script to generate the `.xcodeproj`. 

This ensures that:
*   Build configurations are consistent across environments.
*   Deterministic IDs are used for all files and phases.
*   All required frameworks and SPM dependencies are correctly linked.

---

## 🛡️ Future Roadmap
*   **NEDNSProxyProvider**: Moving DNS resolution into its own provider for even greater visibility.
*   **Process Grouping**: Aggregating rules by application bundle rather than absolute path.
*   **Traffic Shaping**: Adding the ability to rate-limit specific applications.
