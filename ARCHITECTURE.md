# MacSnitch Architecture

## Overview

MacSnitch is a macOS application firewall that intercepts outbound network connections and prompts the user to allow or deny them. It is a native macOS port of [OpenSnitch](https://github.com/evilsocket/opensnitch).

## Components

### 1. Network Extension (`MacSnitchExtension`)

A **System Extension** implementing `NEFilterDataProvider`. This is the kernel-adjacent component that Apple provides for content filtering on macOS. It:

- Receives every new TCP/UDP socket flow before it reaches the network
- Looks up the originating process via the flow's audit token
- Checks a local rule cache for a known verdict
- If no rule exists, pauses the flow and sends a prompt to the app over XPC
- Resumes the flow with the verdict once the user decides

**Key APIs:**
- `NetworkExtension.NEFilterDataProvider`
- `NetworkExtension.NEFilterSocketFlow`
- `SystemExtensions.OSSystemExtensionRequest`

### 2. MacSnitch App (`MacSnitchApp`)

A **menu bar SwiftUI app** that:

- Hosts an XPC listener to receive prompts from the extension
- Shows a floating panel (`NSPanel`) with connection details and allow/deny buttons
- Manages rules in a `RuleStore` (SQLite via GRDB, falling back to JSON)
- Pushes rule changes back to the extension's cache over a separate XPC connection
- Provides a settings window (`RulesView`) for managing saved rules

### 3. Shared (`Shared/`)

Swift types shared between both targets (extension + app):
- `ConnectionInfo` — describes an intercepted connection
- `Rule`, `RuleAction`, `RuleMatch`, `RuleDuration` — rule model
- `Verdict` — allow/deny
- `MacSnitchAppXPCProtocol`, `MacSnitchExtensionXPCProtocol` — XPC contracts
- `XPC` constants (mach service names)

## Data Flow

```
[TCP/UDP socket opened by any app]
          │
          ▼
[NEFilterDataProvider.handleNewFlow()]
          │
          ├── Rule cache hit? ──► Resume with cached verdict
          │
          └── No rule ──► Pause flow
                              │
                              ▼
                    [XPC → MacSnitchApp]
                              │
                              ▼
                    [ConnectionPromptView shown]
                              │
                    [User clicks Allow / Deny]
                              │
                              ▼
                    [VerdictReply → Extension over XPC]
                              │
                              ├── Cache rule if "always"
                              │
                              └── Resume paused flow with verdict
```

## IPC: XPC

Two XPC mach services:

| Service | Direction | Purpose |
|---|---|---|
| `com.macsnitch.app.xpc` | Extension → App | Send connection prompt, receive verdict |
| `com.macsnitch.extension.xpc` | App → Extension | Push rule updates |

## Rule Model

Rules are matched in order. A rule consists of:
- **processPath** — absolute path of the executable (or `*` for wildcard)
- **action** — `allow` or `deny`
- **duration** — `once`, `session`, or `permanent`
- **match** — one of:
  - `.process` — matches any connection from this process
  - `.destination(host:)` — matches a specific IP or hostname
  - `.destinationPort(port:)` — matches a specific port
  - `.destinationAndPort(host:port:)` — exact match

## Known Limitations / TODO

- Hostname resolution: the extension receives raw IP addresses. Reverse DNS lookup is needed to show human-readable destinations.
- eBPF: not available on macOS; `NEFilterDataProvider` is the Apple-sanctioned equivalent.
- The extension cannot see DNS queries; a `NEDNSProxyProvider` would be needed for DNS-level blocking.
- App requires Developer ID + notarization + System Extension entitlement for distribution.

## Entitlements Required

### App target
- `com.apple.developer.system-extension.install` — to install the system extension
- `com.apple.security.network.client` — for XPC

### Extension target
- `com.apple.developer.network-extension.content-filter` — to act as an `NEFilterDataProvider`
- Requires a specific provisioning profile from Apple (content filter entitlement is restricted)

## Development Setup

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/)
2. Request the **content filter** network extension entitlement from Apple
3. Create App ID + provisioning profiles for both targets with the required entitlements
4. In Xcode: Product → Scheme → Edit Scheme → set `System Extension` to `enabled`
5. On your dev Mac: `systemextensionsctl developer on` (disables SIP extension checks in dev)
6. Build & run the app target; accept the prompt in System Settings → Privacy & Security

## Dependencies

- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite for rule persistence (add via SPM)
- Apple frameworks: `NetworkExtension`, `SystemExtensions`, `SwiftUI`, `OSLog`
