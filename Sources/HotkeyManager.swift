import Cocoa
import CoreGraphics

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyOptionTabPressed(backward: Bool)
    func hotkeyOptionReleased()
    func hotkeyEscPressed()
    func hotkeyFlagsChanged(isOptionPressed: Bool)
    func hotkeyArrowPressed(backward: Bool)
    func isSwitcherVisible() -> Bool
}

class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    init(delegate: HotkeyManagerDelegate) {
        self.delegate = delegate
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
        let isOptionPressed = flags.contains(.maskAlternate)
        
        if type == .flagsChanged {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyFlagsChanged(isOptionPressed: isOptionPressed)
            }
            // Option released while switcher is active -> commit selection
            if !isOptionPressed && (delegate?.isSwitcherVisible() ?? false) {
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.hotkeyOptionReleased()
                }
            }
        } else if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // Tab key code is 48
            if keyCode == 48 {
                if isOptionPressed {
                    let isShiftPressed = flags.contains(.maskShift)
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.hotkeyOptionTabPressed(backward: isShiftPressed)
                    }
                    return nil // Swallow Option+Tab
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
        }
        
        return Unmanaged.passUnretained(event)
    }
}
