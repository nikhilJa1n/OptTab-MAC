import Cocoa
import SwiftUI

class DockPreviewWindow: NSPanel {
    private var hostingView: NSHostingView<DockPreviewView>?
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .statusBar
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        self.ignoresMouseEvents = false
    }
    
    func show(appName: String, windows: [WindowInfo], dockItemFrame: CGRect, scale: Double) {
        guard !windows.isEmpty else {
            self.orderOut(nil)
            return
        }
        
        let rootView = DockPreviewView(
            appName: appName,
            windows: windows,
            scale: scale,
            onSelect: { [weak self] window in
                self?.orderOut(nil)
                WindowList.raiseWindow(window: window)
            },
            onClose: { [weak self] window in
                NotificationCenter.default.post(
                    name: Notification.Name("performWindowAction"),
                    object: nil,
                    userInfo: ["action": "close", "window": window]
                )
                
                // Refresh list after close animation/action settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    let freshWindows = WindowList.getWindows(showAllSpacesOverride: true, showMinimizedOverride: true).filter { WindowList.appMatches(window: $0, appName: appName) }
                    self.update(windows: freshWindows, appName: appName, dockItemFrame: dockItemFrame, scale: scale)
                }
            }
        )
        
        if let hosting = hostingView {
            hosting.rootView = rootView
        } else {
            let hosting = NSHostingView(rootView: rootView)
            self.contentView = hosting
            self.hostingView = hosting
        }
        
        // Recalculate frame to wrap around SwiftUI's intrinsic content size
        if let documentView = self.contentView {
            let fittingSize = documentView.fittingSize
            logMessage("[DockPreviewWindow] fittingSize width=\(fittingSize.width) height=\(fittingSize.height)")
            self.setContentSize(fittingSize)
        }
        
        // Position window relative to dock item frame and dock position
        positionWindow(dockItemFrame: dockItemFrame)
        logMessage("[DockPreviewWindow] Showing at origin=(\(self.frame.origin.x), \(self.frame.origin.y)) size=(\(self.frame.size.width), \(self.frame.size.height))")
        
        self.makeKeyAndOrderFront(nil)
    }
    
    func update(windows: [WindowInfo], appName: String, dockItemFrame: CGRect, scale: Double) {
        guard !windows.isEmpty else {
            self.orderOut(nil)
            return
        }
        
        let rootView = DockPreviewView(
            appName: appName,
            windows: windows,
            scale: scale,
            onSelect: { [weak self] window in
                self?.orderOut(nil)
                WindowList.raiseWindow(window: window)
            },
            onClose: { [weak self] window in
                NotificationCenter.default.post(
                    name: Notification.Name("performWindowAction"),
                    object: nil,
                    userInfo: ["action": "close", "window": window]
                )
                
                // Refresh list after close animation/action settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    let freshWindows = WindowList.getWindows(showAllSpacesOverride: true, showMinimizedOverride: true).filter { WindowList.appMatches(window: $0, appName: appName) }
                    self.update(windows: freshWindows, appName: appName, dockItemFrame: dockItemFrame, scale: scale)
                }
            }
        )
        
        hostingView?.rootView = rootView
        
        if let documentView = self.contentView {
            let fittingSize = documentView.fittingSize
            logMessage("[DockPreviewWindow] update fittingSize width=\(fittingSize.width) height=\(fittingSize.height)")
            self.setContentSize(fittingSize)
        }
        
        positionWindow(dockItemFrame: dockItemFrame)
        logMessage("[DockPreviewWindow] Updated at origin=(\(self.frame.origin.x), \(self.frame.origin.y)) size=(\(self.frame.size.width), \(self.frame.size.height))")
    }
    
    func hide() {
        logMessage("[DockPreviewWindow] Hiding")
        self.orderOut(nil)
    }
    
    private func positionWindow(dockItemFrame: CGRect) {
        // Find screen with cursor, or primary screen
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first
        
        guard let targetScreen = screen else { return }
        
        let screenFrame = targetScreen.frame
        let visibleFrame = targetScreen.visibleFrame
        let windowFrame = self.frame
        
        var x = dockItemFrame.origin.x + (dockItemFrame.size.width - windowFrame.width) / 2
        var y = dockItemFrame.origin.y + dockItemFrame.size.height + 8 // Default above dock
        
        // Detect Dock position
        if visibleFrame.origin.y > screenFrame.origin.y {
            // Dock is at the BOTTOM
            y = dockItemFrame.origin.y + dockItemFrame.size.height + 8
            x = max(visibleFrame.origin.x + 8, min(x, visibleFrame.origin.x + visibleFrame.size.width - windowFrame.width - 8))
        } else if visibleFrame.origin.x > screenFrame.origin.x {
            // Dock is on the LEFT
            x = dockItemFrame.origin.x + dockItemFrame.size.width + 8
            y = dockItemFrame.origin.y + (dockItemFrame.size.height - windowFrame.height) / 2
            y = max(visibleFrame.origin.y + 8, min(y, visibleFrame.origin.y + visibleFrame.size.height - windowFrame.height - 8))
        } else if visibleFrame.size.width < screenFrame.size.width {
            // Dock is on the RIGHT
            x = dockItemFrame.origin.x - windowFrame.width - 8
            y = dockItemFrame.origin.y + (dockItemFrame.size.height - windowFrame.height) / 2
            y = max(visibleFrame.origin.y + 8, min(y, visibleFrame.origin.y + visibleFrame.size.height - windowFrame.height - 8))
        } else {
            // Fallback (bottom)
            y = dockItemFrame.origin.y + dockItemFrame.size.height + 8
            x = max(visibleFrame.origin.x + 8, min(x, visibleFrame.origin.x + visibleFrame.size.width - windowFrame.width - 8))
        }
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    private func logMessage(_ msg: String) {
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
