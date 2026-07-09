import Cocoa
import CoreGraphics

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyOptionTabPressed(backward: Bool)
    func hotkeyOptionReleased()
    func hotkeyEscPressed()
    func hotkeyFlagsChanged(isOptionPressed: Bool)
    func hotkeyArrowPressed(backward: Bool)
    func hotkeyVerticalArrowPressed(up: Bool)
    func hotkeyWindowActionPressed(keyCode: Int)
    func isSwitcherVisible() -> Bool
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    let appState: AppState
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    init(delegate: HotkeyManagerDelegate, appState: AppState) {
        self.delegate = delegate
        self.appState = appState
    }
    
    func start() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        // Create event tap
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        
        guard let tap = tap else {
            print("[HotkeyManager] Failed to create Event Tap. Accessibility permissions are likely missing.")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[HotkeyManager] Started monitoring.")
    }
    
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        print("[HotkeyManager] Stopped monitoring.")
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        
        let isCmd = flags.contains(.maskCommand)
        let isOpt = flags.contains(.maskAlternate)
        let isCtrl = flags.contains(.maskControl)
        let isShift = flags.contains(.maskShift)
        
        let cmdRequired = (appState.hotkeyModifiers & 1) != 0
        let optRequired = (appState.hotkeyModifiers & 2) != 0
        let ctrlRequired = (appState.hotkeyModifiers & 4) != 0
        
        let allRequiredPressed = (!cmdRequired || isCmd) &&
                                 (!optRequired || isOpt) &&
                                 (!ctrlRequired || isCtrl)
        
        if type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.hotkeyFlagsChanged(isOptionPressed: optRequired ? isOpt : allRequiredPressed)
                
                // Option released while switcher is active -> commit selection
                if !allRequiredPressed && (self.delegate?.isSwitcherVisible() ?? false) {
                    self.delegate?.hotkeyOptionReleased()
                }
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // Custom Switcher Hotkey
            if keyCode == appState.hotkeyKeyCode {
                if (cmdRequired == isCmd) && (optRequired == isOpt) && (ctrlRequired == isCtrl) {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyOptionTabPressed(backward: isShift)
                    }
                    return nil // Swallow Custom Hotkey
                }
            }
            
            // Esc key code is 53
            if keyCode == 53 {
                if delegate?.isSwitcherVisible() ?? false {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyEscPressed()
                    }
                    return nil // Swallow Esc
                }
            }
            
            // Left Arrow is 123, Right Arrow is 124
            if (keyCode == 123 || keyCode == 124) && (delegate?.isSwitcherVisible() ?? false) {
                let backward = (keyCode == 123)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyArrowPressed(backward: backward)
                }
                return nil // Swallow Arrow key presses
            }
            
            // Up Arrow is 126, Down Arrow is 125
            if (keyCode == 125 || keyCode == 126) && (delegate?.isSwitcherVisible() ?? false) {
                let up = (keyCode == 126)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyVerticalArrowPressed(up: up)
                }
                return nil // Swallow Arrow key presses
            }
            
            // W is 13, M is 46, F is 3, Q is 12
            if (keyCode == 13 || keyCode == 46 || keyCode == 3 || keyCode == 12) && (delegate?.isSwitcherVisible() ?? false) {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyWindowActionPressed(keyCode: Int(keyCode))
                }
                return nil // Swallow shortcut key presses
            }
        }
        
        return Unmanaged.passUnretained(event)
    }
}
