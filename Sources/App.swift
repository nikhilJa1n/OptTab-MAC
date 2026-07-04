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
    }
    
    @objc func handleAccessibilityGranted() {
        print("[App] Accessibility permissions detected. Starting Hotkey Manager.")
        hotkeyManager?.start()
    }
    
    func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem?.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Advanced Switcher")
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
            // Gather active windows
            activeWindows = WindowList.getWindows()
            guard !activeWindows.isEmpty else { return }
            
            // Select appropriate index: standard alt-tab cycles to index 1 (the previous active app)
            if activeWindows.count > 1 {
                currentIndex = backward ? (activeWindows.count - 1) : 1
            } else {
                currentIndex = 0
            }
            
            switcherWindow?.show(windows: activeWindows, currentIndex: currentIndex)
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
            
            switcherWindow?.update(windows: activeWindows, currentIndex: currentIndex)
        }
    }
    
    func hotkeyArrowPressed(backward: Bool) {
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
        
        switcherWindow?.update(windows: activeWindows, currentIndex: currentIndex)
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
