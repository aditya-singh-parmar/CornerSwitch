// Detects the cursor being pushed against the edge where the other Mac sits.
// Mouse events keep reporting movement deltas even when the cursor is pinned
// at the edge, so "pushing through" can be measured.
//
// Intent, like Flow: a quick, straight move into the edge switches almost on contact;
// a slow drift needs a short rest and a proper push; sliding along the edge never counts.

import AppKit

final class EdgeWatcher {
    /// Called with the cursor position and the screen frame it pushed out of (Cocoa coordinates).
    var onTrigger: ((NSPoint, NSRect) -> Void)?
    private var monitors: [Any] = []

    private var push: CGFloat = 0
    /// Sideways movement during the current push; only a push that is mostly straight counts.
    private var pushAlong: CGFloat = 0
    private var lastPush: TimeInterval = 0
    private var cooldownUntil: TimeInterval = 0
    private var suppressedUntil: TimeInterval = 0
    private var arrivedAt: TimeInterval?
    private var fastArrival = false
    /// Smoothed speed toward the edge (pt/s) while approaching it.
    private var approach: CGFloat = 0
    private var lastTime: TimeInterval?
    /// For tuning: biggest push and approach speed seen during the current edge touch.
    private var touchMaxPush: CGFloat = 0
    private var touchApproach: CGFloat = 0
    private var touchSwitched = false

    /// Rest needed at the edge after a slow approach.
    private let settle: TimeInterval = 0.08
    /// Approach speed that counts as a deliberate move toward the other Mac.
    private let fastSpeed: CGFloat = 400

    /// Ignore the edge for a moment (used right after the devices arrive).
    func suppress(for seconds: TimeInterval) {
        suppressedUntil = ProcessInfo.processInfo.systemUptime + seconds
        reset()
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(m)
        }
    }

    private func handle(_ e: NSEvent) {
        process(location: NSEvent.mouseLocation, dx: e.deltaX, dy: e.deltaY, time: e.timestamp,
                buttonsDown: NSEvent.pressedMouseButtons != 0,
                controlDown: e.modifierFlags.contains(.control),
                frames: NSScreen.screens.map(\.frame))
    }

    private func reset() {
        push = 0
        pushAlong = 0
        arrivedAt = nil
        approach = 0
    }

    /// Core detection, separated from NSEvent so it can be tested with synthetic input.
    /// `dy` is positive downward (NSEvent convention); `time` is seconds since boot.
    func process(location p: NSPoint, dx: CGFloat, dy: CGFloat, time: TimeInterval,
                 buttonsDown: Bool, controlDown: Bool, frames: [NSRect]) {
        let s = AppState.shared
        let dt = min(max(time - (lastTime ?? time - 0.016), 0.001), 0.1)
        lastTime = time
        guard s.enabled, !buttonsDown, time >= suppressedUntil else { reset(); return }
        if s.requireControl && !controlDown { reset(); return }

        let outward: CGFloat, along: CGFloat
        switch s.side {
        case .left: outward = -dx; along = dy
        case .right: outward = dx; along = dy
        case .top: outward = -dy; along = dx
        case .bottom: outward = dy; along = dx
        }

        guard let frame = edgeScreen(p, s.side, frames) else {
            if arrivedAt != nil, !touchSwitched {
                clog(String(format: "edge touch, no switch: push %.0f of %d, approach %.0f pt/s",
                            touchMaxPush, s.resistance.rawValue, touchApproach))
            }
            // Still approaching: track how fast the pointer is heading for the edge.
            approach = approach * 0.5 + (outward / dt) * 0.5
            push = 0
            pushAlong = 0
            arrivedAt = nil
            return
        }
        if arrivedAt == nil {
            arrivedAt = time
            fastArrival = approach >= fastSpeed
            touchMaxPush = 0
            touchApproach = approach
            touchSwitched = false
        }
        let quick = fastArrival || s.requireControl
        guard time - arrivedAt! >= (quick ? 0 : settle) else { return }
        // Judge direction over the whole push, not per event, so normal hand wobble is fine.
        // Sliding along the edge (mostly sideways) never adds up to a switch.
        guard outward > 0 else { pushAlong += abs(along); return }
        if time - lastPush > 0.35 { push = 0; pushAlong = 0 }
        lastPush = time
        push += outward
        pushAlong += abs(along)
        touchMaxPush = max(touchMaxPush, push)
        guard push >= pushAlong * 0.6 else { return }

        var threshold = CGFloat(s.resistance.rawValue)
        if s.requireControl { threshold = 1 } else if fastArrival { threshold *= 0.35 }
        if push >= threshold, time >= cooldownUntil {
            push = 0
            cooldownUntil = time + 2
            touchSwitched = true
            clog(String(format: "edge switch: approach %.0f pt/s, %@, %.0f ms after touch",
                        touchApproach, fastArrival ? "quick" : "slow", (time - arrivedAt!) * 1000))
            onTrigger?(p, frame)
        }
    }

    /// The frame of the screen whose outer `side` edge the cursor is on, if any.
    private func edgeScreen(_ p: NSPoint, _ side: Side, _ frames: [NSRect]) -> NSRect? {
        for f in frames {
            guard p.x >= f.minX - 1, p.x <= f.maxX + 1, p.y >= f.minY - 1, p.y <= f.maxY + 1 else { continue }
            let atEdge: Bool
            let beyond: NSPoint
            switch side {
            case .left: atEdge = p.x <= f.minX + 1; beyond = NSPoint(x: f.minX - 3, y: p.y)
            case .right: atEdge = p.x >= f.maxX - 2; beyond = NSPoint(x: f.maxX + 3, y: p.y)
            case .top: atEdge = p.y >= f.maxY - 2; beyond = NSPoint(x: p.x, y: f.maxY + 3)
            case .bottom: atEdge = p.y <= f.minY + 1; beyond = NSPoint(x: p.x, y: f.minY - 3)
            }
            // Skip the outer 10% at each end of the edge: corners, the menu bar and Dock ends stay safe.
            let along: CGFloat = (side == .left || side == .right)
                ? (p.y - f.minY) / f.height : (p.x - f.minX) / f.width
            guard along >= 0.1, along <= 0.9 else { continue }
            // Only outer edges: if another display continues past this edge, the cursor just flows there.
            if atEdge, !frames.contains(where: { $0.contains(beyond) }) { return f }
        }
        return nil
    }
}
