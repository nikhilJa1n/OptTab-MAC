import Foundation
import AppKit

struct UpdateInfo: Codable {
    let version: String
    let downloadUrl: String
    let changelog: String
    let isPrerelease: Bool?
}

class UpdateChecker {
    static let shared = UpdateChecker()
    
    // Raw GitHub URLs for hosted update feeds
    private let stableUpdateURLString = "https://raw.githubusercontent.com/nikhilJa1n/OptTab-MAC/main/update.json"
    private let alphaUpdateURLString = "https://raw.githubusercontent.com/nikhilJa1n/OptTab-MAC/main/update-alpha.json"
    
    func checkForUpdates(verbose: Bool = false) {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let isInstalledAlpha = currentVersion.lowercased().contains("alpha") ||
                               currentVersion.lowercased().contains("beta") ||
                               currentVersion.lowercased().contains("rc")
        let includeAlpha = UserDefaults.standard.bool(forKey: "includeAlphaUpdates") || isInstalledAlpha
        
        if includeAlpha {
            // First check the Alpha / Pre-release feed
            fetchUpdateInfo(urlString: alphaUpdateURLString) { [weak self] alphaInfo in
                guard let self = self else { return }
                if let alphaInfo = alphaInfo, self.isVersion(alphaInfo.version, newerThan: currentVersion) {
                    self.showUpdateAvailableAlert(info: alphaInfo, isAlpha: true)
                    return
                }
                
                // If alpha feed has no newer version, check stable feed (so alpha users automatically upgrade to final stable releases)
                self.fetchUpdateInfo(urlString: self.stableUpdateURLString) { [weak self] stableInfo in
                    guard let self = self else { return }
                    if let stableInfo = stableInfo, self.isVersion(stableInfo.version, newerThan: currentVersion) {
                        self.showUpdateAvailableAlert(info: stableInfo, isAlpha: false)
                    } else if verbose {
                        self.showAlertOnMainQueue(title: "Up to Date", message: "OptTab \(currentVersion) is currently the newest version available on the Alpha channel.")
                    }
                }
            }
        } else {
            // Stable channel only
            fetchUpdateInfo(urlString: stableUpdateURLString) { [weak self] stableInfo in
                guard let self = self else { return }
                if let stableInfo = stableInfo, self.isVersion(stableInfo.version, newerThan: currentVersion) {
                    self.showUpdateAvailableAlert(info: stableInfo, isAlpha: false)
                } else if verbose {
                    self.showAlertOnMainQueue(title: "Up to Date", message: "OptTab \(currentVersion) is currently the newest version available.")
                }
            }
        }
    }
    
    private func fetchUpdateInfo(urlString: String, completion: @escaping (UpdateInfo?) -> Void) {
        guard var components = URLComponents(string: urlString) else {
            completion(nil)
            return
        }
        components.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        guard let url = components.url else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let data = data else {
                completion(nil)
                return
            }
            
            do {
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                completion(info)
            } catch {
                completion(nil)
            }
        }
        task.resume()
    }
    
    /// Standard SemVer 2.0.0 comparison supporting core versions (major.minor.patch) and pre-release tags (alpha.1, beta.2)
    func isVersion(_ versionA: String, newerThan versionB: String) -> Bool {
        func parseSemVer(_ v: String) -> (core: [Int], pre: [String]) {
            var clean = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if clean.hasPrefix("v") {
                clean = String(clean.dropFirst())
            }
            let parts = clean.components(separatedBy: "-")
            let coreParts = parts.first?.components(separatedBy: ".").compactMap { Int($0) } ?? []
            let preParts = parts.count > 1 ? parts[1].components(separatedBy: ".") : []
            return (coreParts, preParts)
        }
        
        let parsedA = parseSemVer(versionA)
        let parsedB = parseSemVer(versionB)
        
        // 1. Compare numeric core parts [major, minor, patch]
        let maxCoreLen = max(parsedA.core.count, parsedB.core.count)
        for i in 0..<maxCoreLen {
            let partA = i < parsedA.core.count ? parsedA.core[i] : 0
            let partB = i < parsedB.core.count ? parsedB.core[i] : 0
            if partA > partB { return true }
            if partA < partB { return false }
        }
        
        // 2. Core versions are identical. Check pre-release tags.
        // SemVer rule: A final release without pre-release tag is NEWER than any pre-release tag on the same core version.
        // e.g., "3.5" is newer than "3.5-alpha.2"
        let hasPreA = !parsedA.pre.isEmpty
        let hasPreB = !parsedB.pre.isEmpty
        
        if !hasPreA && hasPreB {
            return true // A is stable final, B is pre-release -> A is newer
        }
        if hasPreA && !hasPreB {
            return false // A is pre-release, B is stable final -> A is older
        }
        if !hasPreA && !hasPreB {
            return false // Both are stable with identical core -> equal
        }
        
        // 3. Both have pre-release identifiers (e.g. ["alpha", "2"] vs ["alpha", "1"])
        let maxPreLen = max(parsedA.pre.count, parsedB.pre.count)
        for i in 0..<maxPreLen {
            if i >= parsedB.pre.count { return true }
            if i >= parsedA.pre.count { return false }
            let subA = parsedA.pre[i]
            let subB = parsedB.pre[i]
            
            if let intA = Int(subA), let intB = Int(subB) {
                if intA > intB { return true }
                if intA < intB { return false }
            } else {
                let cmp = subA.compare(subB)
                if cmp == .orderedDescending { return true }
                if cmp == .orderedAscending { return false }
            }
        }
        
        return false
    }
    
    private func showUpdateAvailableAlert(info: UpdateInfo, isAlpha: Bool) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            let isPre = isAlpha || (info.isPrerelease ?? false)
            alert.messageText = isPre ? "🧪 OptTab v\(info.version) [Alpha Preview] is Available!" : "✨ OptTab v\(info.version) is Available!"
            let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            
            let channelNotice = isPre ? "\n[Channel: Alpha / Preview Track — Features may be experimental]\n" : ""
            
            alert.informativeText = """
            A new version of OptTab is ready for download.\(channelNotice)
            Current Installed Version: v\(currentVer)
            New Release Version: v\(info.version)
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            WHAT'S NEW IN VERSION \(info.version):
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            \(info.changelog)
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Version History")
            alert.addButton(withTitle: "Remind Me Later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(string: info.downloadUrl) {
                    NSWorkspace.shared.open(url)
                }
            } else if response == .alertSecondButtonReturn {
                NotificationCenter.default.post(name: Notification.Name("showVersionHistory"), object: nil)
            }
        }
    }
    
    private func showAlertOnMainQueue(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
