import Cocoa
import CoreGraphics

struct Permissions {
    static func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }
    
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
    
    static func isScreenRecordingGranted() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }
    
    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }
}
