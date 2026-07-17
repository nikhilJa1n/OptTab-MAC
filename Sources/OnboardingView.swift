import SwiftUI
import Combine
import ServiceManagement

struct RunningAppInfo: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: NSImage?
}

class AppState: ObservableObject {
    @Published var isAccessibilityGranted = false
    @Published var isScreenRecordingGranted = false
    
    @Published var startAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(startAtLogin, forKey: "startAtLogin")
            updateStartAtLogin()
        }
    }
    
    @Published var hideMenuIcon: Bool {
        didSet {
            UserDefaults.standard.set(hideMenuIcon, forKey: "hideMenuIcon")
            NotificationCenter.default.post(name: Notification.Name("updateStatusBarVisibility"), object: nil)
        }
    }
    
    @Published var isOptionKeyPressed = false
    @Published var isTabKeyPressed = false
    
    @Published var groupTabbedWindows: Bool {
        didSet { UserDefaults.standard.set(groupTabbedWindows, forKey: "groupTabbedWindows") }
    }
    
    @Published var enableArrowNavigation: Bool {
        didSet { UserDefaults.standard.set(enableArrowNavigation, forKey: "enableArrowNavigation") }
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
    
    @Published var cpuUsage: Double = 0.0
    @Published var ramUsage: (used: Double, total: Double) = (0.0, 16.0 * 1024 * 1024 * 1024)
    
    @Published var dockHoverDelay: Double {
        didSet { UserDefaults.standard.set(dockHoverDelay, forKey: "dockHoverDelay") }
    }
    
    @Published var useGridLayout: Bool {
        didSet { UserDefaults.standard.set(useGridLayout, forKey: "useGridLayout") }
    }
    
    private var timer: AnyCancellable?
    
    init() {
        self.enableArrowNavigation = UserDefaults.standard.object(forKey: "enableArrowNavigation") as? Bool ?? true
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
        
        let delayVal = UserDefaults.standard.double(forKey: "dockHoverDelay")
        self.dockHoverDelay = delayVal == 0 ? 0.15 : delayVal
        
        self.useGridLayout = UserDefaults.standard.object(forKey: "useGridLayout") as? Bool ?? false
        
        self.groupTabbedWindows = UserDefaults.standard.object(forKey: "groupTabbedWindows") as? Bool ?? true
        self.hideMenuIcon = UserDefaults.standard.object(forKey: "hideMenuIcon") as? Bool ?? false
        self.startAtLogin = (SMAppService.mainApp.status == .enabled)
        
        checkPermissions()
        startPermissionPolling()
    }
    
    func resetToDefaults() {
        self.enableArrowNavigation = true
        self.thumbnailScale = 1.0
        self.showMinimized = true
        self.showAllSpaces = false
        self.windowSortOrder = "Recently Used"
        self.enableDockHoverPreviews = true
        self.dockHoverThumbnailScale = 1.0
        self.hotkeyKeyCode = 48
        self.hotkeyModifiers = 2
        self.excludedApps = []
        self.dockHoverDelay = 0.15
        self.useGridLayout = false
        
        UserDefaults.standard.removeObject(forKey: "enableArrowNavigation")
        UserDefaults.standard.removeObject(forKey: "thumbnailScale")
        UserDefaults.standard.removeObject(forKey: "showMinimized")
        UserDefaults.standard.removeObject(forKey: "showAllSpaces")
        UserDefaults.standard.removeObject(forKey: "windowSortOrder")
        UserDefaults.standard.removeObject(forKey: "enableDockHoverPreviews")
        UserDefaults.standard.removeObject(forKey: "dockHoverThumbnailScale")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifiers")
        UserDefaults.standard.removeObject(forKey: "excludedApps")
        UserDefaults.standard.removeObject(forKey: "dockHoverDelay")
        UserDefaults.standard.removeObject(forKey: "useGridLayout")
        
        self.startAtLogin = false
        self.hideMenuIcon = false
        self.groupTabbedWindows = true
        UserDefaults.standard.removeObject(forKey: "hideMenuIcon")
        UserDefaults.standard.removeObject(forKey: "groupTabbedWindows")
    }
    
    func updateStartAtLogin() {
        let service = SMAppService.mainApp
        if startAtLogin {
            if service.status != .enabled {
                do {
                    try service.register()
                    print("[AppState] Registered start at login successfully.")
                } catch {
                    print("[AppState] Failed to register start at login: \(error.localizedDescription)")
                }
            }
        } else {
            if service.status == .enabled {
                do {
                    try service.unregister()
                    print("[AppState] Unregistered start at login successfully.")
                } catch {
                    print("[AppState] Failed to unregister start at login: \(error.localizedDescription)")
                }
            }
        }
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
    
    private var statsTimer: Timer?
    private var lastCPUTicks: (active: Double, total: Double)?
    
    func startStatsMonitoring() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
        updateStats()
    }
    
    func stopStatsMonitoring() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func updateStats() {
        // CPU
        var cpuInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let user = Double(cpuInfo.cpu_ticks.0)
            let system = Double(cpuInfo.cpu_ticks.1)
            let idle = Double(cpuInfo.cpu_ticks.2)
            let nice = Double(cpuInfo.cpu_ticks.3)
            let active = user + system + nice
            let total = active + idle
            
            if let last = lastCPUTicks {
                let diffActive = active - last.active
                let diffTotal = total - last.total
                if diffTotal > 0 {
                    self.cpuUsage = (diffActive / diffTotal) * 100.0
                }
            }
            lastCPUTicks = (active, total)
        }
        
        // RAM
        var stats = host_basic_info()
        var basicCount = mach_msg_type_number_t(MemoryLayout<host_basic_info>.size / MemoryLayout<integer_t>.size)
        let basicKerr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(basicCount)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &basicCount)
            }
        }
        
        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmKerr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        
        if basicKerr == KERN_SUCCESS && vmKerr == KERN_SUCCESS {
            let totalMemory = Double(stats.max_mem)
            let pageSize = Double(vm_kernel_page_size)
            let free = Double(vmStats.free_count) * pageSize
            let inactive = Double(vmStats.inactive_count) * pageSize
            let speculative = Double(vmStats.speculative_count) * pageSize
            
            let available = free + inactive + speculative
            let used = totalMemory - available
            self.ramUsage = (used, totalMemory)
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
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            Color.black.opacity(0.15)
                .ignoresSafeArea()
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        Image(systemName: "square.filled.on.square")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.85))
                        
                        Text("Advanced Dock")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 4)
                    
                    VStack(spacing: 4) {
                        SidebarButton(title: "General Preferences", icon: "slider.horizontal.3", isSelected: selectedTab == 0) {
                            selectedTab = 0
                        }
                        SidebarButton(title: "Dock Previews", icon: "dock.rectangle", isSelected: selectedTab == 1) {
                            selectedTab = 1
                        }
                        SidebarButton(title: "Hotkeys & Exclusions", icon: "keyboard.badge.ellipsis", isSelected: selectedTab == 2) {
                            selectedTab = 2
                        }
                        SidebarButton(title: "System Diagnostics", icon: "heart.text.square.fill", isSelected: selectedTab == 3) {
                            selectedTab = 3
                        }
                        SidebarButton(title: "How to Use", icon: "questionmark.circle", isSelected: selectedTab == 4) {
                            selectedTab = 4
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        UpdateChecker.shared.checkForUpdates(verbose: true)
                    }) {
                        Text("Check for Updates")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.55))
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(Color.white.opacity(0.03))
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.bottom, 2)
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isAccessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 5, height: 5)
                        
                        Text(state.isAccessibilityGranted ? "Active" : "Action Required")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(20)
                .frame(width: 200)
                
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 0.5)
                    .ignoresSafeArea()
                
                VStack {
                    if selectedTab == 0 {
                        GeneralTab(state: state)
                    } else if selectedTab == 1 {
                        DockPreviewsTab(state: state)
                    } else if selectedTab == 2 {
                        ExclusionsTab(state: state)
                    } else if selectedTab == 3 {
                        DiagnosticsTab(state: state)
                    } else {
                        HelpTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 780, height: 520)
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

struct SidebarButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.4))
                
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                isSelected ? 
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                : 
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.white.opacity(0.04) : Color.clear, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.0)
                .padding(.leading, 2)
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.015)))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
            )
        }
        .padding(.bottom, 6)
    }
}

struct GeneralTab: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("General Preferences")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                
                SettingsSection("Behavior & Navigation") {
                    ToggleRow(
                        title: "Enable Arrow Key Navigation",
                        description: "Cycle through cards using Left (←) / Right (→) arrow keys.",
                        isOn: $state.enableArrowNavigation
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.04))
                    
                    ToggleRow(
                        title: "Grid Layout Mode",
                        description: "Arrange switcher thumbnails in a 2D multi-row grid instead of a single paginated horizontal row.",
                        isOn: $state.useGridLayout
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.04))
                    
                    ToggleRow(
                        title: "Merge Tabbed Windows",
                        description: "Only show the active tab/window when multiple windows of the same application are tabbed or overlapping.",
                        isOn: $state.groupTabbedWindows
                    )
                }
                
                SettingsSection("System Integration") {
                    ToggleRow(
                        title: "Start at Login",
                        description: "Launch OptTab automatically when you log in to your Mac.",
                        isOn: $state.startAtLogin
                    )
                    
                    Divider()
                        .background(Color.white.opacity(0.04))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        ToggleRow(
                            title: "Hide Menu Bar Icon",
                            description: "Hide the status bar item icon.",
                            isOn: $state.hideMenuIcon
                        )
                        
                        if state.hideMenuIcon {
                            Text("⚠️ When hidden, reopen the Control Panel by launching the app again from your Applications folder.")
                                .font(.system(size: 9.5))
                                .foregroundColor(.yellow.opacity(0.85))
                                .padding(.top, 2)
                        }
                    }
                }
                
                SettingsSection("Switcher Scale") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Thumbnail Card Size")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                            Spacer()
                            Text(String(format: "%.0f%%", state.thumbnailScale * 100))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue.opacity(0.9))
                        }
                        Slider(value: $state.thumbnailScale, in: 0.7...1.4, step: 0.05)
                            .accentColor(.blue)
                    }
                }
                
                SettingsSection("Window Cycle Filtering") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Active Space Filters")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white.opacity(0.7))
                            
                            HStack(spacing: 20) {
                                Toggle("Minimized Apps", isOn: $state.showMinimized)
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                                
                                Toggle("All Desktop Spaces", isOn: $state.showAllSpaces)
                                    .toggleStyle(CheckboxToggleStyle())
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundColor(.white.opacity(0.75))
                            }
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.04))
                        
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Thumbnail Sort Order")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.85))
                                Text("Determines the order cards appear in the HUD switcher.")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                            Picker("", selection: $state.windowSortOrder) {
                                Text("Recently Used").tag("Recently Used")
                                Text("App Name").tag("App Name")
                                Text("Window Title").tag("Window Title")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                    }
                }

                
                HStack {
                    Spacer()
                    Button(action: {
                        state.resetToDefaults()
                    }) {
                        Text("Reset to Defaults")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 2)
            }
            .padding(20)
        }
    }
}

struct DockPreviewsTab: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dock Previews Settings")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                
                SettingsSection("Dock Preview Customization") {
                    VStack(alignment: .leading, spacing: 12) {
                        ToggleRow(
                            title: "Enable Dock Hover Previews",
                            description: "Show miniature window grids when hovering your mouse over Dock application icons.",
                            isOn: $state.enableDockHoverPreviews
                        )
                        
                        if state.enableDockHoverPreviews {
                            Divider()
                                .background(Color.white.opacity(0.04))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Dock Hover Card Size")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Spacer()
                                    Text(String(format: "%.0f%%", state.dockHoverThumbnailScale * 100))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.blue.opacity(0.9))
                                }
                                Slider(value: $state.dockHoverThumbnailScale, in: 0.7...2.0, step: 0.05)
                                    .accentColor(.blue)
                            }
                            
                            Divider()
                                .background(Color.white.opacity(0.04))
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Dock Hover Response Delay")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.85))
                                    Spacer()
                                    Text(String(format: "%.2fs", state.dockHoverDelay))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.blue.opacity(0.9))
                                }
                                Slider(value: $state.dockHoverDelay, in: 0.05...1.5, step: 0.05)
                                    .accentColor(.blue)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct ExclusionsTab: View {
    @ObservedObject var state: AppState
    @State private var searchText = ""
    
    var filteredApps: [RunningAppInfo] {
        let allApps = state.getRunningApps()
        if searchText.isEmpty {
            return allApps
        } else {
            return allApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Hotkeys & App Exclusions")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                
                SettingsSection("Trigger Shortcut") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("App Switcher Trigger Key")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("Click input to record your own custom hotkey combination.")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.45))
                        }
                        Spacer()
                        
                        Button(action: {
                            state.isRecordingShortcut = true
                        }) {
                            Text(state.isRecordingShortcut ? "Press Keys..." : hotkeyString(keyCode: state.hotkeyKeyCode, modifiers: state.hotkeyModifiers))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(state.isRecordingShortcut ? Color.red.opacity(0.1) : Color.white.opacity(0.04))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(state.isRecordingShortcut ? Color.red.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                SettingsSection("App Exclusion Rules") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Select applications to skip when cycling window cards.")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                        
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.3))
                            TextField("Search running applications...", text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.02))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
                        )
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                if filteredApps.isEmpty {
                                    Text("No running apps found")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))
                                        .padding(.vertical, 6)
                                } else {
                                    ForEach(filteredApps) { app in
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
                                                        .frame(width: 14, height: 14)
                                                }
                                                Text(app.name)
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(isExcluded ? .white.opacity(0.4) : .white)
                                                
                                                Image(systemName: isExcluded ? "square" : "checkmark.square.fill")
                                                    .foregroundColor(isExcluded ? .white.opacity(0.3) : .blue.opacity(0.8))
                                                    .font(.system(size: 10))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(isExcluded ? Color.clear : Color.white.opacity(0.04))
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(isExcluded ? Color.white.opacity(0.06) : Color.white.opacity(0.12), lineWidth: 0.5)
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

struct DiagnosticsTab: View {
    @ObservedObject var state: AppState
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Diagnostics & Monitoring")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 2)
                
                SettingsSection("System Telemetry") {
                    VStack(spacing: 12) {
                        SystemResourceMeter(
                            title: "CPU Utilization",
                            value: state.cpuUsage,
                            maxVal: 100.0,
                            label: String(format: "%.1f%%", state.cpuUsage),
                            color: .blue
                        )
                        
                        let usedGB = state.ramUsage.used / (1024 * 1024 * 1024)
                        let totalGB = state.ramUsage.total / (1024 * 1024 * 1024)
                        SystemResourceMeter(
                            title: "Physical RAM Allocation",
                            value: usedGB,
                            maxVal: totalGB,
                            label: String(format: "%.1f / %.0f GB", usedGB, totalGB),
                            color: .purple
                        )
                    }
                }
                
                SettingsSection("Permission Access") {
                    VStack(spacing: 8) {
                        PermissionCard(
                            title: "Accessibility API Access",
                            description: "Required to capture custom hotkeys and trigger desktop window actions.",
                            isGranted: state.isAccessibilityGranted,
                            action: { Permissions.requestAccessibility() }
                        )
                        
                        PermissionCard(
                            title: "Screen & Window Recording",
                            description: "Required to grab high-fidelity window preview thumbnails.",
                            isGranted: state.isScreenRecordingGranted,
                            action: { Permissions.requestScreenRecording() }
                        )
                    }
                }
                
                SettingsSection("Event Signal Tap Tester") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Hold options key modifiers to check signal path response.")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                        
                        HStack(spacing: 20) {
                            Spacer()
                            KeyCapView(
                                label: "Option ⌥",
                                isPressed: state.isOptionKeyPressed,
                                gradientColors: [Color.blue, Color.cyan]
                            )
                            
                            KeyCapView(
                                label: "Tab ⇥",
                                isPressed: state.isTabKeyPressed,
                                gradientColors: [Color.purple, Color.pink]
                            )
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            state.startStatsMonitoring()
        }
        .onDisappear {
            state.stopStatsMonitoring()
        }
    }
}

struct SystemResourceMeter: View {
    let title: String
    let value: Double
    let maxVal: Double
    let label: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Spacer()
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(value / maxVal, 1.0)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .background(Color.white.opacity(0.015))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.04), lineWidth: 0.5)
        )
    }
}

struct KeyCapView: View {
    let label: String
    let isPressed: Bool
    let gradientColors: [Color]
    
    var body: some View {
        VStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
                .frame(width: 110, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isPressed ? Color.white.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    Text(label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isPressed ? .white : .white.opacity(0.5))
                )
                .scaleEffect(isPressed ? 0.97 : 1.0)
                .animation(.easeOut(duration: 0.1), value: isPressed)
        }
    }
}

struct HelpTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How to Use")
                .font(.system(size: 15, weight: .bold, design: .rounded))
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
                .foregroundColor(.blue.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Color.blue.opacity(0.12))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }
        }
        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.1, green: 0.5, blue: 1.0)))
    }
}

struct PermissionCard: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isGranted ? .green.opacity(0.8) : .orange.opacity(0.8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(2)
            }
            
            Spacer()
            
            if isGranted {
                Text("Active")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(4)
            } else {
                Button(action: action) {
                    Text("Enable")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 0.5)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.02))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isGranted ? Color.green.opacity(0.08) : Color.orange.opacity(0.08), lineWidth: 0.5)
        )
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
