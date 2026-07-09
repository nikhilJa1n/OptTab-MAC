import Cocoa
import CoreGraphics
import ScreenCaptureKit

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

private func cleanTabTitle(_ title: String) -> String {
    var clean = title
    if let range = clean.range(of: " — ") {
        clean = String(clean[..<range.lowerBound])
    }
    return clean.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
}

private func selectTabIfNeeded(element: AXUIElement, targetTitle: String) -> Bool {
    var roleVal: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleVal) == .success,
       let role = roleVal as? String {
        if role == "AXRadioButton" || role == "AXTabButton" || role == "AXButton" || role.contains("Tab") {
            var titleVal: AnyObject?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleVal) == .success,
               let title = titleVal as? String {
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let cleanTrimmed = cleanTabTitle(trimmed)
                    let cleanTarget = cleanTabTitle(targetTitle)
                    if cleanTrimmed == cleanTarget || cleanTarget.contains(cleanTrimmed) || cleanTrimmed.contains(cleanTarget) {
                        AXUIElementPerformAction(element, kAXPressAction as CFString)
                        return true
                    }
                }
            }
        }
    }
    
    var childrenVal: AnyObject?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenVal) == .success,
       let children = childrenVal as? [AXUIElement] {
           for child in children {
               if selectTabIfNeeded(element: child, targetTitle: targetTitle) {
                   return true
               }
           }
    }
    return false
}

class WindowList {
    static func getWindows(showAllSpacesOverride: Bool? = nil, showMinimizedOverride: Bool? = nil) -> [WindowInfo] {
        // Gather onscreen Z-order rank from active space to sort raw lists in MRU order
        var onscreenZOrder: [CGWindowID: Int] = [:]
        var seenBoundsForPID: [pid_t: Set<String>] = [:]
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
        
        // Build set of valid window IDs and cache titles using accessibility tree of regular applications
        var validAXWindowIDs: Set<CGWindowID> = []
        var axWindowTitles: [CGWindowID: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if app.activationPolicy == .regular {
                let appRef = AXUIElementCreateApplication(app.processIdentifier)
                
                var axElements: [AXUIElement] = []
                
                var windowsValue: AnyObject?
                if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                   let axWindows = windowsValue as? [AXUIElement] {
                    axElements.append(contentsOf: axWindows)
                }
                
                var childrenValue: AnyObject?
                if AXUIElementCopyAttributeValue(appRef, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                   let axChildren = childrenValue as? [AXUIElement] {
                    axElements.append(contentsOf: axChildren)
                }
                
                for axWindow in axElements {
                    // Check role: must be AXWindow
                    var roleValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleValue) == .success,
                       let role = roleValue as? String, role != kAXWindowRole {
                        continue
                    }
                    
                    // Check subrole: must be Standard, Dialog, SystemDialog, FloatingWindow, or empty
                    var subroleValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                       let subrole = subroleValue as? String {
                        let allowed = (subrole == kAXStandardWindowSubrole || 
                                       subrole == kAXDialogSubrole || 
                                       subrole == "AXSystemDialog" ||
                                       subrole == "AXFloatingWindow" ||
                                       subrole.isEmpty)
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
                        
                        // Retrieve title from AX
                        var titleValue: AnyObject?
                        if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue) == .success,
                           let titleStr = titleValue as? String {
                            let trimmed = titleStr.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                axWindowTitles[id] = trimmed
                            }
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
            
            // FILTER: Check if window ID is valid in the AX tree, with fallback for other spaces
            let isAXValid = validAXWindowIDs.contains(windowID)
            if !isAXValid {
                // If showAllSpaces is true, or if the window is currently onscreen, we keep it
                if !showAllSpaces && !isOnscreen {
                    continue
                }
            }
            
            // FILTER: Must have a non-empty, non-whitespace title (excludes empty helper/background layers)
            var title = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty, let axTitle = axWindowTitles[windowID] {
                title = axTitle
            }
            
            if title.isEmpty {
                if isAXValid {
                    title = ownerName
                } else {
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
            }
            
            // Filter out extremely small windows (icons, small widgets, status items)
            if bounds.width < 150 || bounds.height < 150 {
                continue
            }
            
            // Deduplicate tabs/overlapping windows of the same application
            let boundsKey = "\(Int(bounds.origin.x)),\(Int(bounds.origin.y)),\(Int(bounds.width)),\(Int(bounds.height))"
            if seenBoundsForPID[pid] == nil {
                seenBoundsForPID[pid] = []
            }
            if seenBoundsForPID[pid]!.contains(boundsKey) {
                continue
            }
            seenBoundsForPID[pid]!.insert(boundsKey)
            
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
        var capturedImage: CGImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content = content, error == nil else {
                semaphore.signal()
                return
            }
            
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                semaphore.signal()
                return
            }
            
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.width = 340
            config.height = 212
            
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, err in
                capturedImage = image
                semaphore.signal()
            }
        }
        
        _ = semaphore.wait(timeout: .now() + 0.3)
        
        if capturedImage == nil {
            capturedImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        }
        
        return capturedImage
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
            
            // Fallback 1: match by title
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
            
            // Fallback 2: Tab matching (find tab elements inside window and switch tabs)
            for axWindow in axWindows {
                if selectTabIfNeeded(element: axWindow, targetTitle: window.title) {
                    var minimizedValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                       let isMin = minimizedValue as? Bool, isMin {
                        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            // Fallback 3: Raise the first window of the application to prevent silent failure
            if let firstWindow = axWindows.first {
                var minimizedValue: AnyObject?
                if AXUIElementCopyAttributeValue(firstWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                   let isMin = minimizedValue as? Bool, isMin {
                    AXUIElementSetAttributeValue(firstWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                
                AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, firstWindow)
                AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, firstWindow)
                AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
                return true
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
        if AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowValue) == .success {
            if let id = getWindowID(from: windowValue as! AXUIElement) {
                return id
            }
        }
        
        // Fallback: search CGWindowList for the topmost window of the frontmost application
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for info in windowList {
                guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid == frontmostApp.processIdentifier else { continue }
                if let windowID = info[kCGWindowNumber as String] as? CGWindowID {
                    return windowID
                }
            }
        }
        return nil
    }
    
    static func resizeWindow(window: WindowInfo, action: String) {
        // Find screen the window is on
        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        guard let primaryScreenHeight = primaryScreen?.frame.height else { return }
        
        var targetScreen = NSScreen.main ?? NSScreen.screens.first
        let windowMidX = window.bounds.origin.x + window.bounds.size.width / 2
        let windowMidY = window.bounds.origin.y + window.bounds.size.height / 2
        
        for screen in NSScreen.screens {
            // Convert window Y to Cocoa Y coordinate to do bounds check
            let cocoaY = primaryScreenHeight - windowMidY
            let point = CGPoint(x: windowMidX, y: cocoaY)
            if screen.frame.contains(point) {
                targetScreen = screen
                break
            }
        }
        
        guard let screen = targetScreen else { return }
        let visibleFrame = screen.visibleFrame
        
        var targetFrame = visibleFrame
        
        switch action {
        case "leftHalf":
            targetFrame = CGRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y,
                width: visibleFrame.size.width / 2,
                height: visibleFrame.size.height
            )
        case "rightHalf":
            targetFrame = CGRect(
                x: visibleFrame.origin.x + visibleFrame.size.width / 2,
                y: visibleFrame.origin.y,
                width: visibleFrame.size.width / 2,
                height: visibleFrame.size.height
            )
        case "maximize":
            targetFrame = visibleFrame
        default:
            return
        }
        
        // Convert targetFrame Cocoa coordinates (bottom-left origin) to Accessibility coordinates (top-left origin)
        let axX = targetFrame.origin.x
        let axY = primaryScreenHeight - targetFrame.origin.y - targetFrame.size.height
        
        logAction("[resizeWindow] Snapping window id=\(window.id) action=\(action) targetFrame=\(targetFrame) axX=\(axX) axY=\(axY)")
        
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            for axWindow in axWindows {
                if let id = getWindowID(from: axWindow), id == window.id {
                    var position = CGPoint(x: axX, y: axY)
                    var size = targetFrame.size
                    
                    if let axPosition = AXValueCreate(.cgPoint, &position),
                       let axSize = AXValueCreate(.cgSize, &size) {
                        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, axPosition)
                        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, axSize)
                        logAction("[resizeWindow] Set bounds successfully")
                    }
                    break
                }
            }
        }
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
    
    static func setWindowPositionAndSize(window: WindowInfo, frame targetFrame: CGRect) {
        guard let primaryScreen = NSScreen.screens.first else { return }
        let primaryScreenHeight = primaryScreen.frame.height
        
        let axX = targetFrame.origin.x
        let axY = primaryScreenHeight - targetFrame.origin.y - targetFrame.size.height
        
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            for axWindow in axWindows {
                if let id = getWindowID(from: axWindow), id == window.id {
                    var position = CGPoint(x: axX, y: axY)
                    var size = targetFrame.size
                    
                    if let axPosition = AXValueCreate(.cgPoint, &position),
                       let axSize = AXValueCreate(.cgSize, &size) {
                        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, axPosition)
                        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, axSize)
                        logAction("[setWindowPositionAndSize] set size successfully for \(window.id)")
                    }
                    break
                }
            }
        }
    }
    
    static func applyPresetLayout(preset: String, forAppName appName: String) {
        logAction("[applyPresetLayout] AppName=\(appName) Preset=\(preset)")
        let allWindows = getWindows(showAllSpacesOverride: true, showMinimizedOverride: true)
        let appWindows = allWindows.filter { appMatches(window: $0, appName: appName) }
        guard !appWindows.isEmpty else { return }
        
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        
        switch preset {
        case "2x2 Grid":
            let count = min(appWindows.count, 4)
            let cols = count > 1 ? 2 : 1
            let rows = count > 2 ? 2 : 1
            let w = visibleFrame.width / CGFloat(cols)
            let h = visibleFrame.height / CGFloat(rows)
            
            for i in 0..<count {
                let col = i % cols
                let row = i / cols
                let x = visibleFrame.origin.x + CGFloat(col) * w
                let y = visibleFrame.origin.y + (rows == 2 ? (row == 0 ? h : 0) : 0)
                let frame = CGRect(x: x, y: y, width: w, height: h)
                setWindowPositionAndSize(window: appWindows[i], frame: frame)
            }
            
        case "3-Column Split":
            let count = min(appWindows.count, 3)
            let w = visibleFrame.width / CGFloat(count)
            let h = visibleFrame.height
            
            for i in 0..<count {
                let x = visibleFrame.origin.x + CGFloat(i) * w
                let frame = CGRect(x: x, y: visibleFrame.origin.y, width: w, height: h)
                setWindowPositionAndSize(window: appWindows[i], frame: frame)
            }
            
        case "70/30 Split":
            if appWindows.count >= 2 {
                let w1 = visibleFrame.width * 0.7
                let w2 = visibleFrame.width * 0.3
                let h = visibleFrame.height
                
                let frame1 = CGRect(x: visibleFrame.origin.x, y: visibleFrame.origin.y, width: w1, height: h)
                setWindowPositionAndSize(window: appWindows[0], frame: frame1)
                
                let frame2 = CGRect(x: visibleFrame.origin.x + w1, y: visibleFrame.origin.y, width: w2, height: h)
                setWindowPositionAndSize(window: appWindows[1], frame: frame2)
            } else if appWindows.count == 1 {
                setWindowPositionAndSize(window: appWindows[0], frame: visibleFrame)
            }
            
        default:
            break
        }
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
