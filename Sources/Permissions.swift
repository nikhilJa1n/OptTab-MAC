import Cocoa
import CoreGraphics

struct Permissions {
    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let granted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        // If not granted (or dialog suppressed), open System Settings directly
        if !granted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    static func isScreenRecordingGranted() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    static func requestScreenRecording() {
        let granted = CGRequestScreenCaptureAccess()
        
        // If not granted (or dialog suppressed), open System Settings directly
        if !granted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
