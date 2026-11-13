// Small, quiet feedback around a switch:
// - a "← Office Mac" pill at the edge you left from, shown the instant the switch fires,
//   so the Bluetooth hand-over reads as intentional rather than lag;
// - a ring around the pointer when the keyboard and mouse arrive, so you spot it at once.

import AppKit
import SwiftUI

final class SwitchHUD {
    private var panel: NSPanel?

    func showDeparture(to name: String, side: Side, at p: NSPoint, screen f: NSRect, hold: TimeInterval = 1.3) {
        let view = NSHostingView(rootView: DeparturePill(name: name, side: side))
        let size = view.fittingSize
        let inset: CGFloat = 20
        var o: NSPoint
        switch side {
        case .left: o = NSPoint(x: f.minX + inset, y: p.y - size.height / 2)
        case .right: o = NSPoint(x: f.maxX - inset - size.width, y: p.y - size.height / 2)
        case .top: o = NSPoint(x: p.x - size.width / 2, y: f.maxY - inset - size.height - 24)
        case .bottom: o = NSPoint(x: p.x - size.width / 2, y: f.minY + inset)
        }
        o.x = min(max(o.x, f.minX + 8), f.maxX - size.width - 8)
        o.y = min(max(o.y, f.minY + 8), f.maxY - size.height - 30)
        present(view, frame: NSRect(origin: o, size: size), hold: hold)
    }

    func showArrival(at p: NSPoint) {
        let d: CGFloat = 96
        let view = RingView(frame: NSRect(x: 0, y: 0, width: d, height: d))
        present(view, frame: NSRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d), hold: 0.7)
    }

    private func present(_ view: NSView, frame: NSRect, hold: TimeInterval) {
        panel?.orderOut(nil)
        let w = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.contentView = view
        w.alphaValue = 0
        w.orderFrontRegardless()
        panel = w
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; w.animator().alphaValue = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak w] in
            guard let w else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
        }
    }
}

private struct DeparturePill: View {
    let name: String
    let side: Side

    var body: some View {
        let arrow = Image(systemName: {
            switch side {
            case .left: "arrow.left"
            case .right: "arrow.right"
            case .top: "arrow.up"
            case .bottom: "arrow.down"
            }
        }()).font(.system(size: 12, weight: .semibold)).foregroundStyle(brand)
        HStack(spacing: 7) {
            if side == .right { Text(name); arrow } else { arrow; Text(name) }
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .padding(10)
        .fixedSize()
    }
}

/// Ring that expands and fades around the pointer (Core Animation, no SwiftUI state needed).
private final class RingView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let ring = CAShapeLayer()
        let r = bounds.insetBy(dx: 6, dy: 6)
        ring.frame = bounds
        ring.path = CGPath(ellipseIn: r, transform: nil)
        ring.fillColor = nil
        ring.strokeColor = NSColor(brand).cgColor
        ring.lineWidth = 3
        layer?.addSublayer(ring)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.3
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let g = CAAnimationGroup()
        g.animations = [scale, fade]
        g.duration = 0.6
        g.timingFunction = CAMediaTimingFunction(name: .easeOut)
        g.fillMode = .forwards
        g.isRemovedOnCompletion = false
        ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ring.position = CGPoint(x: bounds.midX, y: bounds.midY)
        ring.bounds = bounds
        ring.add(g, forKey: "ring")
    }
    required init?(coder: NSCoder) { nil }
}
