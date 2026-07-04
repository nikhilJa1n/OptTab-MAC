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
    let windows: [WindowInfo]
    let currentIndex: Int
    let scale: Double
    let enableHoverSwitch: Bool
    let onHoverIndex: (Int) -> Void
    let onClickIndex: (Int) -> Void
    
    // Contain thumbnails in boxes (pages) of size 5
    let pageSize = 5
    
    var currentPage: Int {
        guard !windows.isEmpty else { return 0 }
        return currentIndex / pageSize
    }
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let spacing = 20.0 * scale
        let totalCardsWidth = cardWidth * Double(pageSize)
        let totalSpacingWidth = spacing * Double(pageSize - 1)
        let contentWidth = totalCardsWidth + totalSpacingWidth
        
        VStack(spacing: 16) {
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
                HStack(spacing: CGFloat(spacing)) {
                    Spacer()
                    let start = currentPage * pageSize
                    let end = min(start + pageSize, windows.count)
                    
                    if start < windows.count {
                        ForEach(start..<end, id: \.self) { index in
                            let window = windows[index]
                            WindowCard(
                                window: window,
                                isSelected: index == currentIndex,
                                scale: scale,
                                enableHoverSwitch: enableHoverSwitch,
                                onHover: { onHoverIndex(index) },
                                onClick: { onClickIndex(index) }
                            )
                            .id(window.id)
                        }
                    }
                    Spacer()
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
                    // Spacer buffer when there is only 1 page to preserve vertical layout height
                    Spacer()
                        .frame(height: 10)
                }
            }
            .frame(height: CGFloat(160 * scale + 15), alignment: .center)
            
            // Shortcut Help Footer
            Text("Release ⌥ (Option) to switch  •  Press ⎋ (Esc) to cancel")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 4)
        }
        .padding(.vertical, 20)
        // Solid fixed width to prevent resizing jumps
        .frame(width: CGFloat(contentWidth + 60))
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
    let onHover: () -> Void
    let onClick: () -> Void
    
    @State private var thumbnail: NSImage? = nil
    
    var body: some View {
        let cardWidth = 170.0 * scale
        let cardHeight = 106.0 * scale
        
        VStack(spacing: 10) {
            // Thumbnail Container
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
                
                // Action Buttons capsule bar (Close, Minimize, Maximize, Force Quit)
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: CGFloat(6 * scale)) {
                                // Close (Red)
                                ActionButton(icon: "xmark", color: .red, scale: scale) {
                                    WindowList.performWindowAction(window: window, actionAttribute: kAXCloseButtonAttribute as CFString)
                                    notifyActionTriggered()
                                }
                                
                                // Minimize (Yellow)
                                ActionButton(icon: "minus", color: .yellow, scale: scale) {
                                    WindowList.performWindowAction(window: window, actionAttribute: kAXMinimizeButtonAttribute as CFString)
                                    notifyActionTriggered()
                                }
                                
                                // Zoom/Maximize (Green)
                                ActionButton(icon: "arrow.up.left.and.arrow.down.right", color: .green, scale: scale) {
                                    WindowList.performWindowAction(window: window, actionAttribute: kAXZoomButtonAttribute as CFString)
                                }
                                
                                // Force Quit (Gray)
                                ActionButton(icon: "power", color: .gray, scale: scale) {
                                    WindowList.forceQuit(window: window)
                                    notifyActionTriggered()
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
                        Spacer()
                    }
                }
            }
            .frame(width: CGFloat(cardWidth), height: CGFloat(cardHeight))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.blue : Color.white.opacity(0.12),
                        lineWidth: isSelected ? 3.0 : 1.0
                    )
                    .shadow(color: isSelected ? Color.blue.opacity(0.6) : Color.clear, radius: 8)
            )
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
            .onHover { isHovered in
                if isHovered && enableHoverSwitch && !isSelected {
                    onHover()
                }
            }
            .onTapGesture {
                onClick()
            }
            
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
    }
    
    private func notifyActionTriggered() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: Notification.Name("windowActionTriggered"), object: nil)
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
