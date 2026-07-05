import Cocoa
import CoreGraphics

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let appIcon: NSImage?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        return lhs.id == rhs.id
    }
}

class WindowList {
    static func getWindows(showAllSpacesOverride: Bool? = nil, showMinimizedOverride: Bool? = nil) -> [WindowInfo] {
        // Gather onscreen Z-order rank from active space to sort raw lists in MRU order
        var onscreenZOrder: [CGWindowID: Int] = [:]
        let onscreenOptions = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        if let onscreenList = CGWindowListCopyWindowInfo(onscreenOptions, kCGNullWindowID) as? [[String: Any]] {
            for (index, info) in onscreenList.enumerated() {
                if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                    onscreenZOrder[windowID] = index
                }
            }
        }
        
        let showMinimized = showMinimizedOverride ?? (UserDefaults.standard.object(forKey: "showMinimized") as? Bool ?? true)
        let showAllSpaces = showAllSpacesOverride ?? (UserDefaults.standard.object(forKey: "showAllSpaces") as? Bool ?? false)
        
        let options: CGWindowListOption
        if showMinimized || showAllSpaces {
            options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
        } else {
            options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        }
        
        guard let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        // Build set of valid window IDs using accessibility tree of regular applications
        var validAXWindowIDs: Set<CGWindowID> = []
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy == .regular {
                let appRef = AXUIElementCreateApplication(app.processIdentifier)
                var windowsValue: AnyObject?
                if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                   let axWindows = windowsValue as? [AXUIElement] {
                    for axWindow in axWindows {
                        // Check role: must be AXWindow
                        var roleValue: AnyObject?
                        if AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleValue) == .success,
                           let role = roleValue as? String, role != kAXWindowRole {
                            continue
                        }
                        
                        // Check subrole: must be Standard, Dialog, or empty
                        var subroleValue: AnyObject?
                        if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                           let subrole = subroleValue as? String {
                            let allowed = (subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole || subrole.isEmpty)
                            if !allowed {
                                continue
                            }
                        }
                        
                        // Check close and minimize buttons: standard windows must have close or minimize controls
                        var closeButtonValue: AnyObject?
                        let hasClose = AXUIElementCopyAttributeValue(axWindow, kAXCloseButtonAttribute as CFString, &closeButtonValue) == .success && closeButtonValue != nil
                        
                        var minimizeButtonValue: AnyObject?
                        let hasMinimize = AXUIElementCopyAttributeValue(axWindow, kAXMinimizeButtonAttribute as CFString, &minimizeButtonValue) == .success && minimizeButtonValue != nil
                        
                        if !hasClose && !hasMinimize {
                            continue
                        }
                        
                        if let id = getWindowID(from: axWindow) {
                            validAXWindowIDs.insert(id)
                        }
                    }
                }
            }
        }
        
        var windows: [WindowInfo] = []
        let currentPid = ProcessInfo.processInfo.processIdentifier
        
        for info in windowListInfo {
            // Get window layer. Normal apps are in layer 0.
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            
            // Get window ID
            guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else {
                continue
            }
            
            // Get owner PID
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            
            // Filter out our own app
            if pid == currentPid {
                continue
            }
            
            // Get owner Name (App Name)
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if ownerName.isEmpty {
                continue
            }
            
            // Filter out common background/system overlays
            let systemApps = ["Dock", "SystemUIServer", "WindowServer", "NotificationCenter", "ControlCenter", "Wallpaper", "Siri", "Spotlight", "TextInputMenuAgent", "TextInputSwitcher"]
            if systemApps.contains(ownerName) {
                continue
            }
            
            // FILTER: Only show regular user applications (exclude background helpers/agents)
            if let runningApp = NSRunningApplication(processIdentifier: pid) {
                if runningApp.activationPolicy != .regular {
                    continue
                }
            } else {
                continue
            }
            
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            
            // Get bounds
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }
            
            // FILTER: Must have a non-empty, non-whitespace title (excludes empty helper/background layers)
            var title = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                // Keep empty titles only if we are querying other spaces (showAllSpaces is true) or if the window is minimized.
                let minimized = !isOnscreen && isWindowMinimized(pid: pid, windowID: windowID)
                if showAllSpaces || (minimized && showMinimized) {
                    // For windows on other spaces (showAllSpaces is true), filter out small helper windows by requiring a large size.
                    if !minimized {
                        if bounds.width < 800 || bounds.height < 600 {
                            continue
                        }
                    }
                    title = ownerName
                } else {
                    continue
                }
            }
            
            // FILTER: Check if window ID is valid in the AX tree, with fallback for other spaces
            let isAXValid = validAXWindowIDs.contains(windowID)
            if !isAXValid {
                // If showAllSpaces is true, we keep any regular app window
                if !showAllSpaces {
                    continue
                }
            }
            
            // Filter out extremely small windows (icons, small widgets, status items)
            if bounds.width < 150 || bounds.height < 150 {
                continue
            }
            
            // Space / minimized filter checks
            if !isOnscreen {
                let minimized = isWindowMinimized(pid: pid, windowID: windowID)
                
                if minimized {
                    if !showMinimized {
                        continue
                    }
                } else {
                    // Not onscreen and not minimized means it's on another space
                    if !showAllSpaces {
                        continue
                    }
                }
            }
            
            // Get app icon
            var appIcon: NSImage? = nil
            if let runningApp = NSRunningApplication(processIdentifier: pid) {
                appIcon = runningApp.icon
            }
            if appIcon == nil {
                appIcon = NSWorkspace.shared.icon(for: .application)
            }
            
            let window = WindowInfo(
                id: windowID,
                pid: pid,
                ownerName: ownerName,
                title: title.isEmpty ? ownerName : title,
                bounds: bounds,
                appIcon: appIcon
            )
            windows.append(window)
        }
        
        // FILTER CO-LOCATED DUPLICATES: Remove windows that share the same PID, title, and exact screen bounds
        var seenKeys = Set<String>()
        var uniqueWindows: [WindowInfo] = []
        for window in windows {
            let key = "\(window.pid)-\(window.title)-\(Int(window.bounds.origin.x))-\(Int(window.bounds.origin.y))-\(Int(window.bounds.size.width))-\(Int(window.bounds.size.height))"
            if seenKeys.contains(key) {
                continue
            }
            seenKeys.insert(key)
            uniqueWindows.append(window)
        }
        windows = uniqueWindows
        
        // SORT BY Z-ORDER RANK: Keep active space windows in MRU order, push other spaces/minimized to the end
        windows.sort { (w1, w2) -> Bool in
            let rank1 = onscreenZOrder[w1.id] ?? 999999
            let rank2 = onscreenZOrder[w2.id] ?? 999999
            if rank1 != rank2 {
                return rank1 < rank2
            }
            return false
        }
        
        return windows
    }
    
    static func isWindowMinimized(pid: pid_t, windowID: CGWindowID) -> Bool {
        let appRef = AXUIElementCreateApplication(pid)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let axWindows = windowsValue as? [AXUIElement] else {
            return false
        }
        for axWindow in axWindows {
            if let id = getWindowID(from: axWindow), id == windowID {
                var minimizedValue: AnyObject?
                if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                   let minBool = minimizedValue as? Bool {
                    return minBool
                }
            }
        }
        return false
    }
    
    static func getThumbnail(for windowID: CGWindowID) -> CGImage? {
        return CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        )
    }
    
    static func raiseWindow(window: WindowInfo) {
        // 1. Activate the owning application
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            return
        }
        
        app.activate(options: [.activateIgnoringOtherApps])
        
        let appRef = AXUIElementCreateApplication(window.pid)
        
        @discardableResult
        func tryRaise() -> Bool {
            var windowsValue: AnyObject?
            guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                  let axWindows = windowsValue as? [AXUIElement] else {
                return false
            }
            
            // Match using private but reliable _AXUIElementGetWindow
            for axWindow in axWindows {
                if let id = getWindowID(from: axWindow), id == window.id {
                    // If minimized, unminimize first
                    var minimizedValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                       let isMin = minimizedValue as? Bool, isMin {
                        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    
                    // Set as main and focused window for cross-space switching
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            // Fallback: match by title
            for axWindow in axWindows {
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                let axTitle = titleValue as? String ?? ""
                
                if !axTitle.isEmpty && (axTitle == window.title || window.title.contains(axTitle)) {
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            return false
        }
        
        // Try immediately
        if !tryRaise() {
            // Background / Electron apps may not expose their windows immediately after activation.
            // Retry with increasing delays to ensure the window is successfully raised.
            let delays = [0.05, 0.15, 0.3, 0.5]
            for delay in delays {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if tryRaise() {
                        // Successfully raised, stop further retries if scheduled
                        return
                    }
                }
            }
        }
    }
    
    /// Close and Zoom still need button presses — these only work reliably on the frontmost app.
    /// For non-frontmost apps, we try AX frontmost promotion first.
    @discardableResult
    static func performWindowAction(window: WindowInfo, actionAttribute: CFString) -> Bool {
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let axWindows = windowsValue as? [AXUIElement] else { return false }
        
        for axWindow in axWindows {
            if let id = getWindowID(from: axWindow), id == window.id {
                AXUIElementSetAttributeValue(appRef, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                
                var buttonElement: AnyObject?
                let error = AXUIElementCopyAttributeValue(axWindow, actionAttribute, &buttonElement)
                if error == .success, let button = buttonElement {
                    let result = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
                    return result == .success
                }
            }
        }
        return false
    }

    /// Minimize by directly setting kAXMinimizedAttribute — works on any app, no button press needed.
    static func minimizeWindow(window: WindowInfo) {
        logAction("[minimizeWindow] Called for '\(window.ownerName):\(window.title)' pid=\(window.pid) id=\(window.id)")
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
        guard copyResult == .success, let axWindows = windowsValue as? [AXUIElement] else {
            logAction("[minimizeWindow] FAILED to get AX windows list. AXError=\(copyResult.rawValue)")
            return
        }
        logAction("[minimizeWindow] Got \(axWindows.count) AX windows")
        
        for axWindow in axWindows {
            if let id = getWindowID(from: axWindow), id == window.id {
                let result = AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
                logAction("[minimizeWindow] SetAttributeValue result=\(result.rawValue) (0=success)")
                return
            }
        }
        logAction("[minimizeWindow] No matching AX window found for id=\(window.id)")
    }

    static func forceQuit(window: WindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.forceTerminate()
        }
    }
    
    /// Exit full screen by directly setting AXFullScreen attribute — works on any app, no button press needed.
    static func exitFullScreen(window: WindowInfo) {
        logAction("[exitFullScreen] Called for '\(window.ownerName):\(window.title)' pid=\(window.pid) id=\(window.id)")
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue)
        guard copyResult == .success, let axWindows = windowsValue as? [AXUIElement] else {
            logAction("[exitFullScreen] FAILED to get AX windows list. AXError=\(copyResult.rawValue)")
            return
        }
        logAction("[exitFullScreen] Got \(axWindows.count) AX windows")
        
        for axWindow in axWindows {
            if let id = getWindowID(from: axWindow), id == window.id {
                // Check current fullscreen status first
                var fsValue: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, "AXFullScreen" as CFString, &fsValue)
                let isFS = fsValue as? Bool ?? false
                logAction("[exitFullScreen] Window isFullScreen=\(isFS)")
                
                let result = AXUIElementSetAttributeValue(axWindow, "AXFullScreen" as CFString, kCFBooleanFalse)
                logAction("[exitFullScreen] SetAttributeValue result=\(result.rawValue) (0=success)")
                return
            }
        }
        logAction("[exitFullScreen] No matching AX window found for id=\(window.id)")
    }
    
    static func getActiveWindowID() -> CGWindowID? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appRef = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var windowValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success else {
            return nil
        }
        return getWindowID(from: windowValue as! AXUIElement)
    }
    
    static func appMatches(window: WindowInfo, appName: String) -> Bool {
        if window.ownerName == appName {
            return true
        }
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            if app.localizedName == appName {
                return true
            }
        }
        if appName.localizedCaseInsensitiveContains(window.ownerName) ||
           window.ownerName.localizedCaseInsensitiveContains(appName) {
            return true
        }
        return false
    }
    
    private static func logAction(_ msg: String) {
        let logPath = "/Users/nikhiljain/.gemini/antigravity/brain/feb90e27-a96e-4b36-8783-aee805b013b9/scratch/action_debug.log"
        let formattedMsg = "\(Date()): \(msg)\n"
        if let data = formattedMsg.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fh = FileHandle(forWritingAtPath: logPath) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }
}

// Declaration of the private AX API to get CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private func getWindowID(from element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    let result = _AXUIElementGetWindow(element, &id)
    return result == .success ? id : nil
}
