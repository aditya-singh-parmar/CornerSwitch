// When switching should hold off: screen locked, or a presentation, call or video
// app is in front and full screen. (A screen share from a normal window can't be
// detected without extra permissions, so it isn't covered.)

import AppKit

enum Pause {
    static let fullScreenApps: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.apple.FaceTime",
        "com.apple.QuickTimePlayerX", "org.videolan.vlc", "com.colliderli.iina", "com.apple.TV",
    ]

    static func reason() -> String? {
        if screenLocked() { return "screen locked" }
        if let app = NSWorkspace.shared.frontmostApplication,
           let id = app.bundleIdentifier, fullScreenApps.contains(id),
           isFullScreen(pid: app.processIdentifier) {
            return "\(app.localizedName ?? id) is full screen"
        }
        return nil
    }

    static func screenLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return d["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    /// A normal-layer window of the app exactly covers a screen.
    static func isFullScreen(pid: pid_t) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let sizes = NSScreen.screens.map(\.frame.size)
        for w in list {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { continue }
            if sizes.contains(where: { abs($0.width - width) < 1 && abs($0.height - height) < 1 }) { return true }
        }
        return false
    }
}
