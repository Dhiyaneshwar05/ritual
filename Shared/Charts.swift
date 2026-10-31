import SwiftUI

/// Low-poly mountain with a switchback trail of 60 reps and a flag at each level.
struct ClimbChart: View {
    @Environment(\.skin) private var skin
    let reps: Int
    var length = 60

    private static let facets: [([CGPoint], UInt32)] = [
        ([p(20, 200), p(120, 110), p(90, 200)], 0x1C262D), ([p(90, 200), p(120, 110), p(170, 200)], 0x042878),
        ([p(120, 110), p(200, 24), p(170, 200)], 0x1694A4), ([p(200, 24), p(250, 120), p(170, 200)], 0x1C262D),
        ([p(170, 200), p(250, 120), p(300, 200)], 0x1BB86D), ([p(250, 120), p(340, 200), p(300, 200)], 0x947D18),
        ([p(120, 110), p(150, 70), p(200, 24)], 0xE07A10), ([p(200, 24), p(225, 70), p(250, 120)], 0x0B1318),
    ]
    private static let trail: [CGPoint] = [p(60, 192), p(250, 176), p(110, 150), p(230, 128), p(140, 104), p(220, 82), p(165, 62), p(205, 40), p(200, 26)]
    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    private static func point(at t: Double) -> CGPoint {
        var lens: [Double] = [], total = 0.0
        for i in 1..<trail.count { let l = hypot(trail[i].x - trail[i - 1].x, trail[i].y - trail[i - 1].y); lens.append(l); total += l }
        var d = t * total
        for i in 0..<lens.count {
            if d <= lens[i] { let f = d / lens[i]; return CGPoint(x: trail[i].x + (trail[i + 1].x - trail[i].x) * f, y: trail[i].y + (trail[i + 1].y - trail[i].y) * f) }
            d -= lens[i]
        }
        return trail.last!
    }

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 360, size.height / 210)
            ctx.translateBy(x: (size.width - 360 * s) / 2, y: (size.height - 210 * s) / 2)
            ctx.scaleBy(x: s, y: s)
            for (pts, hex) in Self.facets {
                var path = Path(); path.addLines(pts); path.closeSubpath()
                ctx.fill(path, with: .color(Color(hex: hex)))
            }
            var snow = Path(); snow.addLines([Self.p(200, 24), Self.p(212, 44), Self.p(188, 44)]); snow.closeSubpath()
            ctx.fill(snow, with: .color(.white.opacity(0.85)))

            var all = Path(); all.addLines((0...60).map { Self.point(at: Double($0) / 60) }) // trail shape only
            ctx.stroke(all, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            if reps > 0 {
                var done = Path(); done.addLines((0...reps).map { Self.point(at: Double($0) / Double(length)) })
                ctx.stroke(done, with: .color(skin.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            for c in Journey.cumulative(length: length) {
                let pt = Self.point(at: Double(c) / Double(length)), reached = reps >= c
                var pole = Path(); pole.move(to: pt); pole.addLine(to: CGPoint(x: pt.x, y: pt.y - 11))
                ctx.stroke(pole, with: .color(.white.opacity(reached ? 1 : 0.4)), lineWidth: 1.2)
                var flag = Path(); flag.addLines([CGPoint(x: pt.x, y: pt.y - 11), CGPoint(x: pt.x + 8, y: pt.y - 8), CGPoint(x: pt.x, y: pt.y - 5)]); flag.closeSubpath()
                ctx.fill(flag, with: .color(reached ? skin.accent : .white.opacity(0.35)))
            }
            let me = Self.point(at: Double(min(reps, length)) / Double(length))
            ctx.fill(Path(ellipseIn: CGRect(x: me.x - 6, y: me.y - 6, width: 12, height: 12)), with: .color(skin.accent))
            ctx.stroke(Path(ellipseIn: CGRect(x: me.x - 6, y: me.y - 6, width: 12, height: 12)), with: .color(.white), lineWidth: 2)
        }
        .accessibilityLabel("\(reps) of \(length) reps on the climb")
    }
}
