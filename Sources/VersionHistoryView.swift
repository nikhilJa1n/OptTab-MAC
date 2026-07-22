import SwiftUI

public struct VersionHistoryView: View {
    @Environment(\.presentationMode) var presentationMode
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.blue)
                        Text("Version History & Release Notes")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Text("Explore what's new and recent updates in OptTab")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Release Notes List
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(VersionHistory.releases) { release in
                        ReleaseCardView(release: release)
                    }
                }
                .padding(16)
            }
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            // Footer
            HStack {
                Text("OptTab for macOS • Made with ❤️")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.35))
                Spacer()
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("Close")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.8))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(12)
            .background(Color.white.opacity(0.02))
        }
        .frame(width: 520, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ReleaseCardView: View {
    let release: VersionRelease
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Version header row
            HStack(spacing: 8) {
                Text("v\(release.version)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                if release.isCurrent {
                    Text("CURRENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.blue.opacity(0.4), lineWidth: 0.5)
                        )
                }
                
                Spacer()
                
                Text(release.releaseDate)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Text(release.summary)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
                .lineSpacing(2)
            
            // Features
            if !release.features.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEW FEATURES & IMPROVEMENTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue.opacity(0.9))
                        .tracking(0.5)
                    
                    ForEach(release.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(.blue)
                            Text(feature)
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 2)
            }
            
            // Fixes
            if !release.fixes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BUG FIXES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.green.opacity(0.9))
                        .tracking(0.5)
                    
                    ForEach(release.fixes, id: \.self) { fix in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundColor(.green)
                            Text(fix)
                                .font(.system(size: 10.5))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(release.isCurrent ? Color.blue.opacity(0.06) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(release.isCurrent ? Color.blue.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 0.8)
        )
    }
}
