import SwiftUI
import CoreGraphics

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct SwitcherView: View {
    @ObservedObject var appState: AppState
    let windows: [WindowInfo]
    let currentIndex: Int
    let scale: Double
    let enableHoverSwitch: Bool
    let gridRows: Int
    let gridCols: Int
    let refreshToken: UUID
    let onHoverIndex: (Int) -> Void
    let onClickIndex: (Int) -> Void
    
    var pageSize: Int {
        return gridRows * gridCols
    }
    
    var currentPage: Int {
        guard !windows.isEmpty else { return 0 }
        return currentIndex / pageSize
    }
    
    var uniqueApps: [String] {
        var seen = Set<String>()
        var list = [String]()
        for w in windows {
            if !seen.contains(w.ownerName) {
                seen.insert(w.ownerName)
                list.append(w.ownerName)
            }
        }
        return list
    }
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let spacing = 20.0 * scale
        let totalCardsWidth = cardWidth * Double(gridCols)
        let totalSpacingWidth = spacing * Double(gridCols - 1)
        let contentWidth = totalCardsWidth + totalSpacingWidth
        
        let cardTotalHeight = 132.0 * scale // 106 height + 10 spacing + 16 text
        let gridHeight = (cardTotalHeight * Double(gridRows)) + (spacing * Double(gridRows - 1))
        
        HStack(spacing: 0) {
            // Task 5: App Sidebar Grouping
            VStack(spacing: 14) {
                Button(action: { appState.selectedAppFilter = nil }) {
                    VStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(appState.selectedAppFilter == nil ? .blue : .white.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(appState.selectedAppFilter == nil ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(appState.selectedAppFilter == nil ? Color.blue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.5)
                            )
                        Text("All")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundColor(appState.selectedAppFilter == nil ? .white : .white.opacity(0.5))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Divider()
                    .background(Color.white.opacity(0.1))
                    .padding(.horizontal, 10)
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(uniqueApps, id: \.self) { app in
                            let isSelected = appState.selectedAppFilter == app
                            let icon = windows.first(where: { $0.ownerName == app })?.appIcon
                            
                            Button(action: {
                                if isSelected {
                                    appState.selectedAppFilter = nil
                                } else {
                                    appState.selectedAppFilter = app
                                }
                            }) {
                                VStack(spacing: 4) {
                                    ZStack {
                                        if let nsIcon = icon {
                                            Image(nsImage: nsIcon)
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                                .frame(width: 32, height: 32)
                                        } else {
                                            Image(systemName: "app")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                    }
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(isSelected ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.blue.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1.5)
                                    )
                                    
                                    Text(app)
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .foregroundColor(isSelected ? .white : .white.opacity(0.5))
                                        .lineLimit(1)
                                        .frame(width: 64)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(width: 80)
            .padding(.vertical, 16)
            .background(Color.black.opacity(0.15))
            .overlay(
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                }
            )
            
            // Switcher Grid Panel
            VStack(spacing: 16) {
                // Task 4: Fuzzy Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                        .font(.system(size: 14, weight: .bold))
                    
                    TextField("Search window titles or apps...", text: $appState.searchQuery, onEditingChanged: { isEditing in
                        appState.isSearchActive = isEditing
                    }, onCommit: {
                        NotificationCenter.default.post(
                            name: Notification.Name("commitSwitcherSelection"),
                            object: nil
                        )
                    })
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                    
                    if !appState.searchQuery.isEmpty {
                        Button(action: { appState.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.top, 16)
            // Selected Window Title Banner
            if currentIndex >= 0 && currentIndex < windows.count {
                let currentWindow = windows[currentIndex]
                VStack(spacing: 4) {
                    Text(currentWindow.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                    
                    Text(currentWindow.ownerName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(height: 44)
                .transition(.opacity)
            } else {
                VStack(spacing: 4) {
                    Text("No Active Windows")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Open windows will appear here")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                .frame(height: 44)
            }
            
            // Paginated Container Box with stable dimensions
            VStack(spacing: 12) {
                VStack(spacing: CGFloat(spacing)) {
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, windows.count)
                    
                    ForEach(0..<gridRows, id: \.self) { row in
                        HStack(spacing: CGFloat(spacing)) {
                            Spacer()
                            ForEach(0..<gridCols, id: \.self) { col in
                                let cardIndex = start + (row * gridCols) + col
                                if cardIndex < end {
                                    let window = windows[cardIndex]
                                    WindowCard(
                                        window: window,
                                        isSelected: cardIndex == currentIndex,
                                        scale: scale,
                                        enableHoverSwitch: enableHoverSwitch,
                                        refreshToken: refreshToken,
                                        onHover: { onHoverIndex(cardIndex) },
                                        onClick: { onClickIndex(cardIndex) },
                                        appState: appState
                                    )
                                    .id(window.id)
                                } else {
                                    // Empty slot filler to keep standard card bounds
                                    Color.clear
                                        .frame(width: CGFloat(cardWidth), height: CGFloat(cardTotalHeight))
                                }
                            }
                            Spacer()
                        }
                    }
                }
                .frame(width: CGFloat(contentWidth))
                
                // Page Indicator Dots
                let totalPages = Int(ceil(Double(windows.count) / Double(pageSize)))
                if totalPages > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { pageIndex in
                            Circle()
                                .fill(pageIndex == currentPage ? Color.blue : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .scaleEffect(pageIndex == currentPage ? 1.2 : 1.0)
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPage)
                        }
                    }
                    .frame(height: 10)
                } else {
                    Color.clear
                        .frame(height: 10)
                }
            }
            .frame(height: CGFloat(gridHeight + 15), alignment: .center)
            
            // Shortcut Help Footer
            Text("Release ⌥ (Option) to switch  •  Press ⎋ (Esc) to cancel")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 4)
        }
        }
        .padding(.vertical, 20)
        // Solid fixed width and height to prevent sizing jumps and keep window bounded on screen
        .frame(width: CGFloat(contentWidth + 60 + 80), height: CGFloat(gridHeight + 217))
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
    }
}

struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    let scale: Double
    let enableHoverSwitch: Bool
    let refreshToken: UUID
    let onHover: () -> Void
    let onClick: () -> Void
    @ObservedObject var appState: AppState
    
    @State private var thumbnail: NSImage? = nil
    
    var body: some View {
        let cardWidth = 170.0 * scale
        
        VStack(spacing: 10) {
            CardThumbnailView(
                window: window,
                isSelected: isSelected,
                scale: scale,
                enableHoverSwitch: enableHoverSwitch,
                refreshToken: refreshToken,
                onHover: onHover,
                onClick: onClick,
                appState: appState,
                thumbnail: thumbnail
            )
            
            // App Details Text
            HStack(spacing: 6) {
                if thumbnail == nil, let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: CGFloat(16 * scale), height: CGFloat(16 * scale))
                }
                
                Text(window.ownerName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: CGFloat(cardWidth))
        }
        .onAppear {
            loadThumbnail()
        }
        .onChange(of: refreshToken) { _ in
            thumbnail = nil
            loadThumbnail()
        }
        .onChange(of: window.id) { _ in
            thumbnail = nil
            loadThumbnail()
        }
    }
    
    private func loadThumbnail() {
        DispatchQueue.global(qos: .userInteractive).async {
            if let cgImage = WindowList.getThumbnail(for: window.id) {
                let size = NSSize(width: cgImage.width, height: cgImage.height)
                let nsImage = NSImage(cgImage: cgImage, size: size)
                DispatchQueue.main.async {
                    self.thumbnail = nsImage
                }
            }
        }
    }
}

struct CardThumbnailView: View {
    let window: WindowInfo
    let isSelected: Bool
    let scale: Double
    let enableHoverSwitch: Bool
    let refreshToken: UUID
    let onHover: () -> Void
    let onClick: () -> Void
    @ObservedObject var appState: AppState
    let thumbnail: NSImage?
    
    @State private var dragOffset = CGSize.zero
    @State private var isFadingOut = false
    @State private var rotationAngle = 0.0
    
    var isRainbow: Bool { appState.activeTheme == "Rainbow Sweep" }
    var isNeon: Bool { appState.activeTheme == "Neon Blue" }
    var isMinimal: Bool { appState.activeTheme == "Ultra Minimal" }
    
    var borderColor: Color {
        if isSelected {
            if isRainbow || isNeon {
                return .clear
            } else {
                return .blue
            }
        } else {
            if isMinimal {
                return Color.gray.opacity(0.3)
            } else {
                return Color.white.opacity(0.12)
            }
        }
    }
    
    var borderWidth: CGFloat {
        return isSelected ? 3.0 : 1.0
    }
    
    var shadowColor: Color {
        if isSelected {
            if isNeon {
                return Color.cyan.opacity(0.8)
            } else if isRainbow {
                return Color.purple.opacity(0.6)
            } else {
                return Color.blue.opacity(0.6)
            }
        } else {
            return .clear
        }
    }
    
    var shadowRadius: CGFloat {
        if isSelected {
            return isNeon ? 12 : 8
        } else {
            return 0
        }
    }
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let cardHeight = 106.0 * scale
        
        let rainbow = AngularGradient(
            colors: [.red, .yellow, .green, .blue, .purple, .red],
            center: .center,
            angle: .degrees(rotationAngle)
        )
        
        let neon = AngularGradient(
            colors: [.cyan, .blue, .purple, .cyan],
            center: .center,
            angle: .degrees(rotationAngle)
        )
        
        ZStack {
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: CGFloat(cardWidth), height: CGFloat(cardHeight))
                    .clipped()
            } else {
                // Fallback visual with beautiful dark gradient
                LinearGradient(
                    colors: [Color(nsColor: .darkGray).opacity(0.6), Color(nsColor: .black).opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(width: CGFloat(cardWidth), height: CGFloat(cardHeight))
                
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: CGFloat(52 * scale), height: CGFloat(52 * scale))
                        .shadow(color: Color.black.opacity(0.4), radius: CGFloat(6 * scale), x: 0, y: CGFloat(3 * scale))
                }
            }
            
            // Small App Icon badge in bottom-left corner of thumbnail
            if thumbnail != nil, let icon = window.appIcon {
                VStack {
                    Spacer()
                    HStack {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: CGFloat(24 * scale), height: CGFloat(24 * scale))
                            .padding(CGFloat(4 * scale))
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(CGFloat(6 * scale))
                            .shadow(radius: 2)
                        Spacer()
                    }
                }
                .padding(CGFloat(8 * scale))
            }
            
            // Action Buttons capsule bar (Close, Minimize, Maximize, Force Quit) + Layout Snapping
            if isSelected {
                VStack {
                    HStack {
                        Spacer()
                        ActionPanel(
                            window: window,
                            scale: scale,
                            onClose: { postWindowAction("close", window: window) },
                            onMinimize: { postWindowAction("minimize", window: window) },
                            onZoom: { postWindowAction("zoom", window: window) },
                            onExitFS: { postWindowAction("exitFullScreen", window: window) },
                            onForceQuit: { postWindowAction("forceQuit", window: window) },
                            onSnapLeft: { WindowList.resizeWindow(window: window, action: "leftHalf") },
                            onSnapMaximize: { WindowList.resizeWindow(window: window, action: "maximize") },
                            onSnapRight: { WindowList.resizeWindow(window: window, action: "rightHalf") }
                        )
                    }
                    Spacer()
                }
            }
        }
        .frame(width: CGFloat(cardWidth), height: CGFloat(cardHeight))
        .cornerRadius(12)
        .overlay(
            Group {
                if isSelected {
                    if isRainbow {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(rainbow, lineWidth: 3.0)
                    } else if isNeon {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(neon, lineWidth: 3.0)
                    }
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
                .shadow(color: shadowColor, radius: shadowRadius)
        )
        .scaleEffect(isSelected ? 1.08 : 1.0)
        .offset(y: dragOffset.height)
        .opacity(isFadingOut ? 0.0 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if gesture.translation.height < 0 {
                        dragOffset = gesture.translation
                    }
                }
                .onEnded { gesture in
                    if gesture.translation.height < -80 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset.height = -300
                            isFadingOut = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            postWindowAction("close", window: window)
                            dragOffset = .zero
                            isFadingOut = false
                        }
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .onHover { isHovered in
            if isHovered && enableHoverSwitch && !isSelected {
                onHover()
            }
        }
        .onTapGesture {
            onClick()
        }
        .onAppear {
            if isRainbow || isNeon {
                withAnimation(Animation.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360.0
                }
            }
        }
    }
    
    private func postWindowAction(_ action: String, window: WindowInfo) {
        NotificationCenter.default.post(
            name: Notification.Name("performWindowAction"),
            object: nil,
            userInfo: ["action": action, "window": window]
        )
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let scale: Double
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(isHovered ? color.opacity(0.95) : color.opacity(0.75))
                .frame(width: CGFloat(16 * scale), height: CGFloat(16 * scale))
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: CGFloat(8 * scale), weight: .bold))
                        .foregroundColor(.white)
                )
                .scaleEffect(isHovered ? 1.15 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ActionPanel: View {
    let window: WindowInfo
    let scale: Double
    let onClose: () -> Void
    let onMinimize: () -> Void
    let onZoom: () -> Void
    let onExitFS: () -> Void
    let onForceQuit: () -> Void
    let onSnapLeft: () -> Void
    let onSnapMaximize: () -> Void
    let onSnapRight: () -> Void
    
    var body: some View {
        VStack(spacing: CGFloat(6 * scale)) {
            HStack(spacing: CGFloat(6 * scale)) {
                // Close (Red)
                ActionButton(icon: "xmark", color: .red, scale: scale, action: onClose)
                
                // Minimize (Yellow)
                ActionButton(icon: "minus", color: .yellow, scale: scale, action: onMinimize)
                
                // Zoom/Maximize (Green)
                ActionButton(icon: "arrow.up.left.and.arrow.down.right", color: .green, scale: scale, action: onZoom)
                
                // Exit Full Screen (Purple)
                ActionButton(icon: "arrow.down.right.and.arrow.up.left", color: .purple, scale: scale, action: onExitFS)
                
                // Force Quit (Gray)
                ActionButton(icon: "power", color: .gray, scale: scale, action: onForceQuit)
            }
            
            // Layout Snapping (Left half, Maximize, Right half)
            HStack(spacing: CGFloat(6 * scale)) {
                ActionButton(icon: "arrow.left.to.line", color: .blue, scale: scale, action: onSnapLeft)
                ActionButton(icon: "square.dashed", color: .cyan, scale: scale, action: onSnapMaximize)
                ActionButton(icon: "arrow.right.to.line", color: .blue, scale: scale, action: onSnapRight)
            }
        }
        .padding(CGFloat(5 * scale))
        .background(Color.black.opacity(0.75))
        .cornerRadius(CGFloat(10 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: CGFloat(10 * scale))
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .padding(CGFloat(6 * scale))
    }
}

