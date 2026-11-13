// Draws the 1024px app icon: two displays with a cursor crossing between them.
// Usage: swift tools/make-icon.swift Resources/AppIcon.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r/255, green: g/255, blue: b/255, alpha: a) }

// Body: macOS icon grid (824pt squircle-ish rounded rect, 100pt margin).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(0, 0, 0, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(60, 40, 160)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(126, 106, 255), rgb(74, 52, 214), rgb(38, 24, 120)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
// Soft top glow.
let glow = CGGradient(colorsSpace: space, colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 980), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 980), endRadius: 620, options: [])
ctx.restoreGState()

// Displays.
func display(x: CGFloat, dim: Bool) {
    let frame = CGRect(x: x, y: 450, width: 300, height: 214)
    let framePath = CGPath(roundedRect: frame, cornerWidth: 30, cornerHeight: 30, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(10, 0, 50, 0.35))
    ctx.addPath(framePath); ctx.setFillColor(rgb(255, 255, 255, dim ? 0.82 : 1)); ctx.fillPath()
    ctx.restoreGState()
    let screen = frame.insetBy(dx: 18, dy: 18)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: 14, cornerHeight: 14, transform: nil)); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: (dim ? [rgb(150, 140, 230), rgb(110, 96, 210)] : [rgb(178, 166, 255), rgb(120, 100, 245)]) as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: screen.midX, y: screen.maxY), end: CGPoint(x: screen.midX, y: screen.minY), options: [])
    ctx.restoreGState()
    // Stand.
    ctx.setFillColor(rgb(255, 255, 255, dim ? 0.82 : 1))
    ctx.fill(CGRect(x: frame.midX - 22, y: 392, width: 44, height: 60))
    ctx.addPath(CGPath(roundedRect: CGRect(x: frame.midX - 74, y: 370, width: 148, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil))
    ctx.fillPath()
}
display(x: 152, dim: false)
display(x: 572, dim: true)

// Motion trail.
ctx.setLineCap(.round)
for (i, y) in [628.0, 586.0, 544.0].enumerated() {
    ctx.setStrokeColor(rgb(255, 255, 255, 0.85 - Double(i) * 0.2))
    ctx.setLineWidth(18)
    ctx.move(to: CGPoint(x: 556 + CGFloat(i) * 14, y: y)); ctx.addLine(to: CGPoint(x: 640 + CGFloat(i) * 10, y: y))
    ctx.strokePath()
}

// Cursor, tip pointing up-left, crossing into the left display.
let u: CGFloat = 12.5
let tip = CGPoint(x: 432, y: 704)
let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13), (7, 20), (9.2, 19), (6.4, 12.2), (11.5, 12.2)]
let cursor = CGMutablePath()
cursor.addLines(between: pts.map { CGPoint(x: tip.x + $0.0 * u, y: tip.y - $0.1 * u) })
cursor.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: rgb(10, 0, 40, 0.5))
ctx.addPath(cursor); ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(cursor)
ctx.setStrokeColor(rgb(30, 18, 90)); ctx.setLineWidth(14); ctx.setLineJoin(.round)
ctx.strokePath()
ctx.addPath(cursor); ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
