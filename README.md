# 🛡️ MacSnitch

**The Modern, High-Performance Application Firewall for macOS.**

MacSnitch is a world-class security tool designed to give you absolute control over your Mac's network activity. Built with modern Swift, SwiftUI, and the latest macOS System Extension APIs, MacSnitch provides real-time auditing, intelligent filtering, and a premium user experience that feels like a native part of the operating system.

![MacSnitch Banner](https://raw.githubusercontent.com/8-BitBirdman/macsnitch/main/MacSnitchApp/Assets.xcassets/AppIcon.appiconset/icon.png)

---

## ✨ Key Features

### 🚀 High-Performance Filtering
*   **$O(1)$ Rule Lookups**: Our custom `RuleCache` uses indexed dictionaries to evaluate connections in microseconds, ensuring zero impact on your network speed.
*   **Batched Processing**: Supports massive blocklists (AdGuard, StevenBlack) with tens of thousands of domains using transactional SQLite and batched XPC communication.
*   **Self-Healing State**: Automatically re-synchronizes rules if the background extension restarts, ensuring consistent protection.

### 🛡️ Hardened Security
*   **Absolute Path Auditing**: Uses `proc_pidpath` (C-bridge) for spoof-proof process identification.
*   **Wildcard Host Matching**: Powerful `*.domain.com` matching for efficient subdomain filtering.
*   **Full Network Telemetry**: Every connection—even those matched by background rules—is audited and logged for total transparency.
*   **XPC Security**: Hardened inter-process communication with PID validation and secure Mach service registration.

### 🎨 Premium User Experience
*   **Glassmorphic HUDs**: A stunning card-based UI with Sidebar navigation and real-time status indicators.
*   **Real-time Dashboard**: Live charts and per-process traffic breakdowns using pre-calculated statistics.
*   **Smart Prompts**: Beautifully designed connection prompts with one-click rule creation.
*   **Native Integration**: Support for Launch at Login, Menu Bar status, and System Notifications.

---

## 🏗️ Architecture

MacSnitch is built on a robust, decoupled architecture:

1.  **MacSnitch App**: The main control center (SwiftUI). Manages the UI, rule persistence (SQLite via GRDB), and provides an XPC server for the extension.
2.  **MacSnitch Extension**: A high-privilege `NEFilterDataProvider` (System Extension). It intercepts every TCP/UDP packet, resolves hostnames in real-time, and enforces rules with extreme efficiency.
3.  **Rule Engine**: A hybrid engine that combines local memory speed with persistent SQL storage.

For a deep dive into the technical details, see [ARCHITECTURE.md](ARCHITECTURE.md).

---

## 🛠️ Building & Installation

### Prerequisites
*   macOS 13.0 or later
*   Xcode 15.0 or later
*   Python 3 (for project generation)

### Build Steps
1.  **Clone the repository**:
    ```bash
    git clone https://github.com/8-BitBirdman/macsnitch.git
    cd macsnitch
    ```
2.  **Generate the Xcode Project**:
    ```bash
    python3 generate_xcodeproj.py
    ```
3.  **Open and Sign**:
    *   Open `MacSnitch.xcodeproj`.
    *   In the "Signing & Capabilities" tab, select your **Development Team** for both `MacSnitchApp` and `MacSnitchExtension`.
4.  **Run**:
    *   Press `Cmd+R` to build and run the app.
    *   Click **Enable MacSnitch** in the Status menu or Dashboard to install the System Extension.

---

## 🤝 Contributing

We welcome contributions from the community! Whether you're fixing a bug, adding a feature, or improving documentation, please feel free to open a Pull Request.

---

## 📄 License

MacSnitch is released under the **GPL-3.0 License**. See [LICENSE](LICENSE) for more details.

---

**Crafted with 💖 for the macOS Community.**
