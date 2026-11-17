import Foundation

private let logQueue = DispatchQueue(label: "cornerswitch.log", qos: .utility)
private let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/CornerSwitch.log")
private let logFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isRealApp = Bundle.main.bundleIdentifier == "com.aditya.cornerswitch"

/// Appends to ~/Library/Logs/CornerSwitch.log (kept under 200 KB) and the system log.
/// The caller only captures the time; formatting and disk I/O happen on a background
/// queue, so logging never slows a switch.
func clog(_ s: String) {
    let now = Date()
    logQueue.async {
        NSLog("CornerSwitch: %@", s)
        // Only the real app writes the log file (test harnesses just print).
        guard isRealApp else { return }
        let line = "\(logFormatter.string(from: now)) \(s)\n"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           (attrs[.size] as? Int ?? 0) > 200_000 {
            try? FileManager.default.removeItem(at: logURL)
        }
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }
}
