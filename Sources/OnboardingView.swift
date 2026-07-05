import SwiftUI
import Combine

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
    
    @Published var gridRows: Int {
        didSet { UserDefaults.standard.set(gridRows, forKey: "gridRows") }
    }
    
    @Published var gridCols: Int {
        didSet { UserDefaults.standard.set(gridCols, forKey: "gridCols") }
    }
    
    @Published var enableDockHoverPreviews: Bool {
        didSet { UserDefaults.standard.set(enableDockHoverPreviews, forKey: "enableDockHoverPreviews") }
    }
    
    @Published var activeTheme: String {
        didSet { UserDefaults.standard.set(activeTheme, forKey: "activeTheme") }
    }
    
    @Published var selectedAppFilter: String? = nil
    @Published var searchQuery: String = ""
    @Published var isSearchActive: Bool = false
    
    private var timer: AnyCancellable?
    
    init() {
        self.enableArrowNavigation = UserDefaults.standard.object(forKey: "enableArrowNavigation") as? Bool ?? true
        self.enableHoverSwitch = UserDefaults.standard.object(forKey: "enableHoverSwitch") as? Bool ?? false
        let scaleVal = UserDefaults.standard.double(forKey: "thumbnailScale")
        self.thumbnailScale = scaleVal == 0 ? 1.0 : scaleVal
        self.showMinimized = UserDefaults.standard.object(forKey: "showMinimized") as? Bool ?? true
        self.showAllSpaces = UserDefaults.standard.object(forKey: "showAllSpaces") as? Bool ?? false
        self.windowSortOrder = UserDefaults.standard.string(forKey: "windowSortOrder") ?? "Recently Used"
        
        let rowsVal = UserDefaults.standard.integer(forKey: "gridRows")
        self.gridRows = rowsVal == 0 ? 1 : rowsVal
        let colsVal = UserDefaults.standard.integer(forKey: "gridCols")
        self.gridCols = colsVal == 0 ? 5 : colsVal
        self.enableDockHoverPreviews = UserDefaults.standard.object(forKey: "enableDockHoverPreviews") as? Bool ?? true
        self.activeTheme = UserDefaults.standard.string(forKey: "activeTheme") ?? "Glassmorphism"
        
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
                            .frame(width: 140)
                        }
                        
                        Divider()
                        
                        // Theme Style Picker
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Switcher Active Theme")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Select the design styling of the switcher cards.")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            Picker("", selection: $state.activeTheme) {
                                Text("Glassmorphism").tag("Glassmorphism")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Neon Blue").tag("Neon Blue")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Rainbow Sweep").tag("Rainbow Sweep")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Ultra Minimal").tag("Ultra Minimal")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(width: 140)
                        }
                        
                        Divider()
                        
                        // Grid Dimensions Picker
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Grid Layout (Rows x Columns)")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                Text("Configure how many rows and columns show per page.")
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                Picker("Rows", selection: $state.gridRows) {
                                    ForEach(1...3, id: \.self) { r in
                                        Text("\(r) Row\(r > 1 ? "s" : "")").tag(r)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 85)
                                
                                Text("x")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.4))
                                
                                Picker("Cols", selection: $state.gridCols) {
                                    ForEach(3...6, id: \.self) { c in
                                        Text("\(c) Col\(c > 1 ? "s" : "")").tag(c)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(width: 85)
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
