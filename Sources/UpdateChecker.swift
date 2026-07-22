import Foundation
import AppKit

struct UpdateInfo: Codable {
    let version: String
    let downloadUrl: String
    let changelog: String
}

class UpdateChecker {
    static let shared = UpdateChecker()
    
    // Raw GitHub URL for the hosted update JSON file
    private let updateURLString = "https://raw.githubusercontent.com/nikhilJa1n/OptTab-MAC/main/update.json"
    
    func checkForUpdates(verbose: Bool = false) {
        guard var components = URLComponents(string: updateURLString) else { return }
        components.queryItems = [URLQueryItem(name: "t", value: "\(Int(Date().timeIntervalSince1970))")]
        guard let url = components.url else { return }
        
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                if verbose {
                    self.showAlertOnMainQueue(title: "Update Error", message: "Could not fetch update info: \(error.localizedDescription)")
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                if verbose {
                    if httpResponse.statusCode == 404 {
                        self.showAlertOnMainQueue(title: "No Update Info Found", message: "No update file is hosted yet. You will need to upload 'update.json' to your GitHub repository first.")
                    } else {
                        self.showAlertOnMainQueue(title: "Update Error", message: "Server returned HTTP status code \(httpResponse.statusCode).")
                    }
                }
                return
            }
            
            guard let data = data else {
                if verbose {
                    self.showAlertOnMainQueue(title: "Update Error", message: "No data received from update server.")
                }
                return
            }
            
            do {
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                
                if self.isVersion(info.version, newerThan: currentVersion) {
                    self.showUpdateAvailableAlert(info: info)
                } else if verbose {
                    self.showAlertOnMainQueue(title: "Up to Date", message: "OptTab \(currentVersion) is currently the newest version available.")
                }
            } catch {
                if verbose {
                    self.showAlertOnMainQueue(title: "Update Error", message: "Failed to parse update information: \(error.localizedDescription)")
                }
            }
        }
        task.resume()
    }
    
    private func isVersion(_ versionA: String, newerThan versionB: String) -> Bool {
        return versionA.compare(versionB, options: .numeric) == .orderedDescending
    }
    
    private func showUpdateAvailableAlert(info: UpdateInfo) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "✨ OptTab v\(info.version) is Available!"
            let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            
            alert.informativeText = """
            A new version of OptTab is ready for download.
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
                // Open Version History sheet/window
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
