<div align="center">
  <img src="https://raw.githubusercontent.com/8-BitBirdman/macsnitch/main/MacSnitchApp/Assets.xcassets/AppIcon.appiconset/icon.png" alt="MacSnitch Logo" width="200"/>

  # 🛡️ MacSnitch

  **The Next-Generation, Zero-Trust Application Firewall for macOS.**

  [![macOS 13.0+](https://img.shields.io/badge/macOS-13.0%2B-blue.svg)](https://apple.com/macos)
  [![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138.svg)](https://swift.org)
  [![License: GPL-3.0](https://img.shields.io/badge/License-GPLv3-green.svg)](https://opensource.org/licenses/GPL-3.0)
  [![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()

  *Reclaim your privacy. Control your network. Experience uncompromised performance.*
</div>

---

## 📖 Table of Contents

- [Overview](#-overview)
- [Core Features](#-core-features)
- [How It Works](#-how-it-works)
- [Installation & Setup](#-installation--setup)
- [Usage Guide](#-usage-guide)
- [Architecture Deep Dive](#-architecture-deep-dive)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🌍 Overview

In an era where every application "phones home," **MacSnitch** puts you back in the driver's seat. It is a powerful, system-level application firewall built specifically for modern macOS. By leveraging Apple's latest `NetworkExtension` framework, MacSnitch intercepts network traffic at the kernel level, giving you absolute, granular control over which applications can access the internet and where they are allowed to connect.

Unlike legacy firewalls that rely on outdated kernel extensions (kexts) or resource-heavy packet inspection, MacSnitch is designed for **extreme performance** and **minimal resource footprint**, wrapped in a premium, native SwiftUI interface.

---

## ✨ Core Features

### 🔒 Zero-Trust Security
*   **Absolute Process Auditing**: Utilizing low-level C-bridges (`proc_pidpath`), MacSnitch identifies applications by their absolute binary path, neutralizing spoofing attempts by malicious actors.
*   **Granular Rule Engine**: Allow or block connections based on process, destination IP, hostname, or specific port combinations.
*   **Wildcard Domain Matching**: Seamlessly block entire ecosystems using regex-like wildcards (e.g., `*.analytics-provider.com`).

### ⚡ Blazing Performance
*   **$O(1)$ Microsecond Lookups**: The filtering engine uses a highly optimized, indexed dictionary cache. Legitimate traffic is allowed through in microseconds without ever hitting the disk.
*   **Transactional Bulk Updates**: Import massive, 100,000+ domain blocklists (like AdGuard or StevenBlack) in seconds. MacSnitch uses batched XPC communication and SQLite transactions to ensure your system never freezes.
*   **Asynchronous Telemetry**: Connection logging and rule hit-tracking happen in the background, keeping your network throughput at maximum capacity.

### 🎨 Premium, Native UI
*   **Glassmorphic Design**: Built entirely with SwiftUI, featuring native macOS visual effects, fluid animations, and a modern sidebar layout.
*   **Real-Time Dashboard**: Monitor your network health instantly with pre-calculated, aggregated statistics showing top active applications and destination hotspots.
*   **Smart Prompts**: Intuitive connection alerts that provide full context (app name, icon, destination, and protocol) allowing you to create permanent or session-only rules with a single click.

### 🤖 Intelligent Automation
*   **Auto-Resync**: If the background extension is ever updated or restarts, the app automatically re-establishes connection and pushes your entire rule database back into active memory.
*   **Automated Blocklist Refreshes**: Keep ad-tracking and malware domains at bay with automatic 24-hour background synchronization of your subscribed blocklists.
*   **System Safe-Defaults**: Pre-populated rules for essential macOS services (like `trustd` and `mDNSResponder`) ensure your core OS functionality never breaks unexpectedly.

---

## ⚙️ How It Works

MacSnitch operates using a decoupled architecture consisting of two main components:

1.  **The UI Application (`MacSnitchApp`)**: Your control center. It manages the SQLite database, presents the user interface, fetches blocklists, and handles the connection prompts.
2.  **The System Extension (`MacSnitchExtension`)**: A high-privilege, headless background process that lives in macOS's secure extension space. It evaluates every network packet against a lightning-fast in-memory cache.

These two components communicate securely via bidirectional XPC (Cross-Process Communication). For a comprehensive technical breakdown, please read our [Architecture Guide](ARCHITECTURE.md).

---

## 🛠️ Installation & Setup

### Prerequisites
*   macOS 13.0 (Ventura) or later.
*   Xcode 15.0+ (if building from source).
*   Python 3 (for project generation).

### Building from Source

MacSnitch uses a custom project generator to ensure deterministic builds and correct entitlement configurations for System Extensions.

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/8-BitBirdman/macsnitch.git
    cd macsnitch
    ```

2.  **Generate the Xcode Workspace**:
    ```bash
    python3 generate_xcodeproj.py
    ```
    *This script creates the `MacSnitch.xcodeproj` file and links all necessary Swift Package Manager dependencies (like GRDB).*

3.  **Configure Code Signing**:
    *   Open `MacSnitch.xcodeproj` in Xcode.
    *   Select the root project node, then go to the **Signing & Capabilities** tab.
    *   Select your **Development Team** for both the `MacSnitchApp` and `MacSnitchExtension` targets.
    *   *Note: Building a Network Extension requires a valid Apple Developer account.*

4.  **Build and Run**:
    *   Press `Cmd + R` to build the application.
    *   Upon first launch, the app will prompt you to install the System Extension.
    *   Open **System Settings > Privacy & Security** and click **Allow** for the MacSnitch extension.

---

## 🚀 Usage Guide

*   **Approving Connections**: When a new, unknown application tries to connect to the internet, MacSnitch will pause the connection and present a prompt. You can choose to Allow or Deny the connection once, for the current session, or permanently.
*   **Managing Rules**: Open the **Rules** tab (`Cmd+R`) to view, edit, or delete existing rules. You can see exactly how many times a rule has been triggered via the "Hit Count" metric.
*   **Importing Blocklists**: Navigate to the **Block Lists** tab (`Cmd+B`) to subscribe to remote hosts files (e.g., AdGuard DNS filters). MacSnitch will automatically convert these into wildcard block rules.
*   **Monitoring Traffic**: The **Connection Log** (`Cmd+L`) provides a historical, searchable audit trail of every packet that has entered or left your machine.

---

## 🤝 Contributing

We believe security tools should be open and collaborative. We welcome contributions of all kinds!

1.  Fork the repository.
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request.

Please ensure your code follows the existing style and that all tests pass.

---

## 📜 License

MacSnitch is distributed under the GNU General Public License v3.0. See the `LICENSE` file for more information.

---
<div align="center">
  <i>Built for the modern Mac. Defend your digital perimeter.</i>
</div>
