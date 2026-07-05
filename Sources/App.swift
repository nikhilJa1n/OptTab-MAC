import Cocoa
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    var appState = AppState()
    var hotkeyManager: HotkeyManager?
    var switcherWindow: SwitcherWindow?
    var onboardingWindow: NSWindow?
    var statusBarItem: NSStatusItem?
    
    // Dock Hover Previews
    var dockHoverMonitor: DockHoverMonitor?
    var dockPreviewWindow: DockPreviewWindow?
    private var cancellables = Set<AnyCancellable>()
    
    // Switcher state
    var activeWindows: [WindowInfo] = []
    var currentIndex: Int = 0
    var mruWindowIDs: [CGWindowID] = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable stdout buffering for diagnostic logging
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        
        // Initialize state and check permissions
        appState.checkPermissions()
        
        // Setup Switcher Window
        switcherWindow = SwitcherWindow()
        
        // Setup Dock Previews
        dockPreviewWindow = DockPreviewWindow()
        dockHoverMonitor = DockHoverMonitor(delegate: self)
        dockHoverMonitor?.previewWindowFrameProvider = { [weak self] in
            guard let self = self, let previewWin = self.dockPreviewWindow, previewWin.isVisible else {
                return nil
            }
            return previewWin.frame
        }
        
        // Initialize Hotkey Manager
        hotkeyManager = HotkeyManager(delegate: self)
        if appState.isAccessibilityGranted {
            hotkeyManager?.start()
        } else {
            showOnboarding()
        }
        
        // Observe toggle changes in settings dynamically
        appState.$enableDockHoverPreviews
            .sink { [weak self] enabled in
                guard let self = self else { return }
                if enabled && self.appState.isAccessibilityGranted {
                    self.dockHoverMonitor?.start()
                } else {
                    self.dockHoverMonitor?.stop()
                    self.dockPreviewWindow?.hide()
                }
            }
            .store(in: &cancellables)
        
        // Observe search query and app filter changes to update switcher list dynamically
        Publishers.CombineLatest(appState.$searchQuery, appState.$selectedAppFilter)
            .sink { [weak self] _, _ in
                guard let self = self, self.isSwitcherVisible() else { return }
                self.refreshActiveWindows()
            }
            .store(in: &cancellables)
        
        // Setup Status Bar Item
        setupStatusBar()
        
        // Observe accessibility grant notifications from AppState polling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAccessibilityGranted),
            name: .accessibilityGranted,
            object: nil
        )
        
        // Observe window actions triggered from the UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowAction(_:)),
            name: Notification.Name("performWindowAction"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(commitSelection),
            name: Notification.Name("commitSwitcherSelection"),
            object: nil
        )
        
        // Observe workspace application activation and space changes for MRU tracking
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWorkspaceAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleActiveSpaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        
        // Initialize MRU with current active window
        updateMRUWithActiveWindow()
    }
    
    @objc func handleWindowAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let action = userInfo["action"] as? String,
              let window = userInfo["window"] as? WindowInfo else {
            logMessage("[handleWindowAction] guard failed — userInfo missing or cast failed")
            return
        }
        
        logMessage("[handleWindowAction] action='\(action)' app='\(window.ownerName)' title='\(window.title)' pid=\(window.pid) id=\(window.id)")
        
        // Hide the switcher first so focus can transfer to the target app
        switcherWindow?.hide()
        
        if action == "forceQuit" {
            WindowList.forceQuit(window: window)
            return
        }
        
        // Activate the target app
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
            logMessage("[handleWindowAction] activate() called")
        } else {
            logMessage("[handleWindowAction] NSRunningApplication failed for pid=\(window.pid)")
        }
        
        // Retry with increasing delays: 300ms, 600ms, 1000ms
        let delays: [Double] = [0.3, 0.6, 1.0]
        for (i, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // Check if AX windows are available now
                let appRef = AXUIElementCreateApplication(window.pid)
                var windowsValue: AnyObject?
                guard AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsValue) == .success,
                      let axWindows = windowsValue as? [AXUIElement], !axWindows.isEmpty else {
                    self?.logMessage("[handleWindowAction] attempt \(i+1)/\(delays.count) — still 0 AX windows after \(delay)s")
                    return
                }
                
                self?.logMessage("[handleWindowAction] attempt \(i+1) — got \(axWindows.count) AX windows after \(delay)s, executing action")
                
                switch action {
                case "close":
                    WindowList.performWindowAction(window: window, actionAttribute: kAXCloseButtonAttribute as CFString)
                case "minimize":
                    WindowList.minimizeWindow(window: window)
                case "zoom":
                    WindowList.performWindowAction(window: window, actionAttribute: kAXZoomButtonAttribute as CFString)
                case "exitFullScreen":
                    WindowList.exitFullScreen(window: window)
                default:
                    break
                }
            }
        }
    }
    
    @objc func commitSelection() {
        if switcherWindow?.isVisible ?? false {
            if currentIndex >= 0 && currentIndex < activeWindows.count {
                let target = activeWindows[currentIndex]
                mruWindowIDs.removeAll(where: { $0 == target.id })
                mruWindowIDs.insert(target.id, at: 0)
                WindowList.raiseWindow(window: target)
            }
            switcherWindow?.hide()
            appState.searchQuery = ""
            appState.selectedAppFilter = nil
            appState.isSearchActive = false
        }
    }
    
    @objc func handleAccessibilityGranted() {
        print("[App] Accessibility permissions detected. Starting Hotkey Manager and Dock Monitor.")
        hotkeyManager?.start()
        if appState.enableDockHoverPreviews {
            dockHoverMonitor?.start()
        }
    }
    
    
    func logMessage(_ msg: String) {
        let logPath = "/Users/nikhiljain/.gemini/antigravity/brain/feb90e27-a96e-4b36-8783-aee805b013b9/scratch/action_debug.log"
        let fileManager = FileManager.default
        let formattedMsg = "\(Date()): \(msg)\n"
        if let data = formattedMsg.data(using: .utf8) {
            if fileManager.fileExists(atPath: logPath) {
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
    
    func sortWindows(_ rawWindows: [WindowInfo]) -> [WindowInfo] {
        var sortedWindows = rawWindows
        let windowSortOrder = appState.windowSortOrder
        
        switch windowSortOrder {
        case "App Name":
            sortedWindows.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
        case "Window Title":
            sortedWindows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            // "Recently Used"
            sortedWindows.sort { (w1, w2) -> Bool in
                let idx1 = mruWindowIDs.firstIndex(of: w1.id)
                let idx2 = mruWindowIDs.firstIndex(of: w2.id)
                if let i1 = idx1, let i2 = idx2 {
                    return i1 < i2
                } else if idx1 != nil {
                    return true
                } else if idx2 != nil {
                    return false
                }
                // Fallback to original Z-order rank (which is rawWindows index)
                let rank1 = rawWindows.firstIndex(where: { $0.id == w1.id }) ?? 999999
                let rank2 = rawWindows.firstIndex(where: { $0.id == w2.id }) ?? 999999
                return rank1 < rank2
            }
        }
        return sortedWindows
    }
    
    func getSortedWindowsAndIndex(backward: Bool) -> ([WindowInfo], Int) {
        let rawWindows = WindowList.getWindows()
        guard !rawWindows.isEmpty else { return ([], 0) }
        
        // Z-order index 1 is the previously active window
        let previouslyActiveWindowID = rawWindows.count > 1 ? rawWindows[1].id : rawWindows[0].id
        
        var sortedWindows = sortWindows(rawWindows)
        
        // Apply App Filter
        if let filter = appState.selectedAppFilter {
            sortedWindows = sortedWindows.filter { WindowList.appMatches(window: $0, appName: filter) }
        }
        
        // Apply Search Filter
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            sortedWindows = sortedWindows.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.ownerName.localizedCaseInsensitiveContains(query)
            }
        }
        
        let windowSortOrder = appState.windowSortOrder
        logMessage("Sorting request. Preference: '\(windowSortOrder)'")
        logMessage("  - Raw: " + rawWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        logMessage("  - Sorted: " + sortedWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        
        var targetIndex = 0
        if let idx = sortedWindows.firstIndex(where: { $0.id == previouslyActiveWindowID }) {
            targetIndex = idx
        }
        
        if backward && sortedWindows.count > 1 {
            targetIndex = sortedWindows.count - 1
        }
        
        return (sortedWindows, targetIndex)
    }

    @objc func refreshActiveWindows() {
        let previousSelectedID = (currentIndex >= 0 && currentIndex < activeWindows.count) ? activeWindows[currentIndex].id : nil
        
        let rawWindows = WindowList.getWindows()
        if rawWindows.isEmpty {
            activeWindows = []
            switcherWindow?.hide()
            appState.searchQuery = ""
            appState.selectedAppFilter = nil
            return
        }
        
        var sortedWindows = sortWindows(rawWindows)
        
        // Apply App Filter
        if let filter = appState.selectedAppFilter {
            sortedWindows = sortedWindows.filter { WindowList.appMatches(window: $0, appName: filter) }
        }
        
        // Apply Search Filter
        let query = appState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            sortedWindows = sortedWindows.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.ownerName.localizedCaseInsensitiveContains(query)
            }
        }
        
        let windowSortOrder = appState.windowSortOrder
        logMessage("Refresh active windows request. Preference: '\(windowSortOrder)'")
        logMessage("  - Raw: " + rawWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        logMessage("  - Sorted: " + sortedWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        
        activeWindows = sortedWindows
        
        if let prevID = previousSelectedID, let newIndex = activeWindows.firstIndex(where: { $0.id == prevID }) {
            currentIndex = newIndex
        } else {
            currentIndex = 0
        }
        
        updateSwitcherView()
    }
    
    func handleHoverIndex(_ index: Int) {
        guard index >= 0 && index < activeWindows.count else { return }
        currentIndex = index
        switcherWindow?.update(
            appState: appState,
            windows: activeWindows,
            currentIndex: currentIndex,
            scale: appState.thumbnailScale,
            enableHoverSwitch: appState.enableHoverSwitch,
            gridRows: appState.gridRows,
            gridCols: appState.gridCols,
            onHover: { [weak self] i in self?.handleHoverIndex(i) },
            onClick: { [weak self] i in self?.handleClickIndex(i) }
        )
    }
    
    func handleClickIndex(_ index: Int) {
        guard index >= 0 && index < activeWindows.count else { return }
        currentIndex = index
        let target = activeWindows[currentIndex]
        mruWindowIDs.removeAll(where: { $0 == target.id })
        mruWindowIDs.insert(target.id, at: 0)
        hotkeyOptionReleased()
    }
    
    func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "square.filled.on.square", accessibilityDescription: "Advanced Switcher")
            // Optional: Support dark/light mode for template images
            button.image?.isTemplate = true
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Control Panel...", action: #selector(showOnboarding), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Advanced Switcher", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusBarItem?.menu = menu
    }
    
    @objc func showOnboarding() {
        if let window = onboardingWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        
        let view = OnboardingView(state: appState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Advanced Switcher Control Panel"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        
        self.onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
    
    @objc func quitApp() {
        hotkeyManager?.stop()
        NSApp.terminate(nil)
    }
    
    // MARK: - HotkeyManagerDelegate
    
    func isSwitcherVisible() -> Bool {
        return switcherWindow?.isVisible ?? false
    }
    
    func hotkeyFlagsChanged(isOptionPressed: Bool) {
        appState.isOptionKeyPressed = isOptionPressed
        if !isOptionPressed {
            appState.isTabKeyPressed = false
        }
    }
    
    func hotkeyOptionTabPressed(backward: Bool) {
        // Visual feedback for Option+Tab in the tester
        appState.isOptionKeyPressed = true
        appState.isTabKeyPressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.appState.isTabKeyPressed = false
        }
        
        if !(switcherWindow?.isVisible ?? false) {
            updateMRUWithActiveWindow()
            let (sorted, targetIdx) = getSortedWindowsAndIndex(backward: backward)
            activeWindows = sorted
            guard !activeWindows.isEmpty else { return }
            
            currentIndex = targetIdx
            
            switcherWindow?.show(
                appState: appState,
                windows: activeWindows,
                currentIndex: currentIndex,
                scale: appState.thumbnailScale,
                enableHoverSwitch: appState.enableHoverSwitch,
                gridRows: appState.gridRows,
                gridCols: appState.gridCols,
                onHover: { [weak self] index in self?.handleHoverIndex(index) },
                onClick: { [weak self] index in self?.handleClickIndex(index) }
            )
        } else {
            // Already open, cycle highlighted window index
            guard !activeWindows.isEmpty else { return }
            
            if backward {
                currentIndex -= 1
                if currentIndex < 0 {
                    currentIndex = activeWindows.count - 1
                }
            } else {
                currentIndex += 1
                if currentIndex >= activeWindows.count {
                    currentIndex = 0
                }
            }
            
            switcherWindow?.update(
                appState: appState,
                windows: activeWindows,
                currentIndex: currentIndex,
                scale: appState.thumbnailScale,
                enableHoverSwitch: appState.enableHoverSwitch,
                gridRows: appState.gridRows,
                gridCols: appState.gridCols,
                onHover: { [weak self] index in self?.handleHoverIndex(index) },
                onClick: { [weak self] index in self?.handleClickIndex(index) }
            )
        }
    }
    
    func hotkeyArrowPressed(backward: Bool) {
        guard appState.enableArrowNavigation else { return }
        guard switcherWindow?.isVisible ?? false, !activeWindows.isEmpty else { return }
        
        if backward {
            currentIndex -= 1
            if currentIndex < 0 {
                currentIndex = activeWindows.count - 1
            }
        } else {
            currentIndex += 1
            if currentIndex >= activeWindows.count {
                currentIndex = 0
            }
        }
        
        updateSwitcherView()
    }
    
    func hotkeyVerticalArrowPressed(up: Bool) {
        guard appState.enableArrowNavigation else { return }
        guard switcherWindow?.isVisible ?? false, !activeWindows.isEmpty else { return }
        
        let cols = appState.gridCols
        if up {
            currentIndex -= cols
            if currentIndex < 0 {
                // Wrap to the last row, same column
                let col = (currentIndex + cols) % cols
                let lastRowStart = (activeWindows.count - 1) / cols * cols
                currentIndex = min(lastRowStart + col, activeWindows.count - 1)
            }
        } else {
            currentIndex += cols
            if currentIndex >= activeWindows.count {
                // Wrap to the first row, same column
                currentIndex = currentIndex % cols
                if currentIndex >= activeWindows.count {
                    currentIndex = 0
                }
            }
        }
        
        updateSwitcherView()
    }
    
    private func updateSwitcherView() {
        switcherWindow?.update(
            appState: appState,
            windows: activeWindows,
            currentIndex: currentIndex,
            scale: appState.thumbnailScale,
            enableHoverSwitch: appState.enableHoverSwitch,
            gridRows: appState.gridRows,
            gridCols: appState.gridCols,
            onHover: { [weak self] index in self?.handleHoverIndex(index) },
            onClick: { [weak self] index in self?.handleClickIndex(index) }
        )
    }
    
    func hotkeyWindowActionPressed(keyCode: Int) {
        guard switcherWindow?.isVisible ?? false, currentIndex >= 0, currentIndex < activeWindows.count else { return }
        
        let target = activeWindows[currentIndex]
        
        switch keyCode {
        case 13: // W - Close
            WindowList.performWindowAction(window: target, actionAttribute: kAXCloseButtonAttribute as CFString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshActiveWindows()
            }
        case 46: // M - Minimize
            WindowList.performWindowAction(window: target, actionAttribute: kAXMinimizeButtonAttribute as CFString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshActiveWindows()
            }
        case 3: // F - Maximize/Zoom
            WindowList.performWindowAction(window: target, actionAttribute: kAXZoomButtonAttribute as CFString)
        case 12: // Q - Force Quit App
            WindowList.forceQuit(window: target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshActiveWindows()
            }
        default:
            break
        }
    }
    
    func hotkeyOptionReleased() {
        // If search is active, pinned state is maintained: do not close switcher on option release
        guard !appState.isSearchActive else { return }
        
        if switcherWindow?.isVisible ?? false {
            switcherWindow?.hide()
            
            if currentIndex >= 0 && currentIndex < activeWindows.count {
                let target = activeWindows[currentIndex]
                mruWindowIDs.removeAll(where: { $0 == target.id })
                mruWindowIDs.insert(target.id, at: 0)
                WindowList.raiseWindow(window: target)
            }
            
            // Reset query and filters
            appState.searchQuery = ""
            appState.selectedAppFilter = nil
            appState.isSearchActive = false
        }
        
        appState.isOptionKeyPressed = false
        appState.isTabKeyPressed = false
    }
    
    func hotkeyEscPressed() {
        if switcherWindow?.isVisible ?? false {
            switcherWindow?.hide()
            
            // Reset query and filters
            appState.searchQuery = ""
            appState.selectedAppFilter = nil
            appState.isSearchActive = false
        }
        appState.isOptionKeyPressed = false
        appState.isTabKeyPressed = false
    }
    
    // MARK: - MRU / Workspace Tracking Helpers
    @objc func handleWorkspaceAppActivation(_ notification: Notification) {
        updateMRUWithActiveWindow()
    }
    
    @objc func handleActiveSpaceChanged(_ notification: Notification) {
        updateMRUWithActiveWindow()
    }
    
    func updateMRUWithActiveWindow() {
        if let activeID = WindowList.getActiveWindowID() {
            mruWindowIDs.removeAll(where: { $0 == activeID })
            mruWindowIDs.insert(activeID, at: 0)
        }
    }
}

// MARK: - DockHoverMonitorDelegate
extension AppDelegate: DockHoverMonitorDelegate {
    func dockHoverMonitorDidHover(appName: String, itemFrame: CGRect) {
        // Only show previews if the main switcher window is not visible to avoid clutter
        guard !(switcherWindow?.isVisible ?? false) else { return }
        
        let allWindows = WindowList.getWindows(showAllSpacesOverride: true, showMinimizedOverride: true)
        let matchingWindows = allWindows.filter { WindowList.appMatches(window: $0, appName: appName) }
        
        guard !matchingWindows.isEmpty else {
            dockPreviewWindow?.hide()
            return
        }
        
        dockPreviewWindow?.show(
            appName: appName,
            windows: matchingWindows,
            dockItemFrame: itemFrame,
            scale: appState.thumbnailScale
        )
    }
    
    func dockHoverMonitorDidDismiss() {
        dockPreviewWindow?.hide()
    }
}
