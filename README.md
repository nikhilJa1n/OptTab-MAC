# <img src="screenshots/app_icon.png" width="48" height="48" align="center" style="border-radius:10px; margin-right:10px; box-shadow: 0 4px 12px rgba(0,0,0,0.15);" /> OptTab

<p align="left">
  <a href="https://apple.com"><img src="https://img.shields.io/badge/platform-macOS%2014.0%2B-blue.svg?style=flat-square" alt="Platform" /></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/language-Swift%205.9-orange.svg?style=flat-square" alt="Language" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg?style=flat-square" alt="License" /></a>
  <a href="https://github.com/nikhilJa1n/OptTab-MAC/releases"><img src="https://img.shields.io/github/v/release/nikhilJa1n/OptTab-MAC?style=flat-square" alt="Latest Release" /></a>
</p>

**OptTab** is a next-generation window manager and interactive switcher HUD designed to replace the default macOS app switcher and dock experiences. Built natively in Swift and SwiftUI for macOS 14+ and macOS 15 Sequoia, it introduces a glassmorphic interface, dynamic multi-row grid layouts, multi-window tab grouping, and hardware-accelerated isolated window previews—all running as a zero-latency, lightweight background agent.

---

## 🌟 Key Features

*   **Smart MRU Sorting**: Replaces unstable OS Z-ordering. The `"Recently Used"` list sorts strictly by your active window history (`mruWindowIDs`), ensuring the most recently active window is always selected first.
*   **Multi-Window & Tab Grouping**: Preserves separate real OS windows for multi-window apps (Terminal, Chrome, Finder, VS Code) as individual cards while automatically merging duplicate internal tabs.
*   **Dual Capture Pipeline**: Combines single-batch `SCShareableContent` pre-fetching with WindowServer compositor fallback (`fallbackLegacyCapture`) so background/occluded windows (e.g. Chrome) **always** render clean thumbnail snapshots.
*   **Parallel Multi-Core Engine**: Scans accessibility trees in parallel across CPU cores with a **50ms hard IPC messaging timeout** (`AXUIElementSetMessagingTimeout`), preventing slow or unresponsive apps from stalling `Option + Tab`.
*   **Dynamic 2D Grid & 100% Uncropped Previews**: Toggle between horizontal rows and 2D multi-row grids with customizable column counts, thumbnail scaling (up to 140%+), and uncropped (`.fit`) full-window previews.
*   **Aero Action Panel & Resource Widgets**: Instantly Close, Minimize, Maximize, or Force Quit applications (`W` / `M` / `F` / `Q`) alongside real-time CPU and RAM resource monitors.
*   **Interactive Dock Previews**: Hover over active Dock icons to inspect live window preview grids of background applications.

---

## ⌨️ Control & Shortcuts Guide

| Action | Shortcut / Gesture |
| :--- | :--- |
| **Open Switcher / Cycle Forward** | `⌥ + Tab` |
| **Cycle Backward** | `⌥ + ⇧ + Tab` (Option + Shift + Tab) |
| **Arrow Key Navigation** | `←` / `→` (Horizontal) or `↑` / `↓` (Vertical Grid) |
| **Select Highlighted Window** | Release `⌥` (or press `Space` / `Enter` if pinned) |
| **Cancel / Dismiss HUD** | Press `⎋ (Esc)` |
| **Close / Minimize / Maximize Card** | Press `W` (Close), `M` (Minimize), `F` (Full Screen / Maximize), `Q` (Quit) |

---

## ⚙️ Requirements & Security Model

*   **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0 (Sequoia) or newer.
*   **Security & Privacy Policy**:
    *   OptTab operates **entirely locally**. No screen data, window titles, keystrokes, or process lists are ever transmitted, saved, or sent over a network.
    *   **Accessibility API**: Required to retrieve window titles and control windows (minimize, maximize, close, and snap).
    *   **Screen Recording Permission**: Required by `ScreenCaptureKit` and macOS Window Server to display isolated switcher card thumbnails.

---

## 🛠️ Build & Installation

### Prerequisites
*   Xcode 15.0 or newer (Swift 5.9+ compiler tools).

### Building from Source

To compile and package OptTab:

1.  Clone the repository:
    ```bash
    git clone https://github.com/nikhilJa1n/OptTab-MAC.git
    cd OptTab-MAC
    ```

2.  Run the build script:
    ```bash
    chmod +x build.sh
    ./build.sh
    ```

This generates **`OptTab.dmg`**. Drag-and-drop the app bundle inside it to your `/Applications` directory.

---

## 🛡️ License & Contributing

Licensed under the [MIT License](LICENSE). Contributions, bug reports, and feature pull requests are always welcome!
