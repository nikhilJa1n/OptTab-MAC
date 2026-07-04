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
    static func getWindows() -> [WindowInfo] {
        let showMinimized = UserDefaults.standard.object(forKey: "showMinimized") as? Bool ?? true
        let showAllSpaces = UserDefaults.standard.object(forKey: "showAllSpaces") as? Bool ?? false
        let windowSortOrder = UserDefaults.standard.string(forKey: "windowSortOrder") ?? "Recently Used"
        
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
            
            // FILTER: Must have a non-empty, non-whitespace title (excludes empty helper/background layers)
            let title = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
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
            
            // FILTER: Check if window ID is valid in the AX tree, with fallback for other spaces
            let isAXValid = validAXWindowIDs.contains(windowID)
            if !isAXValid {
                // Fallback for windows on other spaces (since accessibility kAXWindowsAttribute only returns current space windows)
                if showAllSpaces && !isOnscreen {
                    if let runningApp = NSRunningApplication(processIdentifier: pid),
                       runningApp.activationPolicy == .regular {
                        // Keep this window (on another space)
                    } else {
                        continue
                    }
                } else {
                    continue
                }
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
            
            // Get bounds
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
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
        
        // SORTING: Sort windows dynamically based on preferences
        switch windowSortOrder {
        case "App Name":
            windows.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
        case "Window Title":
            windows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            break
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
        
        // 2. Raise the specific window using Accessibility API
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let axWindows = windowsValue as? [AXUIElement] else {
            return
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
                
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
        
        // Fallback: match by title and bounds
        for axWindow in axWindows {
            var titleValue: AnyObject?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
            let axTitle = titleValue as? String ?? ""
            
            if axTitle == window.title || window.title.contains(axTitle) {
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                return
            }
        }
    }
    
    @discardableResult
    static func performWindowAction(window: WindowInfo, actionAttribute: CFString) -> Bool {
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let axWindows = windowsValue as? [AXUIElement] else {
            return false
        }
        
        for axWindow in axWindows {
            if let id = getWindowID(from: axWindow), id == window.id {
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

    static func forceQuit(window: WindowInfo) {
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.forceTerminate()
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
