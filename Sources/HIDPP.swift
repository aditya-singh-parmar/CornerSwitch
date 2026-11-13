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

    private func added(_ dev: IOHIDDevice) {
        let name = IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String ?? "Logitech device"
        let pairs = IOHIDDeviceGetProperty(dev, kIOHIDDeviceUsagePairsKey as CFString) as? [[String: Int]] ?? []
        let isKeyboard = pairs.contains { $0[kIOHIDDeviceUsagePageKey] == 1 && $0[kIOHIDDeviceUsageKey] == 6 }
        let d = LogiDevice(ref: dev, name: name, isKeyboard: isKeyboard)
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
        onChange?()
    }

    private func input(sender: UnsafeMutableRawPointer?, reportID: UInt32, report: UnsafeMutablePointer<UInt8>, len: CFIndex) {
        guard let d = devices.first(where: { $0.opaque == sender }) else { return }
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
            self.send(d, feature: idx, fn: 0) { info in
                if let info, info.count >= 2 {
                    d.hostCount = Int(info[0])
                    d.currentHost = Int(info[1])
                }
                self.onChange?()
                then?()
            }
        }
    }

    /// Moves every connected device to `host` (0-based). Keyboard first, then mouse.
    func switchAll(to host: Int) {
        let ordered = devices.sorted { $0.isKeyboard && !$1.isKeyboard }
        for (n, d) in ordered.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(40 * n)) { [weak self] in
                guard let self else { return }
                let go = { (idx: UInt8) in
                    self.send(d, feature: idx, fn: 1, params: [UInt8(host)], expectReply: false) { _ in }
                    self.log("\(d.name) -> channel \(host + 1)")
                }
                if let idx = d.changeHostIndex { go(idx) } else {
                    self.probe(d) { if let idx = d.changeHostIndex { go(idx) } }
                }
            }
        }
    }

    /// This Mac's channel (0-based) as reported by the devices.
    var thisHost: Int? { devices.compactMap(\.currentHost).first }
}
