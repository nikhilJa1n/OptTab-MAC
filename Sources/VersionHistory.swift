import Foundation
import SwiftUI

public struct VersionRelease: Identifiable {
    public let id = UUID()
    public let version: String
    public let releaseDate: String
    public let isCurrent: Bool
    public let summary: String
    public let features: [String]
    public let fixes: [String]
}

public struct VersionHistory {
    public static let releases: [VersionRelease] = [
        VersionRelease(
            version: "3.0",
            releaseDate: "July 2026",
            isCurrent: true,
            summary: "Add version history feature with detailed release notes and update scripts for automation",
            features: [
                "Add version history feature with detailed release notes and update scripts for automation",
                "Add app icon caching and improve window image capture logic"
            ],
            fixes: [
                
            ]
        ),
                                                                VersionRelease(
            version: "2.7",
            releaseDate: "July 2026",
            isCurrent: false,
            summary: "Multi-window tab grouping, 3-tier window targeting, shortcut auto-recovery, and 20x performance boost.",
            features: [
                "Preserves separate real OS windows for Terminal, Chrome, & Finder as individual cards",
                "Hybrid AX & Bounds matching automatically merges tab duplicates & filters nag popups",
                "Multi-Tier AppleScript Window Matcher (ID → Title → Position) for 100% reliable window raising",
                "Automatic Event Tap recovery on timeout/system load & wake notification handler",
                "20x faster window scanning (~5ms) and 1ms fast-path thumbnail snapshots",
                "Direct 'Send Logs to Dev' diagnostic option in settings",
                "Complete Version History & What's New release notes view"
            ],
            fixes: [
                "Resolved issue where selecting a secondary Terminal window raised the first window",
                "Fixed Option+Tab shortcut occasionally freezing after sleep or heavy CPU load",
                "Fixed duplicate Sublime Text nag popup cards in switcher list"
            ]
        ),
        VersionRelease(
            version: "2.6",
            releaseDate: "July 2026",
            isCurrent: false,
            summary: "Grid Switcher HUD layout, card thumbnail rendering, and keyboard shortcuts.",
            features: [
                "2D Multi-row Grid Switcher layout mode",
                "Real-time window thumbnail previews with rounded glassmorphic cards",
                "Arrow key (←/→/↑/↓) navigation & keyboard shortcuts (W/M/F/Q)",
                "Multi-monitor active space Z-order tracking"
            ],
            fixes: [
                "Improved Z-order tracking when switching between apps across spaces"
            ]
        ),
        VersionRelease(
            version: "2.5",
            releaseDate: "July 2026",
            isCurrent: false,
            summary: "Accessibility tree fallback matching and automatic GitHub update checking.",
            features: [
                "Automatic check for updates on startup via GitHub releases",
                "AX tree title & role fallback matching",
                "Start at login system configuration"
            ],
            fixes: [
                "Fixed window title matching for Chromium browser windows"
            ]
        ),
        VersionRelease(
            version: "2.4",
            releaseDate: "June 2026",
            isCurrent: false,
            summary: "One Window Per App / Tabbed window grouping option.",
            features: [
                "Option to merge tabbed windows of the same application",
                "Window action shortcuts"
            ],
            fixes: [
                "Fixed helper window leaks in CGWindowList"
            ]
        ),
        VersionRelease(
            version: "2.3",
            releaseDate: "June 2026",
            isCurrent: false,
            summary: "MRU (Most Recently Used) window ordering & macOS Dock integration.",
            features: [
                "Most Recently Used (MRU) Z-order sorting",
                "Customizable hotkey combination recorder"
            ],
            fixes: [
                "Initial release improvements"
            ]
        )
    ]
}
