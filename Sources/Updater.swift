// Self-updater: checks GitHub Releases, downloads CornerSwitch.zip, checks the new
// build is signed by the same certificate as this one, swaps it into place and relaunches.

import AppKit
import Security

final class Updater {
    static let repo = "aditya-singh-parmar/CornerSwitch"
    private var timer: Timer?
    private var latestAsset: URL?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check(userInitiated: Bool = false) {
        let state = AppState.shared
        if case .installing = state.update { return }
        state.update = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("CornerSwitch-Updater", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, _, error in
            DispatchQueue.main.async {
                guard let data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = json["tag_name"] as? String else {
                    state.update = .failed("Couldn't reach GitHub")
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = json["assets"] as? [[String: Any]] ?? []
                let zip = assets.first { ($0["name"] as? String) == "CornerSwitch.zip" }
                guard Self.isNewer(version, than: state.version),
                      let urlString = zip?["browser_download_url"] as? String,
                      let url = URL(string: urlString) else {
                    state.update = .upToDate
                    return
                }
                self.latestAsset = url
                state.update = .available(version)
                if state.autoUpdate && !userInitiated { self.install(silent: true) }
            }
        }.resume()
    }

    /// `silent`: relaunch without opening the window (background auto-update).
    func install(silent: Bool = false) {
        guard let url = latestAsset else { return }
        let state = AppState.shared
        state.update = .installing
        Task {
            do {
                try await Self.download(url, silent: silent)
            } catch {
                await MainActor.run { state.update = .failed(error.localizedDescription) }
            }
        }
    }

    private static func download(_ url: URL, silent: Bool) async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("CornerSwitchUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (file, _) = try await URLSession.shared.download(from: url)
        let zip = tmp.appendingPathComponent("CornerSwitch.zip")
        try fm.moveItem(at: file, to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        let newApp = tmp.appendingPathComponent("CornerSwitch.app")
        try verifySameSigner(newApp)

        let dest = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            throw msg("Can't write to \(dest.deletingLastPathComponent().path). Move the app to ~/Applications.")
        }
        // Wait for this process to quit, swap the bundle (restoring the old one if the copy fails), relaunch.
        let script = """
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        if mv "$DEST" "$DEST.old"; then
          if /usr/bin/ditto "$NEW" "$DEST"; then rm -rf "$DEST.old"; else rm -rf "$DEST"; mv "$DEST.old" "$DEST"; fi
        fi
        if [ "$SILENT" = 1 ]; then /usr/bin/open "$DEST" --args -silentLaunch YES; else /usr/bin/open "$DEST"; fi
        rm -rf "$TMP"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.environment = [
            "PID": String(ProcessInfo.processInfo.processIdentifier),
            "DEST": dest.path, "NEW": newApp.path, "TMP": tmp.path, "SILENT": silent ? "1" : "0",
        ]
        try p.run()
        await MainActor.run { NSApp.terminate(nil) }
    }

    /// The download must satisfy this app's own designated requirement (same bundle ID, same certificate).
    private static func verifySameSigner(_ app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var req: SecRequirement?
        var newCode: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &req) == errSecSuccess, let req,
              SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            throw msg("Couldn't read code signatures")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(newCode, flags, req) == errSecSuccess else {
            throw msg("Update isn't signed by the same certificate. Skipped.")
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw msg("\(tool) failed") }
    }

    private static func msg(_ s: String) -> NSError {
        NSError(domain: "CornerSwitch", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }
}
