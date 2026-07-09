import SwiftUI
import Combine

struct RunningAppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: NSImage?
}

class AppState: ObservableObject {
    @Published var isAccessibilityGranted = false
    @Published var isScreenRecordingGranted = false
    
    @Published var isOptionKeyPressed = false
    @Published var isTabKeyPressed = false
    
    @Published var enableArrowNavigation: Bool {
        didSet { UserDefaults.standard.set(enableArrowNavigation, forKey: "enableArrowNavigation") }
    }
    
    @Published var enableHoverSwitch: Bool {
        didSet { UserDefaults.standard.set(enableHoverSwitch, forKey: "enableHoverSwitch") }
    }
    
    @Published var thumbnailScale: Double {
        didSet { UserDefaults.standard.set(thumbnailScale, forKey: "thumbnailScale") }
    }
    
    @Published var showMinimized: Bool {
        didSet { UserDefaults.standard.set(showMinimized, forKey: "showMinimized") }
    }
    
    @Published var showAllSpaces: Bool {
        didSet { UserDefaults.standard.set(showAllSpaces, forKey: "showAllSpaces") }
    }
    
    @Published var windowSortOrder: String {
        didSet { UserDefaults.standard.set(windowSortOrder, forKey: "windowSortOrder") }
    }
    
    @Published var enableDockHoverPreviews: Bool {
        didSet { UserDefaults.standard.set(enableDockHoverPreviews, forKey: "enableDockHoverPreviews") }
    }
    
    @Published var dockHoverThumbnailScale: Double {
        didSet { UserDefaults.standard.set(dockHoverThumbnailScale, forKey: "dockHoverThumbnailScale") }
    }
    
    @Published var hotkeyKeyCode: Int {
        didSet { UserDefaults.standard.set(hotkeyKeyCode, forKey: "hotkeyKeyCode") }
    }
    
    @Published var hotkeyModifiers: Int {
        didSet { UserDefaults.standard.set(hotkeyModifiers, forKey: "hotkeyModifiers") }
    }
    
    @Published var excludedApps: Set<String> {
        didSet { UserDefaults.standard.set(Array(excludedApps), forKey: "excludedApps") }
    }
    
    @Published var isRecordingShortcut = false
    
    private var timer: AnyCancellable?
    
    init() {
        self.enableArrowNavigation = UserDefaults.standard.object(forKey: "enableArrowNavigation") as? Bool ?? true
        self.enableHoverSwitch = UserDefaults.standard.object(forKey: "enableHoverSwitch") as? Bool ?? false
        let scaleVal = UserDefaults.standard.double(forKey: "thumbnailScale")
        self.thumbnailScale = scaleVal == 0 ? 1.0 : scaleVal
        self.showMinimized = UserDefaults.standard.object(forKey: "showMinimized") as? Bool ?? true
        self.showAllSpaces = UserDefaults.standard.object(forKey: "showAllSpaces") as? Bool ?? false
        self.windowSortOrder = UserDefaults.standard.string(forKey: "windowSortOrder") ?? "Recently Used"
        
        self.enableDockHoverPreviews = UserDefaults.standard.object(forKey: "enableDockHoverPreviews") as? Bool ?? true
        
        let dockScaleVal = UserDefaults.standard.double(forKey: "dockHoverThumbnailScale")
        self.dockHoverThumbnailScale = dockScaleVal == 0 ? 1.0 : dockScaleVal
        
        self.hotkeyKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? 48
        self.hotkeyModifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? 2 // maskAlternate = 2
        if let excluded = UserDefaults.standard.stringArray(forKey: "excludedApps") {
            self.excludedApps = Set(excluded)
        } else {
            self.excludedApps = []
        }
        
        checkPermissions()
        startPermissionPolling()
    }
    
    func checkPermissions() {
        isAccessibilityGranted = Permissions.isAccessibilityGranted()
        isScreenRecordingGranted = Permissions.isScreenRecordingGranted()
    }
    
    func startPermissionPolling() {
        timer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let prevAccess = self.isAccessibilityGranted
                self.checkPermissions()
                
                if !prevAccess && self.isAccessibilityGranted {
                    NotificationCenter.default.post(name: .accessibilityGranted, object: nil)
                }
            }
    }
    
    func getRunningApps() -> [RunningAppInfo] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app -> RunningAppInfo? in
                guard let name = app.localizedName else { return nil }
                return RunningAppInfo(name: name, icon: app.icon)
            }
        
        var seen = Set<String>()
        var uniqueApps = [RunningAppInfo]()
        for a in apps {
            if !seen.contains(a.name) {
                seen.insert(a.name)
                uniqueApps.append(a)
            }
        }
        return uniqueApps.sorted(by: { $0.name.lowercased() < $1.name.lowercased() })
    }
}

extension Notification.Name {
    static let accessibilityGranted = Notification.Name("accessibilityGranted")
}

struct OnboardingView: View {
    @ObservedObject var state: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation
            VStack(alignment: .leading, spacing: 20) {
                // Header Logo
                HStack(spacing: 12) {
                    // Logo representation
                    LinearGradient(
                        colors: [Color.blue, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 40, height: 40)
                    .cornerRadius(10)
                    .overlay(
                        Image(systemName: "square.filled.on.square")
                            .foregroundColor(.white)
                            .font(.system(size: 18, weight: .bold))
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced Dock")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Switcher v1.0")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.bottom, 10)
                
                // Navigation Items
                VStack(spacing: 8) {
                    SidebarButton(title: "Setup & Permissions", icon: "shield.righthalf.filled", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    SidebarButton(title: "Shortcut Tester", icon: "keyboard", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    SidebarButton(title: "How to Use", icon: "questionmark.circle", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                }
                
                Spacer()
                
                // Check for Updates Button
                Button(action: {
                    UpdateChecker.shared.checkForUpdates(verbose: true)
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle")
                        Text("Check for Updates")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 8)
                
                // Status Light
                HStack(spacing: 8) {
                    Circle()
                        .fill(state.isAccessibilityGranted ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: state.isAccessibilityGranted ? Color.green.opacity(0.6) : Color.red.opacity(0.6), radius: 4)
                    
                    Text(state.isAccessibilityGranted ? "Active" : "Configuration Needed")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(24)
            .frame(width: 210)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
            
            Divider()
            
            // Detail / Content Area
            VStack {
                if selectedTab == 0 {
                    PermissionsTab(state: state)
                } else if selectedTab == 1 {
                    TesterTab(state: state)
                } else {
                    HelpTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 660, height: 460)
        .preferredColorScheme(.dark)
        .overlay(
            Group {
                if state.isRecordingShortcut {
                    KeyRecordingView(state: state)
                        .frame(width: 0, height: 0)
                }
            }
        )
    }
}

// Sidebar Button Helper
struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            .background(isSelected ? Color.blue.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Permissions View
struct PermissionsTab: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Permissions Configuration")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("To display window switcher cards and intercept the **Option + Tab** shortcut, the application requires the following system permissions:")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineSpacing(4)
                
                VStack(spacing: 14) {
                    // Accessibility Permission Card
                    PermissionCard(
                        title: "Accessibility Permission",
                        description: "Enables keyboard interception (Option+Tab) and window focusing controls.",
                        isGranted: state.isAccessibilityGranted,
                        action: { Permissions.requestAccessibility() }
                    )
                    
                    // Screen Recording Permission Card
                    PermissionCard(
                        title: "Screen & Window Recording",
                        description: "Enables taking visual screenshots of active windows to show as thumbnails.",
                        isGranted: state.isScreenRecordingGranted,
                        action: { Permissions.requestScreenRecording() }
                    )
                }
                
                if state.isAccessibilityGranted && state.isScreenRecordingGranted {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 18))
                        Text("All systems configured! The window switcher is active.")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .padding(.vertical, 10)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 14))
                                .padding(.top, 1)
                            
                            Text("Permission issues after app update?")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        Text("If you previously granted permissions but they now show as missing, macOS has cached the old signature. Go to **System Settings > Privacy & Security > Accessibility**, select **AdvancedDock**, click the **minus (–)** button to delete it, and relaunch the app to re-register it. If that fails, restart the app after toggling.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .lineSpacing(3)
                            .padding(.leading, 22)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.top, 4)
                }
                               // Preferences & Behavior Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Preferences & Behavior")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        // Arrow navigation toggle
                        ToggleRow(
                            title: "Enable Arrow Key Navigation",
                            description: "Cycle through cards using Left (←) / Right (→) arrow keys.",
                            isOn: $state.enableArrowNavigation
                        )
                        
                        Divider()
                        
                        // Hover Selection Toggle
                        ToggleRow(
                            title: "Enable Mouse Hover Switch",
                            description: "Highlight window cards automatically when hovering the mouse cursor.",
                            isOn: $state.enableHoverSwitch
                        )
                        
                        Divider()
                        
                        // Thumbnail Scaling Slider
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Thumbnail Card Size")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Spacer()
                                Text(String(format: "%.0f%%", state.thumbnailScale * 100))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(value: $state.thumbnailScale, in: 0.7...1.4, step: 0.05)
                                .accentColor(.blue)
                        }
                        
                        Divider()
                        
                        // Filter & Preview Options
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Workspace & Dock Options")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            HStack(spacing: 20) {
                                Toggle("Minimized Apps", isOn: $state.showMinimized)
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Toggle("All Desktop Spaces", isOn: $state.showAllSpaces)
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            
                            Toggle("Enable Dock Hover Previews", isOn: $state.enableDockHoverPreviews)
                                .toggleStyle(CheckboxToggleStyle())
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            if state.enableDockHoverPreviews {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Dock Hover Thumbnail Size")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .foregroundColor(.white.opacity(0.9))
                                        Spacer()
                                        Text(String(format: "%.0f%%", state.dockHoverThumbnailScale * 100))
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.leading, 20)
                                    
                                    Slider(value: $state.dockHoverThumbnailScale, in: 0.7...2.0, step: 0.05)
                                        .accentColor(.blue)
                                        .padding(.leading, 20)
                                }
                                .padding(.top, 4)
                            }
                        }
                        
                        Divider()
                        
                        // Window Sorting Picker
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thumbnail Sort Order")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Determines the order cards appear in the HUD switcher.")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            Picker("", selection: $state.windowSortOrder) {
                                Text("Recently Used").tag("Recently Used")
                                    .font(.system(size: 11, weight: .medium))
                                Text("App Name").tag("App Name")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Window Title").tag("Window Title")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        Divider()
                        
                        // Hotkey Shortcut Recorder
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Switcher Shortcut")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Click to record a custom shortcut to trigger the switcher HUD.")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            
                            Button(action: {
                                state.isRecordingShortcut = true
                            }) {
                                Text(state.isRecordingShortcut ? "Press Keys (Esc to Cancel)..." : hotkeyString(keyCode: state.hotkeyKeyCode, modifiers: state.hotkeyModifiers))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(state.isRecordingShortcut ? Color.red.opacity(0.3) : Color.blue.opacity(0.2))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(state.isRecordingShortcut ? Color.red : Color.blue, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        Divider()
                        
                        // App Exclusions list
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Excluded Applications")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Select apps that should never appear in the switcher HUD cycle.")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(state.getRunningApps()) { app in
                                        let isExcluded = state.excludedApps.contains(app.name)
                                        Button(action: {
                                            if isExcluded {
                                                state.excludedApps.remove(app.name)
                                            } else {
                                                state.excludedApps.insert(app.name)
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                if let icon = app.icon {
                                                    Image(nsImage: icon)
                                                        .resizable()
                                                        .frame(width: 16, height: 16)
                                                }
                                                Text(app.name)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(isExcluded ? .white.opacity(0.4) : .white)
                                                
                                                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                                                    .foregroundColor(isExcluded ? .white.opacity(0.3) : .blue)
                                                    .font(.system(size: 10))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(isExcluded ? Color.white.opacity(0.04) : Color.blue.opacity(0.12))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isExcluded ? Color.white.opacity(0.08) : Color.blue.opacity(0.3), lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.04))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.top, 8)
                
                Spacer()
            }
            .padding(24)
        }
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: isGranted ? "checkmark" : "exclamationmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isGranted ? .green : .orange)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isGranted {
                Text("Granted")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(6)
            } else {
                Button(action: action) {
                    Text("Grant")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), lineWidth: 1)
        )
    }
}

// Shortcut Tester View
struct TesterTab: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Interactive Shortcut Tester")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Hold the Option key and tap Tab on your keyboard. The visual keys below will glow in real-time if the event tap is active and capturing keys.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(4)
            
            Spacer()
            
            // Visual Keyboard Keys
            HStack(spacing: 24) {
                Spacer()
                
                // Option Key
                KeyCapView(
                    label: "Option ⌥",
                    isPressed: state.isOptionKeyPressed,
                    gradientColors: [Color.blue, Color.cyan]
                )
                
                // Tab Key
                KeyCapView(
                    label: "Tab ⇥",
                    isPressed: state.isTabKeyPressed,
                    gradientColors: [Color.purple, Color.pink]
                )
                
                Spacer()
            }
            .padding(.bottom, 20)
            
            Spacer()
        }
        .padding(24)
    }
}

struct KeyCapView: View {
    let label: String
    let isPressed: Bool
    let gradientColors: [Color]
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isPressed ? LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .frame(width: 120, height: 74)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isPressed ? gradientColors.first ?? .blue : Color.white.opacity(0.15), lineWidth: 1.5)
                )
                .overlay(
                    Text(label)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(isPressed ? .white : .white.opacity(0.6))
                )
                .shadow(color: isPressed ? (gradientColors.first ?? .blue).opacity(0.5) : Color.clear, radius: 10, x: 0, y: 5)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .animation(.easeOut(duration: 0.1), value: isPressed)
        }
    }
}

// Help View
struct HelpTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How to Use")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 14) {
                HelpRow(number: "1", text: "Ensure both permissions are granted and showing a green dot.")
                HelpRow(number: "2", text: "Press and hold the **Option (⌥)** key down.")
                HelpRow(number: "3", text: "Tap the **Tab (⇥)** key to bring up the window switcher HUD panel.")
                HelpRow(number: "4", text: "Cycle through thumbnails by tapping **Tab** (or **Shift + Tab** to go backward), or use the **Left (←) / Right (→)** Arrow keys.")
                HelpRow(number: "5", text: "Release **Option** to switch directly to the highlighted window, or tap **Esc** to cancel.")
            }
            
            Spacer()
        }
        .padding(24)
    }
}

struct HelpRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.blue)
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.15))
                .clipShape(Circle())
            
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.75))
                .padding(.top, 2)
                .lineSpacing(2)
        }
    }
}

struct ToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: .blue))
    }
}

struct KeyRecordingView: NSViewRepresentable {
    @ObservedObject var state: AppState
    
    class Coordinator: NSView {
        var state: AppState?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            guard let state = state, state.isRecordingShortcut else {
                super.keyDown(with: event)
                return
            }
            
            let keyCode = Int(event.keyCode)
            
            // If Esc is pressed, cancel recording
            if keyCode == 53 {
                state.isRecordingShortcut = false
                return
            }
            
            // Parse modifier flags
            let flags = event.modifierFlags
            let isCmd = flags.contains(.command)
            let isOpt = flags.contains(.option)
            let isCtrl = flags.contains(.control)
            let isShift = flags.contains(.shift)
            
            let modifierMask = (isCmd ? 1 : 0) | (isOpt ? 2 : 0) | (isCtrl ? 4 : 0) | (isShift ? 8 : 0)
            
            // Require at least one modifier key (except Shift alone)
            if modifierMask == 0 || modifierMask == 8 {
                return
            }
            
            DispatchQueue.main.async {
                state.hotkeyKeyCode = keyCode
                state.hotkeyModifiers = modifierMask
                state.isRecordingShortcut = false
            }
        }
        
        override func flagsChanged(with event: NSEvent) {
            if state?.isRecordingShortcut == true {
                self.window?.makeFirstResponder(self)
            }
            super.flagsChanged(with: event)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let coord = Coordinator()
        coord.state = state
        return coord
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = context.coordinator
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if state.isRecordingShortcut {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

func hotkeyString(keyCode: Int, modifiers: Int) -> String {
    var str = ""
    if (modifiers & 1) != 0 { str += "⌘ " }
    if (modifiers & 2) != 0 { str += "⌥ " }
    if (modifiers & 4) != 0 { str += "⌃ " }
    if (modifiers & 8) != 0 { str += "⇧ " }
    
    switch keyCode {
    case 48: str += "Tab"
    case 49: str += "Space"
    case 53: str += "Esc"
    case 36: str += "Return"
    case 50: str += "`"
    default:
        str += keyName(for: keyCode)
    }
    return str
}

func keyName(for keyCode: Int) -> String {
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 18: return "1"
    case 19: return "2"
    case 20: return "3"
    case 21: return "4"
    case 22: return "6"
    case 23: return "5"
    case 24: return "="
    case 25: return "9"
    case 26: return "7"
    case 27: return "-"
    case 28: return "8"
    case 29: return "0"
    case 30: return "]"
    case 31: return "O"
    case 32: return "U"
    case 33: return "["
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 39: return "'"
    case 40: return "K"
    case 41: return ";"
    case 42: return "\\"
    case 43: return ","
    case 44: return "/"
    case 45: return "N"
    case 46: return "M"
    case 47: return "."
    case 50: return "`"
    default: return "Key \(keyCode)"
    }
}
