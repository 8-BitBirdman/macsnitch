# Contributing to MacSnitch

Thanks for your interest! Here's how to get set up.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Xcode | 15+ | Mac App Store |
| Swift | 5.9+ | Bundled with Xcode |
| Apple Developer account | Any | [developer.apple.com](https://developer.apple.com) |
| SwiftLint | any | `brew install swiftlint` |
| xcpretty (optional) | any | `gem install xcpretty` |

## The content-filter entitlement

MacSnitch uses `NEFilterDataProvider`, which requires a **restricted entitlement** from Apple. You will not be able to activate the extension without it.

To develop without it:
1. Request access: https://developer.apple.com/contact/request/network-extension-content-filter
2. In the meantime you can work on everything in `MacSnitchApp/` — the UI, RuleStore, views, and services — without the extension running. The XPC server will just never receive prompts.

## First-time setup

```bash
# 1. Clone
git clone https://github.com/yourname/macsnitch.git
cd macsnitch

# 2. Generate .xcodeproj (requires: gem install xcodeproj)
python3 Scripts/generate_xcodeproj.py

# 3. Open in Xcode
open MacSnitch.xcodeproj

# 4. Add GRDB via SPM
#    File → Add Package Dependencies…
#    URL: https://github.com/groue/GRDB.swift  Version: ~> 6.0
#    Target: MacSnitchApp only

# 5. Set your Team in both targets' Signing & Capabilities

# 6. Enable System Extension developer mode (one-time per Mac)
make dev-mode   # runs: sudo systemextensionsctl developer on

# 7. Build & run
make build
```

## Running tests

Tests do not require the extension entitlement.

```bash
swift test
# or
make test
```

## Project layout

```
MacSnitchApp/       App process (SwiftUI, menu bar, SQLite)
  Views/            SwiftUI views
  Services/         Business logic, XPC, persistence
  Models/           Observable data models
NetworkExtension/   System Extension process
Shared/             Types used by both processes
Tests/              XCTest unit tests
Configuration/      Entitlements, Info.plists
Scripts/            Dev tooling
.github/workflows/  CI
```

## Adding a new rule match type

1. Add a new case to `RuleMatch` in `Shared/IPCMessages.swift`
2. Handle it in `RuleCache.matches()` (`NetworkExtension/RuleCache.swift`)
3. Handle it in `RuleStore.ruleMatches()` (`MacSnitchApp/Services/RuleStore.swift`)
4. Add a UI option in `ConnectionPromptView` and `RuleCreatorView`
5. Add a unit test in `Tests/MacSnitchTests.swift`

## Adding a database migration

In `MacSnitchApp/Services/DatabaseMigrator.swift`, register a new migration **after** all existing ones:

```swift
migrator.registerMigration("v5_my_change") { db in
    try db.alter(table: "rules") { t in
        t.add(column: "myNewColumn", .text).defaults(to: "")
    }
}
```

Migrations run in registration order and are never re-run.

## Code style

- Follow Swift API design guidelines
- Run `make lint` before opening a PR — CI will reject violations
- Keep files focused: one primary type per file
- All public types must have a doc comment

## Pull request checklist

- [ ] `make lint` passes with no warnings
- [ ] `make test` passes
- [ ] New behaviour has a unit test
- [ ] CHANGELOG.md updated under `[Unreleased]`
- [ ] No force-unwraps (`!`) added without a comment explaining why it's safe

## Secrets for release CI

To enable the release pipeline in your fork, add these repository secrets:

| Secret | Description |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded `.p12` Developer ID cert |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `KEYCHAIN_PASSWORD` | Arbitrary password for the CI keychain |
| `DEVELOPMENT_TEAM` | Your 10-character Apple Team ID |
| `APPLE_ID` | Apple ID email for notarization |
| `APPLE_APP_PASSWORD` | App-specific password for notarization |
