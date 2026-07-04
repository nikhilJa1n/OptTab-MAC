import Cocoa
import SwiftUI

class SwitcherWindow: NSPanel {
    private var hostingView: NSHostingView<SwitcherView>?
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .statusBar // Place it above regular windows and system elements
        self.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle] // Enable showing over fullscreen apps and multiple spaces
        self.ignoresMouseEvents = false // Allow mouse interactions if the user wants to click a thumbnail
    }
    
    func show(windows: [WindowInfo], currentIndex: Int, scale: Double, enableHoverSwitch: Bool, gridRows: Int, gridCols: Int, onHover: @escaping (Int) -> Void, onClick: @escaping (Int) -> Void) {
        let rootView = SwitcherView(
            windows: windows,
            currentIndex: currentIndex,
            scale: scale,
            enableHoverSwitch: enableHoverSwitch,
            gridRows: gridRows,
            gridCols: gridCols,
            onHoverIndex: onHover,
            onClickIndex: onClick
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
            self.setContentSize(fittingSize)
        }
        
        self.centerOnScreen()
        self.makeKeyAndOrderFront(nil)
    }
    
    func update(windows: [WindowInfo], currentIndex: Int, scale: Double, enableHoverSwitch: Bool, gridRows: Int, gridCols: Int, onHover: @escaping (Int) -> Void, onClick: @escaping (Int) -> Void) {
        let rootView = SwitcherView(
            windows: windows,
            currentIndex: currentIndex,
            scale: scale,
            enableHoverSwitch: enableHoverSwitch,
            gridRows: gridRows,
            gridCols: gridCols,
            onHoverIndex: onHover,
            onClickIndex: onClick
        )
        hostingView?.rootView = rootView
        
        if let documentView = self.contentView {
            let fittingSize = documentView.fittingSize
            self.setContentSize(fittingSize)
        }
    }
    
    func hide() {
        self.orderOut(nil)
    }
    
    private func centerOnScreen() {
        // Find screen with cursor, or primary screen
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main ?? NSScreen.screens.first
        
        guard let targetScreen = screen else { return }
        
        let screenFrame = targetScreen.frame
        let windowFrame = self.frame
        
        let x = screenFrame.origin.x + (screenFrame.width - windowFrame.width) / 2
        // Position it slightly above the center (e.g. 55% height) for better ergonomics
        let y = screenFrame.origin.y + (screenFrame.height - windowFrame.height) * 0.55
        
        self.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
