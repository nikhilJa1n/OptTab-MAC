import SwiftUI
import CoreGraphics

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    var cornerRadius: CGFloat = 0
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        
        if cornerRadius > 0 {
            view.wantsLayer = true
            view.layer?.cornerRadius = cornerRadius
            view.layer?.masksToBounds = true
        }
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        
        if cornerRadius > 0 {
            nsView.wantsLayer = true
            nsView.layer?.cornerRadius = cornerRadius
            nsView.layer?.masksToBounds = true
        }
    }
}

struct SwitcherView: View {
    @ObservedObject var appState: AppState
    let windows: [WindowInfo]
    let currentIndex: Int
    let scale: Double
    let refreshToken: UUID
    let onHoverIndex: (Int) -> Void
    let onClickIndex: (Int) -> Void
    
    var gridCols: Int {
        return min(windows.count, 5) > 0 ? min(windows.count, 5) : 5
    }
    
    var pageSize: Int {
        return gridCols
    }
    
    var currentPage: Int {
        guard !windows.isEmpty else { return 0 }
        return currentIndex / pageSize
    }
    
    var footerText: String {
        let cmdRequired = (appState.hotkeyModifiers & 1) != 0
        let optRequired = (appState.hotkeyModifiers & 2) != 0
        let ctrlRequired = (appState.hotkeyModifiers & 4) != 0
        
        var modName = ""
        if cmdRequired { modName += "⌘ (Command) " }
        else if optRequired { modName += "⌥ (Option) " }
        else if ctrlRequired { modName += "⌃ (Control) " }
        else { modName += "Shortcut " }
        
        return "Release \(modName)to switch  •  Press ⎋ (Esc) to cancel"
    }
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let spacing = 20.0 * scale
        
        let cols = appState.useGridLayout ? (min(windows.count, 4) > 0 ? min(windows.count, 4) : 4) : gridCols
        let rows = appState.useGridLayout ? max(1, Int(ceil(Double(windows.count) / Double(cols)))) : 1
        
        let totalCardsWidth = cardWidth * Double(cols)
        let totalSpacingWidth = spacing * Double(cols - 1)
        let contentWidth = totalCardsWidth + totalSpacingWidth
        
        let cardTotalHeight = 132.0 * scale // 106 height + 10 spacing + 16 text
        let gridHeight = appState.useGridLayout ? (cardTotalHeight * Double(rows) + spacing * Double(rows - 1)) : cardTotalHeight
        
        VStack(spacing: 16) {
            // Selected Window Title Banner
            if currentIndex >= 0 && currentIndex < windows.count {
                let currentWindow = windows[currentIndex]
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        if let icon = currentWindow.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                        }
                        Text(currentWindow.ownerName)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Text(currentWindow.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }
                .frame(height: 48)
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
            
            // Container Box (Grid or Paginated Horizontal Row)
            VStack(spacing: 12) {
                if appState.useGridLayout {
                    // 2D Grid Layout
                    VStack(spacing: CGFloat(spacing)) {
                        ForEach(0..<rows, id: \.self) { rowIndex in
                            HStack(spacing: CGFloat(spacing)) {
                                let start = rowIndex * cols
                                let end = min(start + cols, windows.count)
                                
                                ForEach(start..<end, id: \.self) { cardIndex in
                                    let window = windows[cardIndex]
                                    WindowCard(
                                        window: window,
                                        isSelected: cardIndex == currentIndex,
                                        scale: scale,
                                        refreshToken: refreshToken,
                                        onHover: { onHoverIndex(cardIndex) },
                                        onClick: { onClickIndex(cardIndex) },
                                        appState: appState
                                    )
                                    .id(window.id)
                                }
                                
                                if (end - start) < cols {
                                    ForEach(0..<(cols - (end - start)), id: \.self) { _ in
                                        Color.clear
                                            .frame(width: CGFloat(cardWidth), height: CGFloat(cardTotalHeight))
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: CGFloat(gridHeight + 15), alignment: .center)
                    
                    // No dots page indicator needed in grid layout
                    Color.clear
                        .frame(height: 10)
                } else {
                    // Paginated Horizontal Row
                    HStack(spacing: CGFloat(spacing)) {
                        Spacer()
                        let start = currentPage * pageSize
                        let end = min(start + pageSize, windows.count)
                        
                        ForEach(start..<end, id: \.self) { cardIndex in
                            let window = windows[cardIndex]
                            WindowCard(
                                window: window,
                                isSelected: cardIndex == currentIndex,
                                scale: scale,
                                refreshToken: refreshToken,
                                onHover: { onHoverIndex(cardIndex) },
                                onClick: { onClickIndex(cardIndex) },
                                appState: appState
                            )
                            .id(window.id)
                        }
                        Spacer()
                    }
                    .frame(height: CGFloat(gridHeight + 15), alignment: .center)
                    
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
            }
            
            // Shortcut Help Footer
            Text(footerText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 4)
        }
        .padding(.vertical, 20)
        // Solid fixed width and height to prevent sizing jumps and keep window bounded on screen
        .frame(width: CGFloat(contentWidth + 60), height: CGFloat(gridHeight + 160))
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                )
        )
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
        .overlay(
            VStack {
                HStack {
                    Spacer()
                    // System Resource Widget
                    HStack(spacing: 12) {
                        // CPU Usage Info
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                            Text(String(format: "%.0f%%", appState.cpuUsage))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        
                        // RAM Usage Info
                        HStack(spacing: 4) {
                            Image(systemName: "memorychip")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                            
                            let usedGB = appState.ramUsage.used / (1024 * 1024 * 1024)
                            let totalGB = appState.ramUsage.total / (1024 * 1024 * 1024)
                            Text(String(format: "%.1f/%.0fGB", usedGB, totalGB))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.25))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 16)
                }
                Spacer()
            }
        )
        .onAppear {
            appState.startStatsMonitoring()
        }
        .onDisappear {
            appState.stopStatsMonitoring()
        }
    }
}

struct WindowCard: View {
    let window: WindowInfo
    let isSelected: Bool
    let scale: Double
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
    let refreshToken: UUID
    let onHover: () -> Void
    let onClick: () -> Void
    @ObservedObject var appState: AppState
    let thumbnail: NSImage?
    
    @State private var dragOffset = CGSize.zero
    @State private var isFadingOut = false
    @State private var rotationAngle = 0.0
    @State private var isHovered = false
    
    var borderColor: Color {
        if isSelected { return .blue }
        if isHovered { return Color.white.opacity(0.4) }
        return Color.white.opacity(0.12)
    }
    
    var borderWidth: CGFloat {
        return isSelected ? 3.0 : 1.0
    }
    
    var shadowColor: Color {
        if isSelected { return Color.blue.opacity(0.4) }
        if isHovered { return Color.black.opacity(0.3) }
        return .clear
    }
    
    var shadowRadius: CGFloat {
        if isSelected { return 8 }
        if isHovered { return 4 }
        return 0
    }
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let cardHeight = 106.0 * scale
        
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
                    .padding(CGFloat(8 * scale))
                }
                .frame(width: CGFloat(cardWidth), height: CGFloat(cardHeight))
            }
            
            // Action Buttons capsule bar (Close, Minimize, Maximize, Force Quit) + Layout Snapping
            if isSelected || isHovered {
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
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
                .shadow(color: shadowColor, radius: shadowRadius)
        )
        .scaleEffect(isSelected ? 1.08 : (isHovered ? 1.04 : 1.0))
        .offset(y: dragOffset.height)
        .opacity(isFadingOut ? 0.0 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
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
        .onTapGesture {
            onClick()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                self.isHovered = hovering
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

