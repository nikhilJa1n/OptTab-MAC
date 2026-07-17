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
    let isAXValid: Bool
    let isOnscreen: Bool
    
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

private func titlesMatch(axTitle: String, windowTitle: String) -> Bool {
    let cleanAX = axTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanWin = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleanAX.isEmpty || cleanWin.isEmpty { return false }
    if cleanAX == cleanWin || cleanAX.contains(cleanWin) || cleanWin.contains(cleanAX) {
        return true
    }
    
    // Handle truncation with ellipsis "…"
    if cleanWin.contains("…") {
        let components = cleanWin.components(separatedBy: "…")
                                 .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                 .filter { !$0.isEmpty }
        if !components.isEmpty {
            return components.allSatisfy { cleanAX.contains($0) }
        }
    }
    return false
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

private struct CachedThumbnail {
    let image: CGImage
    let timestamp: Date
}

class WindowList {
    private static var thumbnailCache: [CGWindowID: CachedThumbnail] = [:]
    private static let cacheLock = NSLock()
    private static var raiseGeneration: Int = 0
    
    private static func logMessage(_ msg: String) {
        let logPath = "/Users/nikhiljain/.gemini/antigravity/brain/feb90e27-a96e-4b36-8783-aee805b013b9/scratch/action_debug.log"
        let formattedMsg = "\(Date()): [WindowList] \(msg)\n"
        if let data = formattedMsg.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logPath) {
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }
    
    static func clearThumbnailCache() {
        cacheLock.lock()
        thumbnailCache.removeAll()
        cacheLock.unlock()
    }
    static func getWindows(showAllSpacesOverride: Bool? = nil, showMinimizedOverride: Bool? = nil) -> [WindowInfo] {
        let systemApps = ["Dock", "SystemUIServer", "WindowServer", "NotificationCenter", "ControlCenter", "Wallpaper", "Siri", "Spotlight", "TextInputMenuAgent", "TextInputSwitcher"]
        
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
        
        // Build set of valid window IDs and cache titles using accessibility tree of regular applications
        var validAXWindowIDs: Set<CGWindowID> = []
        var axWindowTitles: [CGWindowID: String] = [:]
        var axMinimizedStates: [CGWindowID: Bool] = [:]
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
                    
                    // Let all AXWindows pass role validation without requiring standard close/minimize controls (fixes custom/Chromium decorations)
                    
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
                        
                        // Retrieve minimized state
                        var minimizedValue: AnyObject?
                        if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                           let minBool = minimizedValue as? Bool {
                            axMinimizedStates[id] = minBool
                        } else {
                            axMinimizedStates[id] = false
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
                    let minimized = !isOnscreen && (axMinimizedStates[windowID] ?? false)
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
            
            // Space / minimized filter checks
            if !isOnscreen {
                let minimized = axMinimizedStates[windowID] ?? false
                
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
                appIcon: appIcon,
                isAXValid: isAXValid,
                isOnscreen: isOnscreen
            )
            windows.append(window)
        }
        
        // DEDUPLICATE TABS & HELPER WINDOWS: Keep only unique windows based on user preference
        let groupTabbedWindows = UserDefaults.standard.object(forKey: "groupTabbedWindows") as? Bool ?? true
        
        var uniqueWindows: [WindowInfo] = []
        var seenBoundsForPID = [pid_t: Set<String>]()
        
        if groupTabbedWindows {
            // Deduplicate all windows (both AX-valid and non-AX-valid) of the same app that have the exact same bounds.
            // Since the source window list is in front-to-back Z-order, the first one encountered is the active/visible tab.
            for window in windows {
                let boundsKey = "\(Int(window.bounds.origin.x))-\(Int(window.bounds.origin.y))-\(Int(window.bounds.size.width))-\(Int(window.bounds.size.height))"
                if !seenBoundsForPID[window.pid, default: []].contains(boundsKey) {
                    seenBoundsForPID[window.pid, default: []].insert(boundsKey)
                    uniqueWindows.append(window)
                }
            }
        } else {
            // Original logic: Keep all AX-valid windows. For non-AX-valid windows (tabs/helpers),
            // only keep them if they don't overlap with already kept windows of the same app on the same space.
            for window in windows {
                if window.isAXValid {
                    let boundsKey = "\(window.isOnscreen)-\(Int(window.bounds.origin.x))-\(Int(window.bounds.origin.y))-\(Int(window.bounds.size.width))-\(Int(window.bounds.size.height))"
                    seenBoundsForPID[window.pid, default: []].insert(boundsKey)
                    uniqueWindows.append(window)
                }
            }
            
            for window in windows {
                if !window.isAXValid {
                    let isRealWindow = window.title != window.ownerName
                    if isRealWindow {
                        uniqueWindows.append(window)
                    } else {
                        let boundsKey = "\(window.isOnscreen)-\(Int(window.bounds.origin.x))-\(Int(window.bounds.origin.y))-\(Int(window.bounds.size.width))-\(Int(window.bounds.size.height))"
                        if !seenBoundsForPID[window.pid, default: []].contains(boundsKey) {
                            seenBoundsForPID[window.pid, default: []].insert(boundsKey)
                            uniqueWindows.append(window)
                        }
                    }
                }
            }
        }
        windows = uniqueWindows
        
        // Add placeholders for running applications that have no open windows (like native Cmd+Tab)
        let activePIDs = Set(windows.map { $0.pid })
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            if !activePIDs.contains(pid) {
                let placeholderID = UInt32(bitPattern: -Int32(pid))
                let appName = app.localizedName ?? ""
                if appName.isEmpty || systemApps.contains(appName) || appName == "OptTab" {
                    continue
                }
                
                let placeholderWindow = WindowInfo(
                    id: placeholderID,
                    pid: pid,
                    ownerName: appName,
                    title: appName,
                    bounds: CGRect.zero,
                    appIcon: app.icon,
                    isAXValid: false,
                    isOnscreen: false
                )
                windows.append(placeholderWindow)
            }
        }
        
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
        if Int32(bitPattern: windowID) < 0 {
            return nil
        }
        
        cacheLock.lock()
        if let cached = thumbnailCache[windowID], Date().timeIntervalSince(cached.timestamp) < 3.0 {
            cacheLock.unlock()
            return cached.image
        }
        cacheLock.unlock()
        
        var capturedImage: CGImage?
        
        // Fast Path: Try capturing with onScreenWindowsOnly: true (very fast, covers active space)
        let semFast = DispatchSemaphore(value: 0)
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { content, error in
            guard let content = content, error == nil,
                  let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                semFast.signal()
                return
            }
            
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.width = 340
            config.height = 212
            
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, err in
                capturedImage = image
                semFast.signal()
            }
        }
        _ = semFast.wait(timeout: .now() + 0.15)
        
        // Slow Path: Fallback to capturing with onScreenWindowsOnly: false (covers minimized / other spaces)
        if capturedImage == nil {
            let semSlow = DispatchSemaphore(value: 0)
            SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
                guard let content = content, error == nil,
                      let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                    semSlow.signal()
                    return
                }
                
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let config = SCStreamConfiguration()
                config.showsCursor = false
                config.width = 340
                config.height = 212
                
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, err in
                    capturedImage = image
                    semSlow.signal()
                }
            }
            _ = semSlow.wait(timeout: .now() + 0.65)
        }
        
        if capturedImage == nil {
            capturedImage = CGWindowListCreateImage(
                .null,
                .optionIncludingWindow,
                windowID,
                [.boundsIgnoreFraming, .bestResolution]
            )
        }
        
        if let img = capturedImage {
            cacheLock.lock()
            thumbnailCache[windowID] = CachedThumbnail(image: img, timestamp: Date())
            cacheLock.unlock()
        }
        
        return capturedImage
    }
    
    static func raiseWindow(window: WindowInfo) {
        // Increment generation to cancel any stale delayed raises from previous calls
        raiseGeneration += 1
        let currentGen = raiseGeneration
        
        logMessage("raiseWindow called for target '\(window.ownerName):\(window.title)' (id=\(window.id), pid=\(window.pid)) gen=\(currentGen)")
        // 1. Activate the owning application
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            logMessage("  Error: Could not retrieve NSRunningApplication for pid \(window.pid)")
            return
        }
        
        app.activate(options: [.activateIgnoringOtherApps])
        logMessage("  activate() called for \(app.localizedName ?? "")")
        
        // For placeholder windows (apps running with no open windows), activation is sufficient
        if window.bounds == CGRect.zero {
            logMessage("  Placeholder window targeted, returning early after activation")
            return
        }
        
        let appRef = AXUIElementCreateApplication(window.pid)
        
        @discardableResult
        func tryRaise() -> Bool {
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
            
            var axWindows: [AXUIElement] = []
            for element in axElements {
                var roleValue: AnyObject?
                if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                   let role = roleValue as? String, role == kAXWindowRole {
                    axWindows.append(element)
                }
            }
            
            logMessage("  tryRaise: found \(axWindows.count) AXWindow elements")
            
            if axWindows.isEmpty {
                return false
            }
            
            // Match using private but reliable _AXUIElementGetWindow
            for axWindow in axWindows {
                let id = getWindowID(from: axWindow)
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                let axTitle = titleValue as? String ?? ""
                logMessage("    Checking AXWindow ID: \(id ?? 0) | Title: \(axTitle)")
                
                if let id = id, id == window.id {
                    logMessage("      Match found by WindowID! Raising window.")
                    // If minimized, unminimize first
                    var minimizedValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                       let isMin = minimizedValue as? Bool, isMin {
                        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    
                    // Set as main and focused window for cross-space switching
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            // Fallback 1: match by title
            for axWindow in axWindows {
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
                let axTitle = titleValue as? String ?? ""
                
                if !axTitle.isEmpty && titlesMatch(axTitle: axTitle, windowTitle: window.title) {
                    logMessage("      Match found by title Fallback! '\(axTitle)' vs '\(window.title)'. Raising.")
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            // Fallback 2: Tab matching (find tab elements inside window and switch tabs)
            for axWindow in axWindows {
                if selectTabIfNeeded(element: axWindow, targetTitle: window.title) {
                    logMessage("      Match found by tab fallback! Raising.")
                    var minimizedValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                       let isMin = minimizedValue as? Bool, isMin {
                        AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                    }
                    
                    AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, axWindow)
                    AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
                    return true
                }
            }
            
            // Fallback 3: Raise the first window of the application to prevent silent failure
            // Skip for Chromium apps — Chrome's AX tree doesn't expose all windows,
            // so raising the first AX window would bring up the WRONG window.
            // Instead, return false to let the AppleScript fallback handle it.
            let chromiumApps = ["Google Chrome", "Google Chrome Canary", "Chromium", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera"]
            let isChromiumApp = chromiumApps.contains(window.ownerName)
            
            if !isChromiumApp, let firstWindow = axWindows.first {
                var titleValue: AnyObject?
                AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleValue)
                let firstTitle = titleValue as? String ?? ""
                logMessage("      Fallback 3: Raising first window of app (Title: \(firstTitle))")
                var minimizedValue: AnyObject?
                if AXUIElementCopyAttributeValue(firstWindow, kAXMinimizedAttribute as CFString, &minimizedValue) == .success,
                   let isMin = minimizedValue as? Bool, isMin {
                    AXUIElementSetAttributeValue(firstWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                }
                
                AXUIElementSetAttributeValue(appRef, kAXMainWindowAttribute as CFString, firstWindow)
                AXUIElementSetAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, firstWindow)
                AXUIElementSetAttributeValue(firstWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
                AXUIElementSetAttributeValue(firstWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                AXUIElementPerformAction(firstWindow, kAXRaiseAction as CFString)
                return true
            }
            
            if isChromiumApp {
                logMessage("      tryRaise: Chromium app — skipping Fallback 3, deferring to AppleScript.")
            }
            
            logMessage("      tryRaise: No match found.")
            return false
        }
        
        // AppleScript fallback for applications when standard AX activation fails.
        // For Chromium apps, searches and brings the target window forward by title.
        // For standard apps (like Notes, Finder, etc.), sends a reopen and activate event to unminimize/raise its windows.
        func tryAppleScriptRaise() -> Bool {
            let chromiumApps = ["Google Chrome", "Google Chrome Canary", "Chromium", "Microsoft Edge", "Brave Browser", "Arc", "Vivaldi", "Opera"]
            
            let script: String
            let appScriptName = window.ownerName
            
            if chromiumApps.contains(appScriptName) {
                // Chromium specific title-based activation
                let targetTitle = window.title
                let resolvedScriptName: String
                switch appScriptName {
                case "Google Chrome Canary": resolvedScriptName = "Google Chrome Canary"
                case "Microsoft Edge": resolvedScriptName = "Microsoft Edge"
                case "Brave Browser": resolvedScriptName = "Brave Browser"
                default: resolvedScriptName = appScriptName
                }
                
                var titleFragments: [String] = []
                if targetTitle.contains("…") {
                    titleFragments = targetTitle.components(separatedBy: "…")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                } else {
                    titleFragments = [targetTitle]
                }
                
                var conditions: [String] = []
                for fragment in titleFragments {
                    let escaped = fragment.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    conditions.append("winTitle contains \"\(escaped)\"")
                }
                let conditionStr = conditions.joined(separator: " and ")
                
                script = """
                tell application "\(resolvedScriptName)"
                    set winCount to count of windows
                    repeat with i from 1 to winCount
                        set winTitle to title of window i
                        if \(conditionStr) then
                            set index of window i to 1
                            return "ok"
                        end if
                    end repeat
                    return "not_found"
                end tell
                """
                logMessage("      AppleScript fallback: Running Chromium title script for '\(resolvedScriptName)'")
            } else {
                // General App fallback (e.g. Notes, Finder, Mail)
                script = """
                tell application "\(appScriptName)"
                    reopen
                    activate
                    return "ok"
                end tell
                """
                logMessage("      AppleScript fallback: Running generic reopen/activate script for '\(appScriptName)'")
            }
            
            if let appleScript = NSAppleScript(source: script) {
                var errorInfo: NSDictionary?
                let result = appleScript.executeAndReturnError(&errorInfo)
                let resultStr = result.stringValue ?? "nil"
                logMessage("      AppleScript result: \(resultStr)")
                if resultStr == "ok" {
                    return true
                }
                if let err = errorInfo {
                    logMessage("      AppleScript error: \(err)")
                }
            }
            return false
        }
        
        // Try immediately
        let raised = tryRaise()
        
        // For Chromium apps where AX can't find the target window, use AppleScript on a background thread
        if !raised {
            // Run AppleScript on a background thread to avoid blocking the UI
            DispatchQueue.global(qos: .userInteractive).async {
                // Check if this raise request is still current
                guard currentGen == raiseGeneration else {
                    logMessage("      AppleScript cancelled — stale generation \(currentGen) vs \(raiseGeneration)")
                    return
                }
                _ = tryAppleScriptRaise()
            }
        }
        
        // Schedule delayed AX retries on main thread (lightweight, non-blocking)
        // These handle apps that need time to expose AX windows after activate()
        // Each callback checks raiseGeneration to cancel if a newer raise supersedes this one.
        let delays = [0.1, 0.25, 0.5]
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard currentGen == raiseGeneration else {
                    logMessage("  Delayed tryRaise cancelled — stale generation \(currentGen) vs \(raiseGeneration)")
                    return
                }
                _ = tryRaise()
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
