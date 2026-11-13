// CornerSwitch: push the cursor past the edge where your other Mac sits and the
// Logitech keyboard and mouse jump to it. Switching uses Bluetooth HID++ only, no network.

import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let hid = HIDPP()
    let watcher = EdgeWatcher()
    let updater = Updater()
    let state = AppState.shared
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var quietLaunch = false

    func applicationWillFinishLaunching(_ note: Notification) {
        quietLaunch = launchedQuietly()
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        // Menu bar icon. On notched MacBooks macOS hides icons that don't fit, so the
        // window is also reachable from Spotlight, Launchpad and the Dock.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "CornerSwitch"
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "CornerSwitch")
            ?? NSImage(systemSymbolName: "display.2", accessibilityDescription: "CornerSwitch")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hid.log = { clog($0) }
        clog("launch v\(state.version), input monitoring: \(hid.hasPermission)")
        hid.onChange = { [weak self] in self?.syncDevices() }
        hid.start()

        watcher.onTrigger = { [weak self] p, f in self?.switchNow(from: p, screen: f) }
        watcher.start()
        updater.start()
        syncDevices()
        state.launchAtLogin = SMAppService.mainApp.status == .enabled

        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstRun || !quietLaunch || !hid.hasPermission { showWindow() }
        if !hid.hasPermission { watchForPermission() }
    }

    /// Polls until Input Monitoring is granted, then connects to the devices without a restart.
    private func watchForPermission() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard let self, self.hid.hasPermission else { return }
            t.invalidate()
            clog("input monitoring granted")
            self.hid.reopen()
            self.syncDevices()
        }
    }

    /// Opening the app again (Finder, Spotlight, Dock) brings up the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: Window

    @objc func showWindow() {
        state.hasPermission = hid.hasPermission
        state.launchAtLogin = SMAppService.mainApp.status == .enabled
        hid.devices.forEach { hid.probe($0) }
        if window == nil {
            let host = NSHostingController(rootView: MainView(state: state, actions: Actions(
                switchNow: { [weak self] in self?.switchNow(from: nil, screen: nil) },
                openPrivacy: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                },
                setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
                checkUpdates: { [weak self] in self?.updater.check(userInitiated: true) },
                installUpdate: { [weak self] in self?.updater.install() })))
            host.sizingOptions = [.preferredContentSize]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "CornerSwitch"
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        // Show in the Dock and Cmd-Tab while the window is open, like a normal app.
        NSApp.setActivationPolicy(.regular)
        if let w = window {
            w.layoutIfNeeded()
            if !w.isVisible { placeOnScreen(w) }
            w.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window inside the usable screen area (below the menu bar, above the Dock).
    private func placeOnScreen(_ w: NSWindow) {
        guard let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else { return }
        var f = w.frame
        f.size.height = min(f.height, vf.height)
        f.origin.x = vf.midX - f.width / 2
        f.origin.y = vf.midY - f.height / 2
        w.setFrame(f, display: false)
    }

    /// Keeps the window inside the usable area when its content grows (e.g. the permission banner).
    func windowDidResize(_ notification: Notification) {
        guard let w = notification.object as? NSWindow, let vf = w.screen?.visibleFrame else { return }
        var f = w.frame
        if f.minY < vf.minY { f.origin.y = vf.minY }
        if f.maxY > vf.maxY { f.origin.y = max(vf.minY, vf.maxY - f.height) }
        if f != w.frame { w.setFrame(f, display: true) }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: Menu bar

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: statusLine(state), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let on = NSMenuItem(title: "CornerSwitch On", action: #selector(toggleEnabled), keyEquivalent: "")
        on.state = state.enabled ? .on : .off
        on.target = self
        menu.addItem(on)
        let sw = NSMenuItem(title: "Switch to Other Mac", action: hid.devices.isEmpty ? nil : #selector(menuSwitch), keyEquivalent: "")
        sw.target = self
        menu.addItem(sw)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open CornerSwitch…", action: #selector(showWindow), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "Quit CornerSwitch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc func toggleEnabled() { state.enabled.toggle(); syncDevices() }
    @objc func menuSwitch() { switchNow(from: nil, screen: nil) }

    // MARK: Behaviour

    func syncDevices() {
        state.devices = hid.devices.map { DeviceInfo(name: $0.name, isKeyboard: $0.isKeyboard, channel: $0.currentHost.map { $0 + 1 }) }
        state.hasPermission = hid.hasPermission
        statusItem.button?.appearsDisabled = !state.enabled || hid.devices.isEmpty
    }

    /// Parks the cursor just inside the edge it left from (so coming back feels natural
    /// and doesn't bounce straight back), then sends both devices to the other Mac.
    func switchNow(from p: NSPoint?, screen f: NSRect?) {
        let via = p == nil ? "button" : "\(state.side.rawValue) edge"
        if UserDefaults.standard.bool(forKey: "dryRun") {
            clog("DRYRUN switch to channel \(state.target) via \(via), devices here: \(hid.devices.count)")
            return
        }
        // Only touch the pointer when a switch can actually go out.
        guard hid.hasPermission else { clog("switch via \(via) ignored: no Input Monitoring"); return }
        guard hid.devices.contains(where: { $0.changeHostIndex != nil }) else {
            clog("switch via \(via) ignored: no devices ready here"); return
        }
        clog("switch to channel \(state.target) via \(via)")
        let inset: CGFloat = 80
        var park: NSPoint
        if let p, let f {
            switch state.side {
            case .left: park = NSPoint(x: f.minX + inset, y: p.y)
            case .right: park = NSPoint(x: f.maxX - inset, y: p.y)
            case .top: park = NSPoint(x: p.x, y: f.maxY - inset)
            case .bottom: park = NSPoint(x: p.x, y: f.minY + inset)
            }
        } else {
            let m = NSScreen.main?.frame ?? .zero
            park = NSPoint(x: m.midX, y: m.midY)
        }
        // Cocoa (bottom-left origin) to Quartz (top-left origin of the primary display).
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        CGWarpMouseCursorPosition(CGPoint(x: park.x, y: primaryHeight - park.y))
        CGAssociateMouseAndMouseCursorPosition(1)
        hid.switchAll(to: state.target - 1)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("CornerSwitch: login item: %@", error.localizedDescription)
            NSSound.beep()
        }
        state.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// True when started at login or relaunched by the updater, so no window pops up.
    private func launchedQuietly() -> Bool {
        if UserDefaults.standard.bool(forKey: "silentLaunch") { return true }
        if let ev = NSAppleEventManager.shared().currentAppleEvent,
           ev.eventID == AEEventID(kAEOpenApplication),
           ev.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        // Fallback: the console session started within the last two minutes.
        var loginTime: Int = 0
        setutxent()
        while let e = getutxent() {
            let line = withUnsafeBytes(of: e.pointee.ut_line) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            if e.pointee.ut_type == USER_PROCESS, line == "console" {
                loginTime = max(loginTime, Int(e.pointee.ut_tv.tv_sec))
            }
        }
        endutxent()
        return loginTime > 0 && Int(Date().timeIntervalSince1970) - loginTime < 120
    }
}

// MARK: - CLI (diagnostics)

/// `CornerSwitch --probe` lists devices and their channel without switching.
/// `CornerSwitch --switch N` moves devices to channel N (1-based).
func runCLI(_ args: [String]) -> Never {
    let hid = HIDPP()
    hid.log = { print("  \($0)") }
    hid.start()
    RunLoop.main.run(until: Date().addingTimeInterval(2.5))
    if hid.devices.isEmpty { print("No HID++ Logitech devices found."); exit(1) }
    for d in hid.devices {
        let idx = d.changeHostIndex.map { String(format: "0x%02x", $0) } ?? "none"
        let cur = d.currentHost.map { "\($0 + 1)" } ?? "?"
        let cnt = d.hostCount.map(String.init) ?? "?"
        print("\(d.name)\(d.isKeyboard ? " [keyboard]" : ""): CHANGE_HOST idx \(idx), channel \(cur) of \(cnt)")
    }
    if args.first == "--switch", args.count > 1, let n = Int(args[1]), (1...3).contains(n) {
        hid.switchAll(to: n - 1)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }
    exit(0)
}

let cliArgs = Array(CommandLine.arguments.dropFirst())
if cliArgs.first == "--probe" || cliArgs.first == "--switch" { runCLI(cliArgs) }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
