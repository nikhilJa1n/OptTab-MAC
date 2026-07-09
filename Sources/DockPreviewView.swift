import SwiftUI

struct DockPreviewView: View {
    let appName: String
    let windows: [WindowInfo]
    let scale: Double
    let onSelect: (WindowInfo) -> Void
    let onClose: (WindowInfo) -> Void
    
    var body: some View {
        let cardWidth = 160.0 * scale
        let cardHeight = 100.0 * scale
        let spacing = 12.0
        let padding = 12.0
        
        let maxCols = 3
        let cols = min(windows.count, maxCols)
        let rows = Int(ceil(Double(windows.count) / Double(cols)))
        
        let columns = Array(repeating: GridItem(.fixed(cardWidth), spacing: spacing), count: cols)
        
        let headerHeight = 22.0
        let cardTotalHeight = cardHeight + 20.0 // Card height + title text height
        
        let totalWidth = cardWidth * Double(cols) + spacing * Double(max(0, cols - 1)) + padding * 2
        let totalHeight = headerHeight + 12.0 + cardTotalHeight * Double(rows) + spacing * Double(max(0, rows - 1)) + padding * 2
        
        VStack(alignment: .leading, spacing: 12) {
            // App Header
            HStack(spacing: 8) {
                if let firstWindow = windows.first, let icon = firstWindow.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                }
                Text(appName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("•")
                    .foregroundColor(.white.opacity(0.3))
                
                Text("\(windows.count) window\(windows.count > 1 ? "s" : "")")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.55))
                
                Spacer()
            }
            .frame(height: headerHeight)
            .padding(.horizontal, 4)
            
            // Cards Grid
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(windows) { window in
                    DockPreviewCard(
                        window: window,
                        scale: scale,
                        onSelect: { onSelect(window) },
                        onClose: { onClose(window) }
                    )
                }
            }
        }
        .padding(padding)
        .frame(width: totalWidth, height: totalHeight)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
        )
    }
}

struct DockPreviewCard: View {
    let window: WindowInfo
    let scale: Double
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var thumbnail: NSImage?
    @State private var isHovered = false
    
    var body: some View {
        let cardWidth = 160.0 * scale
        let cardHeight = 100.0 * scale
        
        VStack(spacing: 6) {
            ZStack {
                // Thumbnail container
                ZStack {
                    if let img = thumbnail {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                    } else {
                        // Fallback background with beautiful dark gradient
                        LinearGradient(
                            colors: [Color(nsColor: .darkGray).opacity(0.6), Color(nsColor: .black).opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(width: cardWidth, height: cardHeight)
                        
                        if let icon = window.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: CGFloat(40 * scale), height: CGFloat(40 * scale))
                                .shadow(color: Color.black.opacity(0.4), radius: CGFloat(4 * scale), x: 0, y: CGFloat(2 * scale))
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
                                    .frame(width: CGFloat(20 * scale), height: CGFloat(20 * scale))
                                    .padding(CGFloat(3 * scale))
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(5)
                                    .shadow(radius: 1)
                                Spacer()
                            }
                        }
                        .padding(8)
                        .frame(width: cardWidth, height: cardHeight)
                    }
                }
                .frame(width: cardWidth, height: cardHeight)
                .background(Color.white.opacity(0.04))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isHovered ? Color.blue.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1.5)
                )
                
                // Close button overlay on hover
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Color.red.opacity(0.85))
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.3), radius: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .onHover { hover in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hover
                }
            }
            .onTapGesture {
                onSelect()
            }
            
            // Window title text
            Text(window.title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.75))
                .lineLimit(1)
                .frame(width: cardWidth)
        }
        .onAppear {
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
