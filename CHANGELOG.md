# Changelog

All notable changes to MacSnitch will be documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
MacSnitch uses [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

### Added
- Initial project scaffold (Swift + SwiftUI + NetworkExtension)
- `NEFilterDataProvider` system extension intercepts all outbound TCP/UDP flows
- `NEFilterControlProvider` companion provider hosts app→extension XPC listener
- Shared in-memory `RuleCache` with thread-safe access, singleton across both providers
- Async reverse-DNS resolution (`DNSResolver`) with in-process cache — prompts show hostnames instead of raw IPs
- Floating allow/deny prompt panel (`ConnectionPromptView`)
  - Shows app icon, process name, path, PID, destination hostname, IP, port, protocol
  - Four scope options: per-process / per-host / per-port / exact host+port
  - Three duration options: once / until quit / permanent
  - Button labels update dynamically ("Allow Once", "Always Deny", etc.)
- `RuleStore` — SQLite persistence via GRDB with versioned migrations
  - Migrations: v1 initial schema, v2 indexes, v3 source port columns, v4 rule hit counter
  - Session rules held in memory, permanent rules written to `~/Library/Application Support/MacSnitch/macsnitch.sqlite`
- `ConnectionLogger` — live in-memory log (1,000 entries cap) synced to SQLite
- `ConnectionLogView` — Table view with time / verdict / app / destination / port / protocol columns
  - Live pause toggle, clear button, allow/deny filter, search
  - Running allowed/denied counters in toolbar
- `RulesView` — NavigationSplitView with:
  - Full-text search, allow/deny filter segmented control
  - Swipe-to-delete, context menu (enable/disable, delete)
  - Inline detail editor with Save button
  - Import/Export toolbar menu (JSON, via NSSavePanel / NSOpenPanel)
  - `+` button opens `RuleCreatorView` sheet
- `RuleCreatorView` — manual rule creation form
  - App browser with file picker
  - Wildcard (`*`) option for all apps
  - Scope picker matching the prompt options
  - Port and hostname validation
- `StatusView` — three-panel status UI:
  - Extension health card with animated indicator and enable/disable button
  - Session stats (total / allowed / denied / unique apps)
  - Per-process breakdown table (top 15 apps by connection count)
  - Top destinations bar chart (top 10 hosts)
- `AppStatsModel` — `@MainActor ObservableObject` aggregating per-process and per-destination connection stats
- `NotificationManager` — macOS User Notifications
  - Silent background-block notifications with "Manage Rules" action
  - Extension-needs-approval notification with "Open System Settings" action
- `FilterExtensionManager` — installs/activates the System Extension via `OSSystemExtensionRequest`, publishes `isEnabled` + `statusMessage`
- `ExtensionClient` — app-side XPC client pushes rule add/remove/session-clear into extension cache
- `XPCServer` — `NSXPCListener` hosted in the app, routes extension prompts to `ConnectionPromptCoordinator`
- `ConnectionPromptCoordinator` — serialises simultaneous prompts into a queue, builds `VerdictReply` + `Rule` from user decision
- `RuleImportExport` — JSON import with duplicate detection, JSON export with `NSSavePanel`
- `DatabaseMigrator` — versioned GRDB migration runner
- Menu bar status item with live indicator, quick links to Rules/Log, toggle extension
- `NotificationManager` wired into `AppDelegate` — fires blocked notification on auto-deny, approval notification when extension needs system approval
- GitHub Actions CI (`ci.yml`):
  - SwiftLint on every push/PR
  - `swift test` unit test job
  - Unsigned build job
  - Signed release archive + notarization + DMG on version tags
- Unit tests: rule matching (process / destination / port / exact / wildcard / disabled), `RuleCache` (hit / miss / remove / clearSession), `Codable` round-trip for all `RuleMatch` variants, import/export round-trip
- `SwiftLint` configuration (`.swiftlint.yml`)
- `Package.swift` SPM manifest with GRDB dependency
- `generate_xcodeproj.py` script (uses `xcodeproj` Ruby gem, falls back to printed instructions)
- Entitlements for both targets
- `Info.plist` for both targets
- `ExportOptions.plist` for signed distribution builds
- Full `ARCHITECTURE.md` with data flow diagram

### Known Limitations
- The `content-filter` Network Extension entitlement is restricted — must be requested from Apple before the extension can activate
- System Extensions require a Developer ID certificate and cannot run in a Mac App Store sandbox
- DNS queries themselves are not intercepted (would need `NEDNSProxyProvider`)
- The Xcode project file (`.xcodeproj`) must be created manually or via `generate_xcodeproj.py` — it is not committed to the repository

---

## Version History

_No releases yet._

[Unreleased]: https://github.com/yourname/macsnitch/compare/HEAD
