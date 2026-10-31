import SwiftUI

/// The check mark, drawn in a 100×100 box. Shared by the 3D mesh and the 2D orb.
struct CheckShape: Shape {
    static let points: [CGPoint] = [
        CGPoint(x: 16, y: 50), CGPoint(x: 30, y: 36), CGPoint(x: 42, y: 48),
        CGPoint(x: 70, y: 20), CGPoint(x: 84, y: 34), CGPoint(x: 42, y: 76),
    ]

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 100
        var p = Path()
        p.addLines(Self.points.map { CGPoint(x: rect.minX + $0.x * s, y: rect.minY + $0.y * s) })
        p.closeSubpath()
        return p
    }
}

/// A flat-shaded "extruded" check: stacked side layers plus a face, like the 3D one.
struct ExtrudedCheck: View {
    var face: Color
    var side: Color

    var body: some View {
        GeometryReader { g in
            let depth = g.size.width * 0.09
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let k = CGFloat(8 - i) / 8
                    CheckShape().fill(side).offset(x: -depth * k, y: depth * k)
                }
                CheckShape().fill(face)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// A lightweight 2D orb for the sidebar, menu bar, settings and widgets.
struct MiniOrb: View {
    let skin: Skin
    var done: Bool
    var size: CGFloat

    private static let oilSlick: [Color] = [
        Color(hex: 0xFF3B2F), Color(hex: 0xFFB300), Color(hex: 0x2FD0A8), Color(hex: 0x1D6BFF),
        .clear, .clear, Color(hex: 0xFF3B2F),
    ]

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: skin.orb2D, center: UnitPoint(x: 0.5, y: 0.32),
                                         startRadius: 0, endRadius: size * 0.62))
            if skin.iridescence > 0 {
                Circle()
                    .strokeBorder(AngularGradient(colors: Self.oilSlick, center: .center, angle: .degrees(200)),
                                  lineWidth: max(1.5, size * 0.075))
                    .blur(radius: size * 0.025)
                    .opacity(skin.iridescence)
                    .clipShape(Circle())
            }
            if skin.glow > 0 {
                Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: max(1, size * 0.02))
            }
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.18), .clear], center: .center,
                                     startRadius: 0, endRadius: size * 0.3))
                .frame(width: size * 0.56, height: size * 0.3)
                .offset(y: -size * 0.27)
            if done {
                ExtrudedCheck(face: skin.checkFace, side: skin.checkSide)
                    .frame(width: size * 0.6, height: size * 0.6)
                    .offset(x: size * 0.02)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: skin.glow > 0 ? skin.accent.opacity(0.5) : .black.opacity(skin.dark ? 0.5 : 0.2),
                radius: size * 0.08, y: skin.glow > 0 ? 0 : size * 0.05)
    }
}
