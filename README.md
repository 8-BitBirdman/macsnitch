# MacSnitch 🕵️

A macOS interactive application firewall — a native port of [OpenSnitch](https://github.com/evilsocket/opensnitch) for macOS, inspired by Little Snitch.

MacSnitch intercepts outbound network connections and prompts you to allow or deny them per-app, giving you full visibility and control over what leaves your machine.

## Architecture

```
┌─────────────────────────────────────────────┐
│              MacSnitch.app                  │
│  ┌──────────────┐    ┌─────────────────┐   │
│  │  Menu Bar UI │    │   Rules Manager │   │
│  │  (SwiftUI)   │    │   (SQLite)      │   │
│  └──────┬───────┘    └────────┬────────┘   │
│         │  XPC                │            │
└─────────┼─────────────────────┼────────────┘
          │                     │
┌─────────┼─────────────────────┼────────────┐
│  MacSnitchExtension (System Extension)      │
│  ┌──────▼──────────────────────────────┐   │
│  │  NEFilterDataProvider               │   │
│  │  - Intercepts all TCP/UDP flows     │   │
│  │  - Resolves PID → process name      │   │
│  │  - Consults rule cache              │   │
│  │  - Prompts app via XPC if needed    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
          │
    macOS Network Stack
```

## Features (Planned)

- [x] Project scaffold
- [ ] Network Extension intercepts outbound connections
- [ ] Menu bar prompt: allow / deny / always allow / always deny
- [ ] Rule persistence (SQLite)
- [ ] Rules management UI
- [ ] Per-process, per-domain, per-IP, per-port rule granularity
- [ ] Temporary (session) vs permanent rules
- [ ] Connection log viewer
- [ ] Import/export rules

## Requirements

- macOS 13.0+
- Xcode 15+
- Apple Developer account (System Extensions require notarization)

## Project Structure

```
macsnitch/
├── MacSnitchApp/           # SwiftUI menu bar application
│   ├── Views/              # UI components
│   ├── Models/             # Data models
│   └── Services/           # XPC client, rule engine
├── NetworkExtension/       # NEFilterDataProvider system extension
├── Shared/                 # Types shared between app and extension
└── docs/                   # Architecture & dev notes
```

## Development Setup

```bash
# Clone
git clone https://github.com/yourname/macsnitch.git
cd macsnitch

# Open in Xcode
open MacSnitch.xcodeproj

# Build & run (requires signing)
make build
```

> **Note:** System Extensions must be signed with a valid Apple Developer certificate and require SIP configuration in development. See `docs/DEVELOPMENT.md` for setup instructions.

## License

GPL-3.0 — same as OpenSnitch.
