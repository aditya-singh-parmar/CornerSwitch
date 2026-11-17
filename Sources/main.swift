// CornerSwitch: push the cursor past the edge where your other Mac sits and the
// Logitech keyboard and mouse jump to it. Switching uses Bluetooth HID++ only, no network.

import AppKit
import SwiftUI
import ServiceManagement
import UserNotifications
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let hid = HIDPP()
    let hud = SwitchHUD()
    let launchedAt = Date()
    var lastArrival: Date?
    /// When this app last sent a switch, to tell our own switches from manual ones.
    var lastSwitchAt: Date?
    let watcher = EdgeWatcher()
    let updater = Updater()
    let state = AppState.shared
    var statusItem: NSStatusItem!
    var window: NSWindow?
    var quietLaunch = false
    private var enabledSub: AnyCancellable?

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
        hid.onRemoved = { [weak self] d in self?.deviceLeft(d) }
        hid.start()

        watcher.onTrigger = { [weak self] p, f in self?.switchNow(from: p, screen: f) }
        watcher.pauseReason = { [weak self] in
            guard let self, self.state.autoPause else { return nil }
            return Pause.reason()
        }
        // Battery every 10 minutes while the devices are here. The wide tolerance lets macOS
        // batch the wake-up with others instead of waking the CPU just for this.
        let battery = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.hid.devices.forEach { self?.hid.readBattery($0) }
        }
        battery.tolerance = 120
        watcher.start()
        enabledSub = state.$enabled.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateWatcher() }
        }
        updater.start()
        syncDevices()
        state.launchAtLogin = SMAppService.mainApp.status == .enabled

        let firstRun = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if firstRun || !quietLaunch || !hid.hasPermission || UserDefaults.standard.bool(forKey: "previewWindow") { showWindow() }
        if !hid.hasPermission { watchForPermission() }
        // Hidden: `-previewHUD YES` shows the switch hint without switching (for design checks).
        if UserDefaults.standard.bool(forKey: "previewHUD"), let f = NSScreen.main?.frame {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.hud.showDeparture(to: self.state.otherDisplayName, side: self.state.side,
                                       at: NSPoint(x: f.minX, y: f.midY), screen: f, hold: 8)
            }
        }
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
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.title = "CornerSwitch"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.isReleasedWhenClosed = false
            w.delegate = self
            window = w
        }
        // Hidden design-check mode: show the window without taking focus from the user.
        if UserDefaults.standard.bool(forKey: "previewWindow"), let w = window {
            if UserDefaults.standard.bool(forKey: "previewDark") { w.appearance = NSAppearance(named: .darkAqua) }
            w.layoutIfNeeded()
            placeOnScreen(w)
            w.orderFrontRegardless()
            return
        }
        // Show in the Dock and Cmd-Tab while the window is open, like a normal app.
        NSApp.setActivationPolicy(.regular)
        if let w = window {
            w.layoutIfNeeded()
            if !w.isVisible { placeOnScreen(w) }
            w.makeKeyAndOrderFront(nil)
            // Don't hand keyboard focus to the name field on open; typing should only land there after a click.
            DispatchQueue.main.async { w.makeFirstResponder(nil) }
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
        for d in hid.devices.sorted(by: { $0.isKeyboard && !$1.isKeyboard }) {
            let b = d.battery.map { " · \($0)%\(d.charging ? " charging" : "")" } ?? ""
            let item = NSMenuItem(title: "\(prettyName(d.name))\(b)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let on = NSMenuItem(title: "CornerSwitch On", action: #selector(toggleEnabled), keyEquivalent: "")
        on.state = state.enabled ? .on : .off
        on.target = self
        menu.addItem(on)
        let sw = NSMenuItem(title: "Switch to \(state.otherDisplayName)", action: hid.devices.isEmpty ? nil : #selector(menuSwitch), keyEquivalent: "")
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
        // Keyboard and mouse just arrived from the other Mac: ring the pointer so it's easy to find.
        if state.devices.isEmpty, !hid.devices.isEmpty {
            lastArrival = Date()
            // Hand still moving from the other Mac: don't let that bounce the devices straight back.
            watcher.suppress(for: 0.8)
            if Date().timeIntervalSince(launchedAt) > 5 { hud.showArrival(at: NSEvent.mouseLocation) }
        }
        state.devices = hid.devices.map {
            DeviceInfo(name: $0.name, isKeyboard: $0.isKeyboard, channel: $0.currentHost.map { $0 + 1 },
                       battery: $0.battery, charging: $0.charging)
        }
        for d in hid.devices {
            if let b = d.battery, state.batteries[d.name] != b { state.batteries[d.name] = b }
            checkLowBattery(d)
        }
        state.hasPermission = hid.hasPermission
        statusItem.button?.appearsDisabled = !state.enabled || hid.devices.isEmpty
        updateWatcher()
    }

    /// The pointer is only watched while a switch could go out from this Mac.
    private func updateWatcher() {
        watcher.active = state.enabled && (!hid.devices.isEmpty || UserDefaults.standard.bool(forKey: "dryRun"))
    }

    /// One notification per discharge: at 15% or below, re-armed once it's back above 30%.
    private func checkLowBattery(_ d: LogiDevice) {
        guard let b = d.battery else { return }
        let key = "lowBatteryNotified.\(d.name)"
        let ud = UserDefaults.standard
        if b >= 30 || d.charging { ud.removeObject(forKey: key); return }
        guard state.batteryAlerts, b <= 15, !ud.bool(forKey: key) else { return }
        ud.set(true, forKey: key)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
            guard ok else { return }
            let c = UNMutableNotificationContent()
            c.title = "\(prettyName(d.name)) battery is low"
            c.body = "\(b)% left. Charge it soon."
            c.sound = .default
            center.add(UNNotificationRequest(identifier: key, content: c, trigger: nil))
        }
        clog("low battery alert: \(d.name) \(b)%")
    }

    /// A device left this Mac without CornerSwitch sending it: someone pressed its
    /// Easy-Switch button. If it was in use just before, send the other device along too.
    /// (A device that drops off after sitting idle has gone to sleep, so nothing follows.)
    private func deviceLeft(_ d: LogiDevice) {
        guard state.enabled, state.followAlong else { return }
        if let s = lastSwitchAt, Date().timeIntervalSince(s) < 5 { return }
        // The keyboard's own keys never reach this app (macOS keeps them), and the Easy-Switch
        // key is handled in the keyboard itself, so for the keyboard "in use" means the user
        // touched any input on this Mac a moment ago (usually the mouse, just before reaching
        // over to the key). Asked once here, so nothing is watched in between.
        let own = ProcessInfo.processInfo.systemUptime - d.lastActivity
        let anyInput = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let idle = d.isKeyboard ? min(own, anyInput) : own
        guard idle < 4 else { clog(String(format: "%@ left after %.0fs idle (sleep?), not following", d.name, min(idle, 99999))); return }
        let rest = hid.devices.filter { $0 !== d }
        guard !rest.isEmpty else { return }
        clog("\(d.name) was switched by hand, sending the rest along")
        lastSwitchAt = Date()
        let fixed = state.targetChannel
        let fallback = state.target - 1
        hid.switchAll { dev in
            guard rest.contains(where: { $0 === dev }) else { return dev.currentHost ?? fallback }
            if fixed > 0 { return fixed - 1 }
            guard let cur = dev.currentHost else { return fallback }
            return cur == 1 ? 0 : 1
        }
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
        lastSwitchAt = Date()
        // The pointer stays where it is: no jump back from the edge.
        if let p, let f { hud.showDeparture(to: state.otherDisplayName, side: state.side, at: p, screen: f) }
        sendWhenReady(deadline: Date().addingTimeInterval(2.5))
    }

    /// If the keyboard or mouse is still reconnecting to this Mac (it arrived moments ago),
    /// wait for it so nothing is left behind, then send every device across together.
    private func sendWhenReady(deadline: Date) {
        let expected = Set([state.keyboardName, state.mouseName].compactMap { $0 })
        let present = Set(hid.devices.map(\.name))
        let arrivingRecently = lastArrival.map { Date().timeIntervalSince($0) < 8 } ?? false
        if arrivingRecently, !expected.isSubset(of: present), Date() < deadline {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
                self?.sendWhenReady(deadline: deadline)
            }
            return
        }
        let fixed = state.targetChannel
        let fallback = state.target - 1
        for d in hid.devices {
            clog("  \(d.name): on channel \(d.currentHost.map { String($0 + 1) } ?? "?"), changeHost \(d.changeHostIndex.map { String($0) } ?? "unknown")")
        }
        // Automatic works per device: each goes to "the other one" of its own channels 1 and 2.
        hid.switchAll { d in
            if fixed > 0 { return fixed - 1 }
            guard let cur = d.currentHost else { return fallback }
            return cur == 1 ? 0 : 1
        }
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
