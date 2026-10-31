// Draws the Ritual app icon: a carbon tile with a thick bottom edge, a black orb with an
// oil-slick rim, and a white extruded check. Writes an .iconset folder for iconutil.
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

    // tile (macOS icon grid: ~80% of canvas, continuous corners)
    let inset = s * 0.1, tile = NSRect(x: inset, y: inset + s * 0.02, width: s - inset * 2, height: s - inset * 2 - s * 0.02)
    let r = tile.width * 0.225
    c(0x0A0A0B).setFill()
    NSBezierPath(roundedRect: tile.offsetBy(dx: 0, dy: -s * 0.025), xRadius: r, yRadius: r).fill()
    let face = NSBezierPath(roundedRect: tile, xRadius: r, yRadius: r)
    NSGradient(colors: [c(0x2E2E30), c(0x1A1A1B)])!.draw(in: face, angle: -90)

    // orb
    let d = tile.width * 0.62
    let orb = NSRect(x: tile.midX - d / 2, y: tile.midY - d / 2 + s * 0.005, width: d, height: d)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: NSColor.black.withAlphaComponent(0.6).cgColor)
    c(0x060607).setFill(); NSBezierPath(ovalIn: orb).fill()
    ctx.restoreGState()
    NSGradient(colors: [c(0x232325), c(0x050506)])!.draw(in: NSBezierPath(ovalIn: orb), relativeCenterPosition: NSPoint(x: 0, y: 0.45))

    // oil-slick rim
    ctx.saveGState()
    NSBezierPath(ovalIn: orb).addClip()
    // conic oil-slick drawn as many thin arc segments, interpolating hue stops
    let stops: [(CGFloat, NSColor)] = [(0, c(0xFF3B2F)), (0.14, c(0xFFB300)), (0.28, c(0x2FD0A8)), (0.42, c(0x1D6BFF)),
                                       (0.55, c(0x1D6BFF, 0)), (0.85, c(0xFF3B2F, 0)), (1, c(0xFF3B2F))]
    func color(at t: CGFloat) -> NSColor {
        for i in 1..<stops.count where t <= stops[i].0 {
            let (t0, a) = stops[i - 1], (t1, b) = stops[i]
            return a.blended(withFraction: (t - t0) / (t1 - t0), of: b) ?? a
        }
        return stops.last!.1
    }
    ctx.setBlendMode(.normal)
    let center = CGPoint(x: orb.midX, y: orb.midY), radius = d / 2 - d * 0.04
    let segments = 240
    ctx.setLineWidth(d * 0.085)
    for i in 0..<segments {
        let t = CGFloat(i) / CGFloat(segments)
        let a0 = .pi * 1.1 + t * 2 * .pi, a1 = a0 + 2 * .pi / CGFloat(segments) + 0.01
        ctx.setStrokeColor(color(at: t).cgColor)
        ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
        ctx.strokePath()
    }
    ctx.restoreGState()
    // soft highlight
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: orb.midX - d * 0.26, y: orb.maxY - d * 0.3, width: d * 0.52, height: d * 0.2)), relativeCenterPosition: .zero)

    // extruded check
    let pts: [CGPoint] = [CGPoint(x: 16, y: 50), CGPoint(x: 30, y: 36), CGPoint(x: 42, y: 48), CGPoint(x: 70, y: 20), CGPoint(x: 84, y: 34), CGPoint(x: 42, y: 76)]
    let k = d * 0.56 / 100, ox = orb.midX - 50 * k + d * 0.02, oy = orb.midY + 50 * k
    func check(dx: CGFloat, dy: CGFloat) -> NSBezierPath {
        let p = NSBezierPath()
        for (i, q) in pts.enumerated() {
            let pt = NSPoint(x: ox + q.x * k + dx, y: oy - q.y * k + dy)
            i == 0 ? p.move(to: pt) : p.line(to: pt)
        }
        p.close(); return p
    }
    let depth = d * 0.07
    for i in stride(from: 10, through: 1, by: -1) {
        let f = CGFloat(i) / 10
        c(0x9D9D9D).setFill(); check(dx: -depth * f, dy: -depth * f).fill()
    }
    c(0xFFFFFF).setFill(); check(dx: 0, dy: 0).fill()

    // amber spark
    let sp = NSBezierPath()
    let sx = tile.maxX - tile.width * 0.2, sy = tile.maxY - tile.width * 0.2, sr = tile.width * 0.05
    sp.move(to: NSPoint(x: sx, y: sy + sr * 1.6)); sp.line(to: NSPoint(x: sx + sr, y: sy)); sp.line(to: NSPoint(x: sx, y: sy - sr * 1.6)); sp.line(to: NSPoint(x: sx - sr, y: sy)); sp.close()
    c(0xFDB000).setFill(); sp.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
