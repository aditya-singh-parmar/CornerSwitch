// Draws the 1024px app icon, flat: two displays with a pointer crossing between them.
// Usage: swift tools/make-icon.swift Resources/AppIcon.png
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let S = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: S, pixelsHigh: S, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r/255, green: g/255, blue: b/255, alpha: a) }
let brand = rgb(97, 79, 237)
let ink = rgb(40, 28, 120)

// Body on the macOS icon grid (824pt, 100pt margin).
ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil))
ctx.setFillColor(brand)
ctx.fillPath()

func display(x: CGFloat, filled: Bool) {
    let frame = CGRect(x: x, y: 452, width: 290, height: 206)
    let white = rgb(255, 255, 255, filled ? 1 : 0.55)
    ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 12, dy: 12), cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setStrokeColor(white); ctx.setLineWidth(24); ctx.strokePath()
    if filled {
        ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 40, dy: 40), cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setFillColor(rgb(255, 255, 255, 0.22)); ctx.fillPath()
    }
    ctx.setFillColor(white)
    ctx.fill(CGRect(x: frame.midX - 18, y: 398, width: 36, height: 56))
    ctx.addPath(CGPath(roundedRect: CGRect(x: frame.midX - 70, y: 378, width: 140, height: 26), cornerWidth: 13, cornerHeight: 13, transform: nil))
    ctx.fillPath()
}
display(x: 164, filled: true)
display(x: 570, filled: false)

// Pointer, tip up-left, crossing into the left display.
let u: CGFloat = 12
let tip = CGPoint(x: 446, y: 690)
let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13), (7, 20), (9.2, 19), (6.4, 12.2), (11.5, 12.2)]
let cursor = CGMutablePath()
cursor.addLines(between: pts.map { CGPoint(x: tip.x + $0.0 * u, y: tip.y - $0.1 * u) })
cursor.closeSubpath()
ctx.addPath(cursor)
ctx.setStrokeColor(ink); ctx.setLineWidth(22); ctx.setLineJoin(.round)
ctx.strokePath()
ctx.addPath(cursor); ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
