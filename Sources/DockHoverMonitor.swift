import Cocoa
import ApplicationServices

protocol DockHoverMonitorDelegate: AnyObject {
    func dockHoverMonitorDidHover(appName: String, itemFrame: CGRect)
    func dockHoverMonitorDidDismiss()
}

class DockHoverMonitor {
    weak var delegate: DockHoverMonitorDelegate?
    let appState: AppState
    var previewWindowFrameProvider: (() -> CGRect?)?
    private var timer: Timer?
    private var currentHoveredApp: String?
    private var pendingHoveredApp: String?
    private var activeDockPID: pid_t?
    private var hoverDelayWorkItem: DispatchWorkItem?
    
    init(delegate: DockHoverMonitorDelegate, appState: AppState) {
        self.delegate = delegate
        self.appState = appState
    }
    
    func start() {
        logMessage("[DockHoverMonitor] starting")
        guard timer == nil else { return }
        
        findDockPID()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            self?.checkMousePosition()
        }
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        currentHoveredApp = nil
        pendingHoveredApp = nil
        hoverDelayWorkItem?.cancel()
        hoverDelayWorkItem = nil
    }
    
    private func findDockPID() {
        if let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
            activeDockPID = dockApp.processIdentifier
            logMessage("[DockHoverMonitor] Found Dock app, PID=\(activeDockPID!)")
        } else {
            logMessage("[DockHoverMonitor] Dock app not found!")
        }
    }
    
    private func checkMousePosition() {
        // Ensure we have a valid Dock PID (fallback if Dock restarted)
        if activeDockPID == nil {
            findDockPID()
        }
        guard let dockPID = activeDockPID else { return }
        
        // Get mouse cursor location in Cocoa coordinates (bottom-left origin)
        let mouseLoc = NSEvent.mouseLocation
        
        // Primary screen height to convert Y coordinates (top-left origin for screen coordinates)
        guard let primaryScreen = NSScreen.screens.first else { return }
        let screenHeight = primaryScreen.frame.height
        let cursorPoint = CGPoint(x: mouseLoc.x, y: screenHeight - mouseLoc.y)
        
        let dockRef = AXUIElementCreateApplication(dockPID)
        
        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(dockRef, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return
        }
        
        var hoveredItem: (title: String, frame: CGRect)? = nil
        
        for child in children {
            var role: AnyObject?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &role)
            
            if (role as? String) == "AXList" {
                var listChildrenValue: AnyObject?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &listChildrenValue) == .success,
                   let listChildren = listChildrenValue as? [AXUIElement] {
                    
                    for item in listChildren {
                        var titleValue: AnyObject?
                        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                        let title = (titleValue as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        // Ignore separator divider (empty title) and trash/downloads for previews
                        if title.isEmpty || title == "Trash" || title == "Downloads" {
                            continue
                        }
                        
                        var posVal: AnyObject?
                        var sizeVal: AnyObject?
                        AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posVal)
                        AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeVal)
                        
                        if let axPos = posVal as! AXValue?, let axSize = sizeVal as! AXValue? {
                            var position = CGPoint.zero
                            var size = CGSize.zero
                            
                            if AXValueGetValue(axPos, .cgPoint, &position) &&
                               AXValueGetValue(axSize, .cgSize, &size) {
                                
                                let frame = CGRect(origin: position, size: size)
                                
                                // Check if cursor is within this dock item's bounds
                                if frame.contains(cursorPoint) {
                                    hoveredItem = (title: title, frame: frame)
                                    break
                                }
                            }
                        }
                    }
                }
            }
            if hoveredItem != nil { break }
        }
        
        if let item = hoveredItem {
            if currentHoveredApp != item.title {
                if pendingHoveredApp != item.title {
                    hoverDelayWorkItem?.cancel()
                    pendingHoveredApp = item.title
                    
                    let appName = item.title
                    let cocoaFrame = CGRect(
                        x: item.frame.origin.x,
                        y: screenHeight - item.frame.origin.y - item.frame.size.height,
                        width: item.frame.size.width,
                        height: item.frame.size.height
                    )
                    
                    let delay = appState.dockHoverDelay
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        self.logMessage("[DockHoverMonitor] Hover delay fired for '\(appName)'")
                        self.currentHoveredApp = appName
                        self.pendingHoveredApp = nil
                        self.delegate?.dockHoverMonitorDidHover(appName: appName, itemFrame: cocoaFrame)
                    }
                    self.hoverDelayWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                }
            } else {
                // If it is already the current hovered app, cancel any pending switch timer
                hoverDelayWorkItem?.cancel()
                hoverDelayWorkItem = nil
                pendingHoveredApp = nil
            }
        } else {
            // Check if mouse is currently inside the preview window
            if let frame = previewWindowFrameProvider?(), frame.contains(mouseLoc) {
                return
            }
            
            hoverDelayWorkItem?.cancel()
            hoverDelayWorkItem = nil
            pendingHoveredApp = nil
            
            if currentHoveredApp != nil {
                logMessage("[DockHoverMonitor] Hover dismissed (currentHoveredApp was '\(currentHoveredApp!)')")
                currentHoveredApp = nil
                delegate?.dockHoverMonitorDidDismiss()
            }
        }
    }
    
    private func logMessage(_ msg: String) {
        AppLogger.log(msg)
    }
}
