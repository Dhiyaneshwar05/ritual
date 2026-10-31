// Draws the Ritual app icon: a marigold tile with an ink circle (a habit) and a cream
// rounded square (a task). Writes an .iconset folder for iconutil.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func draw(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // tile (macOS icon grid: 80% of the canvas, continuous corners), soft drop shadow
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let r = tile.width * 0.225
    let face = NSBezierPath(roundedRect: tile, xRadius: r, yRadius: r)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    c(0xF59E0B).setFill(); face.fill()
    ctx.restoreGState()
    NSGradient(colors: [c(0xFFC21A), c(0xF59E0B)])!.draw(in: face, angle: -90)

    // a habit (ink circle) and a task (cream rounded square), side by side
    let d = s * 0.2, cy = tile.midY
    let dot = NSRect(x: tile.midX - s * 0.12 - d / 2, y: cy - d / 2, width: d, height: d)
    c(0x141414).setFill(); NSBezierPath(ovalIn: dot).fill()
    let box = NSRect(x: tile.midX + s * 0.02, y: cy - d / 2, width: d, height: d)
    c(0xFFF6E0).setFill(); NSBezierPath(roundedRect: box, xRadius: d * 0.28, yRadius: d * 0.28).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
