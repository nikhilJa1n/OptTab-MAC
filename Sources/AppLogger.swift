import Foundation

public struct AppLogger {
    public static var logFileURL: URL {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs/OptTab", isDirectory: true) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        return logsDir.appendingPathComponent("opt_tab_debug.log")
    }
    
    public static func log(_ message: String) {
        let fileURL = logFileURL
        let formattedMsg = "\(Date()): \(message)\n"
        if let data = formattedMsg.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fh = try? FileHandle(forWritingTo: fileURL) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    try? fh.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
