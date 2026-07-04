import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate {
    var appState = AppState()
    var hotkeyManager: HotkeyManager?
    var switcherWindow: SwitcherWindow?
    var onboardingWindow: NSWindow?
    var statusBarItem: NSStatusItem?
    
    // Switcher state
    var activeWindows: [WindowInfo] = []
    var currentIndex: Int = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable stdout buffering for diagnostic logging
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        
        // Initialize state and check permissions
        appState.checkPermissions()
        
        // Setup Switcher Window
        switcherWindow = SwitcherWindow()
        
        // Initialize Hotkey Manager
        hotkeyManager = HotkeyManager(delegate: self)
        if appState.isAccessibilityGranted {
            hotkeyManager?.start()
        } else {
            showOnboarding()
        }
        
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
            selector: #selector(refreshActiveWindows),
            name: Notification.Name("windowActionTriggered"),
            object: nil
        )
    }
    
    @objc func handleAccessibilityGranted() {
        print("[App] Accessibility permissions detected. Starting Hotkey Manager.")
        hotkeyManager?.start()
    }
    
    
    func logMessage(_ msg: String) {
        let logPath = "/Users/nikhiljain/.gemini/antigravity/brain/feb90e27-a96e-4b36-8783-aee805b013b9/scratch/sorting_test.log"
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
    
    func getSortedWindowsAndIndex(backward: Bool) -> ([WindowInfo], Int) {
        let rawWindows = WindowList.getWindows()
        guard !rawWindows.isEmpty else { return ([], 0) }
        
        // Z-order index 1 is the previously active window
        let previouslyActiveWindowID = rawWindows.count > 1 ? rawWindows[1].id : rawWindows[0].id
        
        var sortedWindows = rawWindows
        let windowSortOrder = appState.windowSortOrder
        
        logMessage("Sorting request. Preference: '\(windowSortOrder)'")
        logMessage("  - Raw: " + rawWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        
        switch windowSortOrder {
        case "App Name":
            sortedWindows.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
        case "Window Title":
            sortedWindows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            break
        }
        
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
            return
        }
        
        var sortedWindows = rawWindows
        let windowSortOrder = appState.windowSortOrder
        logMessage("Refresh active windows request. Preference: '\(windowSortOrder)'")
        logMessage("  - Raw: " + rawWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        
        switch windowSortOrder {
        case "App Name":
            sortedWindows.sort { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
        case "Window Title":
            sortedWindows.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        default:
            break
        }
        
        logMessage("  - Sorted: " + sortedWindows.map { "\($0.ownerName):\($0.title)" }.joined(separator: ", "))
        
        activeWindows = sortedWindows
        
        if let prevID = previousSelectedID, let newIndex = activeWindows.firstIndex(where: { $0.id == prevID }) {
            currentIndex = newIndex
        } else {
            if currentIndex >= activeWindows.count {
                currentIndex = activeWindows.count - 1
            }
            if currentIndex < 0 {
                currentIndex = 0
            }
        }
        
        switcherWindow?.update(
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
    
    func handleHoverIndex(_ index: Int) {
        guard index >= 0 && index < activeWindows.count else { return }
        currentIndex = index
        switcherWindow?.update(
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
            let (sorted, targetIdx) = getSortedWindowsAndIndex(backward: backward)
            activeWindows = sorted
            guard !activeWindows.isEmpty else { return }
            
            currentIndex = targetIdx
            
            switcherWindow?.show(
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
        
        switcherWindow?.update(
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
        if switcherWindow?.isVisible ?? false {
            switcherWindow?.hide()
            
            if currentIndex >= 0 && currentIndex < activeWindows.count {
                let target = activeWindows[currentIndex]
                WindowList.raiseWindow(window: target)
            }
        }
        
        appState.isOptionKeyPressed = false
        appState.isTabKeyPressed = false
    }
    
    func hotkeyEscPressed() {
        if switcherWindow?.isVisible ?? false {
            switcherWindow?.hide()
        }
        appState.isOptionKeyPressed = false
        appState.isTabKeyPressed = false
    }
}
