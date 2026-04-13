# MacSnitch 🕵️

A macOS interactive application firewall — a native port of [OpenSnitch](https://github.com/evilsocket/opensnitch) for macOS, inspired by Little Snitch.

MacSnitch intercepts every outbound TCP/UDP connection and prompts you to allow or deny it, per-app, giving you full visibility and control over what leaves your machine.

## Features

- **Outbound connection interception** — every TCP/UDP flow is intercepted via `NEFilterDataProvider` before it hits the network
- **Interactive allow/deny prompt** — floating panel shows app icon, process path, resolved hostname, IP, port, and protocol
- **Granular rule scopes** — match by: process (any connection), destination host, destination port, or exact host+port
- **Rule durations** — once (no rule saved), session (until quit), permanent (saved to SQLite)
- **Rule persistence** — SQLite database via GRDB; survives restarts
- **Connection log** — live table of every intercepted connection with verdict, process, host, port, and timestamp
- **Rules management UI** — search, filter, enable/disable, edit, delete rules without restarting
- **Import/export** — JSON export via Save panel, import with duplicate detection
- **Reverse DNS** — destination IPs are resolved to hostnames in the background before the prompt appears
- **Menu bar** — lives entirely in the menu bar, no Dock icon

## Architecture

```
┌──────────────────────────────────────────┐
│             MacSnitchApp                 │
│  ┌──────────────┐  ┌──────────────────┐  │
│  │ Menu Bar /   │  │ MainContentView  │  │
│  │ StatusItem   │  │  ├ RulesView     │  │
│  └──────┬───────┘  │  ├ LogView       │  │
│         │  XPC     │  └ StatusView    │  │
│  ┌──────▼───────┐  └──────────────────┘  │
│  │  XPCServer   │                        │
│  │  RuleStore ──────── SQLite (GRDB)     │
│  │  ConnLogger  │                        │
│  └──────┬───────┘                        │
└─────────┼────────────────────────────────┘
          │ XPC (NSXPCConnection)
┌─────────┼────────────────────────────────┐
│  MacSnitchExtension (System Extension)   │
│  ┌──────▼──────────────────────────────┐ │
│  │ FilterProvider (NEFilterDataProvider│ │
│  │  · pauses flows                     │ │
│  │  · checks RuleCache                 │ │
│  │  · reverse-DNS resolves IPs         │ │
│  │  · prompts app via XPC              │ │
│  └─────────────────────────────────────┘ │
│  ┌──────────────────────────────────────┐ │
│  │ FilterControlProvider                │ │
│  │  · receives rule updates from app   │ │
│  └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
         │
   macOS Network Stack
```

## Requirements

- macOS 13.0+
- Xcode 15+
- Apple Developer account (System Extensions require a provisioning profile)
- **Content filter entitlement** — request from Apple: https://developer.apple.com/contact/request/network-extension-content-filter

## Project Structure

```
macsnitch/
├── MacSnitchApp/
│   ├── App.swift                      # Entry point, AppDelegate, XPC wiring
│   ├── Views/
│   │   ├── MainContentView.swift      # Tab container
│   │   ├── ConnectionPromptView.swift # Allow/deny floating panel
│   │   ├── RulesView.swift            # Rules list + detail editor
│   │   ├── ConnectionLogView.swift    # Live connection log table
│   │   └── StatusView.swift          # Extension health + stats
│   └── Services/
│       ├── RuleStore.swift            # SQLite persistence (GRDB)
│       ├── ConnectionLogger.swift     # Log buffer + SQLite log
│       ├── XPCServer.swift            # XPC listener (app side)
│       ├── ExtensionClient.swift      # XPC client → extension
│       ├── ConnectionPromptCoordinator.swift
│       ├── FilterExtensionManager.swift
│       └── RuleImportExport.swift
├── NetworkExtension/
│   ├── main.swift                     # Extension entry point
│   ├── FilterProvider.swift           # NEFilterDataProvider
│   ├── FilterControlProvider.swift    # NEFilterControlProvider + XPC listener
│   ├── RuleCache.swift                # Shared in-memory rule cache
│   └── DNSResolver.swift             # Async reverse-DNS with cache
├── Shared/
│   └── IPCMessages.swift             # ConnectionInfo, Rule, Verdict, XPC protocols
├── Configuration/
│   ├── MacSnitchApp.entitlements
│   ├── MacSnitchExtension.entitlements
│   ├── MacSnitchApp-Info.plist
│   └── MacSnitchExtension-Info.plist
├── Tests/
│   └── MacSnitchTests.swift          # Rule matching + cache unit tests
├── Scripts/
│   └── generate_xcodeproj.py         # Generates .xcodeproj (requires xcodeproj gem)
├── Package.swift                      # SPM manifest + GRDB dependency
├── Makefile
└── docs/
    └── ARCHITECTURE.md
```

## Setup

```bash
# 1. Generate the Xcode project
python3 Scripts/generate_xcodeproj.py
# or: gem install xcodeproj && ruby Scripts/generate.rb

# 2. Open in Xcode and add GRDB via SPM
open MacSnitch.xcodeproj
# File → Add Package Dependencies → https://github.com/groue/GRDB.swift (~> 6.0)
# Add to MacSnitchApp target only

# 3. Set your Team ID in both targets' Signing settings

# 4. Enable System Extension developer mode (once per Mac)
make dev-mode

# 5. Build and run
make build
```

## Checklist

- [x] Project scaffold
- [x] Network Extension intercepts outbound connections
- [x] Menu bar prompt: allow / deny with once / session / permanent durations
- [x] Rule persistence (SQLite via GRDB)
- [x] Rules management UI (search, filter, enable/disable, edit, delete)
- [x] Per-process, per-domain, per-IP, per-port rule granularity
- [x] Temporary (session) vs permanent rules
- [x] Connection log viewer (live table, filter, clear)
- [x] Import/export rules (JSON)
- [x] Reverse DNS resolution
- [x] Unit tests (rule matching, cache, codability)

## License

GPL-3.0 — same as OpenSnitch.
