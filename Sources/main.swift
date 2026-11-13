// CornerSwitch: push the cursor against the edge where your other Mac sits and the
// Logitech keyboard and mouse jump to it. Switching uses Bluetooth HID++ only, no network.

import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hid = HIDPP()
    let watcher = EdgeWatcher()
    let updater = Updater()
    let state = AppState.shared
    var statusItem: NSStatusItem!
    let popover = NSPopover()

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let symbol = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "CornerSwitch")
            ?? NSImage(systemSymbolName: "display.2", accessibilityDescription: "CornerSwitch")
        statusItem.button?.image = symbol
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PopoverView(state: state, actions: Actions(
            switchNow: { [weak self] in self?.switchNow(from: nil, screen: nil) },
            openPrivacy: {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
            },
            refresh: { [weak self] in self?.refresh() },
            setLaunchAtLogin: { [weak self] in self?.setLaunchAtLogin($0) },
            checkUpdates: { [weak self] in self?.updater.check(userInitiated: true) },
            installUpdate: { [weak self] in self?.updater.install() },
            quit: { NSApp.terminate(nil) })))

        hid.log = { NSLog("CornerSwitch: %@", $0) }
        hid.onChange = { [weak self] in self?.syncDevices() }
        hid.start()

        watcher.onTrigger = { [weak self] p, f in self?.switchNow(from: p, screen: f) }
        watcher.start()
        updater.start()
        syncDevices()
    }

    @objc func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        state.hasPermission = hid.hasPermission
        state.launchAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
        popover.show(relativeTo: statusItem.button!.bounds, of: statusItem.button!, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func refresh() { hid.devices.forEach { hid.probe($0) } }

    func syncDevices() {
        state.devices = hid.devices.map { DeviceInfo(name: $0.name, isKeyboard: $0.isKeyboard, channel: $0.currentHost.map { $0 + 1 }) }
        state.hasPermission = hid.hasPermission
        statusItem.button?.appearsDisabled = !state.enabled || hid.devices.isEmpty
    }

    /// Parks the cursor just inside the edge it left from (so coming back feels natural
    /// and doesn't bounce straight back), then sends both devices to the target channel.
    func switchNow(from p: NSPoint?, screen f: NSRect?) {
        guard !hid.devices.isEmpty else { NSSound.beep(); return }
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
