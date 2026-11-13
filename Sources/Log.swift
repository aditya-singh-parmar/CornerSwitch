import Foundation

/// Appends to ~/Library/Logs/CornerSwitch.log (kept under 200 KB) and the system log.
func clog(_ s: String) {
    NSLog("CornerSwitch: %@", s)
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CornerSwitch.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
       (attrs[.size] as? Int ?? 0) > 200_000 {
        try? FileManager.default.removeItem(at: url)
    }
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
