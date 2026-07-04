import Cocoa
import ApplicationServices

// Declaration of private AX API
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

for app in NSWorkspace.shared.runningApplications {
    if app.activationPolicy == .regular {
        let appRef = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: AnyObject?
        if AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
           let axWindows = windowsValue as? [AXUIElement] {
            print("App: \(app.localizedName ?? "") (PID: \(app.processIdentifier)) has \(axWindows.count) AX windows")
            
            for axWindow in axWindows {
                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(axWindow, &windowID)
                
                var titleVal: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleVal)
                let title = titleVal as? String ?? ""
                
                var roleVal: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXRoleAttribute as CFString, &roleVal)
                let role = roleVal as? String ?? ""
                
                var subroleVal: AnyObject?
                AXUIElementCopyAttributeValue(axWindow, kAXSubroleAttribute as CFString, &subroleVal)
                let subrole = subroleVal as? String ?? ""
                
                print("  - ID: \(windowID) | Role: \(role) | Subrole: \(subrole) | Title: \(title)")
            }
        }
    }
}
