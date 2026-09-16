import Foundation

public struct AppLogger {
    private static let logQueue = DispatchQueue(label: "com.nikhiljain.opttab.logger", qos: .utility)
    
    public static var logFileURL: URL {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/OptTab", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("opt_tab_debug.log")
    }
    
    public static func log(_ message: String) {
        let timestamp = Date()
        logQueue.async {
            let fileURL = logFileURL
            let formattedMsg = "\(timestamp): \(message)\n"
            guard let data = formattedMsg.data(using: .utf8) else { return }
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fh = try? FileHandle(forWritingTo: fileURL) {
                    do {
                        try fh.seekToEnd()
                        try fh.write(contentsOf: data)
                        try fh.close()
                    } catch {
                        try? fh.close()
                    }
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
