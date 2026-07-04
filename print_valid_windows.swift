import Cocoa
import CoreGraphics
import ApplicationServices

// Declaration of private AX API
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

private func getWindowID(from element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    let result = _AXUIElementGetWindow(element, &id)
    return result == .success ? id : nil
}

// Emulate WindowList.getWindows()
func getWindows() -> [String] {
    let showMinimized = true
    let showAllSpaces = false
    
    let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
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
                       let role = roleValue as? String, role != "AXWindow" {
                        continue
                    }
                    
                    // Check subrole: must be Standard, Dialog, or empty
                    var subroleValue: AnyObject?
                    if AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleValue) == .success,
                       let subrole = subroleValue as? String {
                        let allowed = (subrole == "AXStandardWindow" || subrole == "AXDialog" || subrole.isEmpty)
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
    
    var results: [String] = []
    let currentPid = ProcessInfo.processInfo.processIdentifier
    
    for info in windowListInfo {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        guard let windowID = info[kCGWindowNumber as String] as? CGWindowID else { continue }
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { continue }
        if pid == currentPid { continue }
        
        let title = (info[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { continue }
        
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            if runningApp.activationPolicy != .regular { continue }
        } else {
            continue
        }
        
        let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
        
        if !isOnscreen && title.isEmpty { continue }
        
        let isAXValid = validAXWindowIDs.contains(windowID)
        if !isAXValid {
            if showAllSpaces && !isOnscreen {
                if let runningApp = NSRunningApplication(processIdentifier: pid),
                   runningApp.activationPolicy == .regular {
                    // Keep
                } else {
                    continue
                }
            } else {
                continue
            }
        }
        
        let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
        if ownerName.isEmpty { continue }
        
        var boundsStr = ""
        if let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
           let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) {
            boundsStr = "\(Int(bounds.width))x\(Int(bounds.height))"
        }
        
        results.append("ID: \(windowID) | PID: \(pid) | Owner: \(ownerName) | Title: \(title) | Bounds: \(boundsStr)")
    }
    
    return results
}

let activeWindows = getWindows()
print("Number of windows passing filter: \(activeWindows.count)")
for win in activeWindows {
    print("  - \(win)")
}
