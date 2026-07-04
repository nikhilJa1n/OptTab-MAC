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
    
    var body: some View {
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
            
            // Horizontal list of windows
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<windows.count, id: \.self) { index in
                            WindowCard(
                                window: windows[index],
                                isSelected: index == currentIndex
                            )
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .onChange(of: currentIndex) { old, new in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
            }
            
            // Shortcut Help Footer
            Text("Release ⌥ (Option) to switch  •  Press ⎋ (Esc) to cancel")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.4))
                .padding(.bottom, 4)
        }
        .padding(.vertical, 20)
        .frame(minWidth: 400, maxWidth: 850)
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
    
    @State private var thumbnail: NSImage? = nil
    
    var body: some View {
        VStack(spacing: 10) {
            // Thumbnail Container
            ZStack {
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 170, height: 106)
                        .clipped()
                } else {
                    // Fallback visual with beautiful dark gradient
                    LinearGradient(
                        colors: [Color(nsColor: .darkGray).opacity(0.6), Color(nsColor: .black).opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .frame(width: 170, height: 106)
                    
                    if let icon = window.appIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                            .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
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
                                .frame(width: 24, height: 24)
                                .padding(4)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(6)
                                .shadow(radius: 2)
                            Spacer()
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 170, height: 106)
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
            
            // App Details Text
            HStack(spacing: 6) {
                if thumbnail == nil, let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
                
                Text(window.ownerName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(width: 170)
        }
        .onAppear {
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
