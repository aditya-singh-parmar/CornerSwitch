// HID++ 2.0 over Bluetooth: finds the Logitech devices and sends them the
// CHANGE_HOST (0x1814) command, the same thing the Easy-Switch button does.

import Foundation
import IOKit.hid

let kLogitechVendor = 0x046D
let kSoftwareID: UInt8 = 0x0B
let kReportLong: UInt8 = 0x11
let kDeviceIndexBT: UInt8 = 0xFF

final class LogiDevice {
    let ref: IOHIDDevice
    let name: String
    let isKeyboard: Bool
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    var changeHostIndex: UInt8?
    var hostCount: Int?
    var currentHost: Int?   // 0-based
    /// UNIFIED_BATTERY (0x1004) feature index and last reading.
    var batteryIndex: UInt8?
    var battery: Int?
    var charging = false
    /// Last time the device sent ordinary input (a keypress or mouse movement).
    var lastActivity = Date.distantPast
    var pending: [Pending] = []

    struct Pending {
        let id: UUID
        let feature: UInt8
        let fnByte: UInt8
        let done: ([UInt8]?) -> Void
    }

    init(ref: IOHIDDevice, name: String, isKeyboard: Bool) {
        self.ref = ref
        self.name = name
        self.isKeyboard = isKeyboard
    }

    var opaque: UnsafeMutableRawPointer { Unmanaged.passUnretained(ref).toOpaque() }
}

final class HIDPP {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    private(set) var devices: [LogiDevice] = []
    private(set) var openResult: IOReturn = kIOReturnSuccess
    var onChange: (() -> Void)?
    /// A device dropped off this Mac (switched away, slept, or turned off).
    var onRemoved: ((LogiDevice) -> Void)?
    var log: (String) -> Void = { _ in }

    func start() {
        let match: [String: Any] = [
            kIOHIDVendorIDKey: kLogitechVendor,
            kIOHIDDeviceUsagePageKey: 0xFF43,
            kIOHIDDeviceUsageKey: 0x0202,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDPP>.fromOpaque(ctx!).takeUnretainedValue().added(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, dev in
            Unmanaged<HIDPP>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Keyboards are behind Input Monitoring. This prompts once and lists the app in System Settings.
        if !hasPermission { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            log(String(format: "IOHIDManagerOpen failed: 0x%08x (grant Input Monitoring)", openResult))
        }
    }

    var hasPermission: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }

    /// Called once Input Monitoring is granted, so the user doesn't have to restart the app.
    func reopen() {
        openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        for d in devices {
            let r = IOHIDDeviceOpen(d.ref, IOOptionBits(kIOHIDOptionsTypeNone))
            log(String(format: "reopen %@: 0x%08x", d.name, r))
            probe(d)
        }
        onChange?()
    }

    private func added(_ dev: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "Logitech device"
        let pairs = IOHIDDeviceGetProperty(dev, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        let isKeyboard = pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 1 && $0[kIOHIDDeviceUsageKey] == 6 }
        let d = LogiDevice(ref: dev, name: name, isKeyboard: isKeyboard)
        // Remembered from earlier probes, so a switch right after reconnecting goes out instantly.
        let ud = UserDefaults.standard
        if let idx = ud.object(forKey: "chIdx.\(name)") as? Int { d.changeHostIndex = UInt8(idx) }
        if let host = ud.object(forKey: "host.\(name)") as? Int { d.currentHost = host }
        // Open per device, so one refused device doesn't block the other.
        let r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if r != kIOReturnSuccess { log(String(format: "open %@: 0x%08x", name, r)) }
        devices.removeAll { $0.ref == dev }
        devices.append(d)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, d.buffer, 64, { ctx, _, sender, _, reportID, report, len in
            Unmanaged<HIDPP>.fromOpaque(ctx!).takeUnretainedValue()
                .input(sender: sender, reportID: reportID, report: report, len: len)
        }, ctx)
        log("connected: \(name)")
        probe(d)
        onChange?()
    }

    private func removed(_ dev: IOHIDDevice) {
        guard let i = devices.firstIndex(where: { $0.ref == dev }) else { return }
        let d = devices.remove(at: i)
        d.pending.forEach { $0.done(nil) }
        d.pending.removeAll()
        log("disconnected: \(d.name)")
        onRemoved?(d)
        onChange?()
    }

    private func input(sender: UnsafeMutableRawPointer?, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, len: CFIndex) {
        guard let d = devices.first(where: { $0.opaque == sender }) else { return }
        // Ordinary input (keys, movement) uses other report IDs than HID++ (0x10/0x11).
        let first = len > 0 ? report[0] : 0
        let isHIDPP = reportID == 0x10 || reportID == UInt32(kReportLong) || first == 0x10 || first == kReportLong
        if !isHIDPP { d.lastActivity = Date(); return }
        var r = Array(UnsafeBufferPointer(start: report, count: len))
        if r.first != kReportLong {
            guard reportID == UInt32(kReportLong) else { return }
            r.insert(kReportLong, at: 0)
        }
        guard r.count >= 5 else { return }
        let isError = r[2] == 0xFF
        let feature = isError ? r[3] : r[2]
        let fnByte = isError ? r[4] : r[3]
        guard let i = d.pending.firstIndex(where: { $0.feature == feature && $0.fnByte == fnByte }) else { return }
        let p = d.pending.remove(at: i)
        p.done(isError ? nil : Array(r[4...]))
    }

    /// Sends a HID++ 2.0 long report. `done` gets the response params, or nil on error/timeout.
    func send(_ d: LogiDevice, feature: UInt8, fn: UInt8, params: [UInt8] = [],
              expectReply: Bool = true, done: @escaping ([UInt8]?) -> Void) {
        var buf = [UInt8](repeating: 0, count: 20)
        buf[0] = kReportLong
        buf[1] = kDeviceIndexBT
        buf[2] = feature
        buf[3] = (fn << 4) | kSoftwareID
        for (i, p) in params.prefix(16).enumerated() { buf[4 + i] = p }
        let r = IOHIDDeviceSetReport(d.ref, kIOHIDReportTypeOutput, CFIndex(kReportLong), buf, buf.count)
        guard r == kIOReturnSuccess else {
            log(String(format: "write to %@ failed: 0x%08x", d.name, r))
            done(nil)
            return
        }
        guard expectReply else { done([]); return }
        let id = UUID()
        d.pending.append(.init(id: id, feature: feature, fnByte: buf[3], done: done))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let i = d.pending.firstIndex(where: { $0.id == id }) {
                d.pending.remove(at: i).done(nil)
            }
        }
    }

    /// Finds the CHANGE_HOST feature index and reads the host count and current host.
    func probe(_ d: LogiDevice, then: (() -> Void)? = nil) {
        send(d, feature: 0x00, fn: 0, params: [0x18, 0x14]) { [weak self] resp in
            guard let self, let idx = resp?.first, idx != 0 else {
                self?.log("\(d.name): CHANGE_HOST not found")
                then?()
                return
            }
            d.changeHostIndex = idx
            UserDefaults.standard.set(Int(idx), forKey: "chIdx.\(d.name)")
            self.send(d, feature: idx, fn: 0) { info in
                if let info, info.count >= 2 {
                    d.hostCount = Int(info[0])
                    d.currentHost = Int(info[1])
                    UserDefaults.standard.set(Int(info[1]), forKey: "host.\(d.name)")
                }
                self.onChange?()
                self.findBattery(d)
                then?()
            }
        }
    }

    /// Looks up UNIFIED_BATTERY (0x1004) once, then reads it.
    func findBattery(_ d: LogiDevice) {
        if d.batteryIndex != nil { readBattery(d); return }
        send(d, feature: 0x00, fn: 0, params: [0x10, 0x04]) { [weak self] resp in
            guard let self, let idx = resp?.first, idx != 0 else { return }
            d.batteryIndex = idx
            self.readBattery(d)
        }
    }

    /// get_status: [state of charge %, level bits, charging status, external power].
    func readBattery(_ d: LogiDevice) {
        guard let idx = d.batteryIndex else { return }
        send(d, feature: idx, fn: 1) { [weak self] r in
            guard let self, let r, r.count >= 3 else { return }
            var pct = Int(r[0])
            if pct == 0 {   // device reports levels only
                pct = r[1] & 8 != 0 ? 100 : r[1] & 4 != 0 ? 60 : r[1] & 2 != 0 ? 20 : r[1] & 1 != 0 ? 5 : 0
            }
            d.battery = pct
            d.charging = r[2] == 1 || r[2] == 2 || r[2] == 3
            self.onChange?()
        }
    }

    /// Moves every connected device at once. `host(d)` gives each device's target channel
    /// (0-based), since a keyboard and a mouse can be paired to the Macs on different keys.
    /// A failed write is retried once after reopening the device.
    func switchAll(_ host: @escaping (LogiDevice) -> Int) {
        for d in devices {
            let target = host(d)
            let go = { [weak self] (idx: UInt8) in
                guard let self else { return }
                // A device that accepted the command drops off this Mac within a moment. One that
                // just reconnected can silently ignore it, so resend until it leaves (max 3 tries).
                func confirm(_ attempt: Int) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(900)) {
                        guard self.devices.contains(where: { $0 === d }) else {
                            self.log("\(d.name): left this Mac"); return
                        }
                        guard attempt < 3 else { self.log("\(d.name): still here after 3 tries"); return }
                        self.log("\(d.name): still here, resending (try \(attempt + 1))")
                        self.send(d, feature: idx, fn: 1, params: [UInt8(target)], expectReply: false) { _ in
                            confirm(attempt + 1)
                        }
                    }
                }
                self.send(d, feature: idx, fn: 1, params: [UInt8(target)], expectReply: false) { ok in
                    if ok != nil { self.log("\(d.name): sent to channel \(target + 1)"); confirm(1); return }
                    self.log("\(d.name): send failed, retrying")
                    _ = IOHIDDeviceOpen(d.ref, IOOptionBits(kIOHIDOptionsTypeNone))
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80)) {
                        self.send(d, feature: idx, fn: 1, params: [UInt8(target)], expectReply: false) { ok2 in
                            self.log("\(d.name): retry \(ok2 != nil ? "sent" : "failed")")
                        }
                    }
                }
            }
            if let idx = d.changeHostIndex { go(idx) } else {
                log("\(d.name): not probed yet, probing before switch")
                probe(d) { if let idx = d.changeHostIndex { go(idx) } else { self.log("\(d.name): can't switch, no CHANGE_HOST") } }
            }
        }
    }

    /// Back-compat for the CLI: every device to the same channel.
    func switchAll(to host: Int) { switchAll { _ in host } }

    /// This Mac's channel (0-based) as reported by the devices.
    var thisHost: Int? { devices.compactMap(\.currentHost).first }
}
