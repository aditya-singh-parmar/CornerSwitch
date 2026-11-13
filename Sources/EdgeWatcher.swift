// Detects the cursor being pushed against the edge where the other Mac sits.
// Mouse events keep reporting movement deltas even when the cursor is pinned
// at the edge, so "pushing through" can be measured.

import AppKit

final class EdgeWatcher {
    /// Called with the cursor position and the screen frame it pushed out of (Cocoa coordinates).
    var onTrigger: ((NSPoint, NSRect) -> Void)?
    private var monitors: [Any] = []
    private var push: CGFloat = 0
    private var lastPush = Date.distantPast
    private var cooldownUntil = Date.distantPast
    /// When the cursor arrived at the edge. Pushes only count after it has rested there
    /// briefly, so flicking into the edge (to reach the Dock, a scrollbar…) never switches.
    private var arrivedAt: Date?
    private let settle: TimeInterval = 0.08
    private var suppressedUntil = Date.distantPast

    /// Ignore the edge for a moment (used right after the devices arrive).
    func suppress(for seconds: TimeInterval) {
        suppressedUntil = Date().addingTimeInterval(seconds)
        push = 0
        arrivedAt = nil
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
        let s = AppState.shared
        guard s.enabled, NSEvent.pressedMouseButtons == 0, Date() >= suppressedUntil else { push = 0; return }
        let p = NSEvent.mouseLocation
        guard let frame = edgeScreen(p, s.side) else { push = 0; arrivedAt = nil; return }
        let now = Date()
        if arrivedAt == nil { arrivedAt = now }
        guard now.timeIntervalSince(arrivedAt!) >= settle else { return }
        let outward: CGFloat
        switch s.side {
        case .left: outward = -e.deltaX
        case .right: outward = e.deltaX
        case .top: outward = -e.deltaY      // NSEvent deltaY is positive downward
        case .bottom: outward = e.deltaY
        }
        guard outward > 0 else { return }
        if now.timeIntervalSince(lastPush) > 0.35 { push = 0 }
        lastPush = now
        push += outward
        if push >= CGFloat(s.resistance.rawValue), now >= cooldownUntil {
            push = 0
            cooldownUntil = now.addingTimeInterval(2)
            onTrigger?(p, frame)
        }
    }

    /// The frame of the screen whose outer `side` edge the cursor is on, if any.
    private func edgeScreen(_ p: NSPoint, _ side: Side) -> NSRect? {
        let frames = NSScreen.screens.map(\.frame)
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
