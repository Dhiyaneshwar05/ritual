import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// A skin is a whole world: background, ink, accent, orb material, check colors and monument colors.
struct Skin: Identifiable, Hashable {
    let id: String
    let name: String
    let tagline: String
    let dark: Bool
    let bgTop: Color
    let bgBottom: Color
    let fg: Color
    let fgDim: Color
    let accent: Color
    let onAccent: Color
    let chip: Color
    let chipFg: Color
    let ring: Color
    let sidebar: Color
    let card: Color
    let line: Color
    // orb
    let orbBase: Color
    let orbRoughness: Double
    let orbMetalness: Double
    let iridescence: Double
    let glow: Double
    let glass: Bool
    let orb2D: [Color]
    let checkFace: Color
    let checkSide: Color
    // celebration + monument
    let shardA: Color
    let shardB: Color
    let plinth: Color
    let pieceA: Color
    let pieceB: Color
    /// Optional soft light pools painted over the gradient: (color, unit center, radius as a fraction of the larger side).
    var glows: [Glow] = []

    struct Glow: Hashable { let color: Color; let center: UnitPoint; let radius: CGFloat }
}

extension Skin {
    static let carbon = Skin(
        id: "carbon", name: "Carbon", tagline: "Matte black stone, amber light", dark: true,
        bgTop: Color(hex: 0x2A2A2B), bgBottom: Color(hex: 0x19191A),
        fg: Color(hex: 0xEDEDED), fgDim: Color(hex: 0x8A8A8A), accent: Color(hex: 0xFDB000), onAccent: Color(hex: 0x141414),
        chip: Color(hex: 0x050505), chipFg: Color(hex: 0xEDEDED), ring: Color(hex: 0x3A3A3A),
        sidebar: Color(hex: 0x161617), card: Color(hex: 0xFFFFFF, alpha: 0.045), line: Color(hex: 0xFFFFFF, alpha: 0.07),
        orbBase: Color(hex: 0x0E0E0F), orbRoughness: 0.34, orbMetalness: 0.05, iridescence: 0, glow: 0, glass: false,
        orb2D: [Color(hex: 0x1D1D1E), Color(hex: 0x0F0F10), Color(hex: 0x060606)],
        checkFace: Color(hex: 0xF5F5F5), checkSide: Color(hex: 0x9D9D9D),
        shardA: Color(hex: 0xFFCC06), shardB: Color(hex: 0xFF8B0B),
        plinth: Color(hex: 0x111112), pieceA: Color(hex: 0xE8A417), pieceB: Color(hex: 0xC9661A))

    static let paper = Skin(
        id: "paper", name: "Paper", tagline: "White page, oil-slick rim", dark: false,
        bgTop: Color(hex: 0xFBFBF9), bgBottom: Color(hex: 0xEEEEEA),
        fg: Color(hex: 0x141414), fgDim: Color(hex: 0x76767A), accent: Color(hex: 0x2B4BFF), onAccent: .white,
        chip: Color(hex: 0x141414), chipFg: Color(hex: 0xFAFAF8), ring: Color(hex: 0xD3D3CF),
        sidebar: Color(hex: 0xF1F1EE), card: Color(hex: 0xFFFFFF), line: Color(hex: 0x141414, alpha: 0.08),
        orbBase: Color(hex: 0x050506), orbRoughness: 0.16, orbMetalness: 0.0, iridescence: 1.0, glow: 0, glass: false,
        orb2D: [Color(hex: 0x1A1A1C), Color(hex: 0x070708), Color(hex: 0x000000)],
        checkFace: Color(hex: 0xFFFFFF), checkSide: Color(hex: 0xBDBDBD),
        shardA: Color(hex: 0x2B4BFF), shardB: Color(hex: 0xFF3B2F),
        plinth: Color(hex: 0x1A1A1B), pieceA: Color(hex: 0xEDEDE9), pieceB: Color(hex: 0x3550E8))

    static let marigold = Skin(
        id: "marigold", name: "Marigold", tagline: "Warm amber glass", dark: false,
        bgTop: Color(hex: 0xF6BD45), bgBottom: Color(hex: 0xE2872D),
        fg: Color(hex: 0x2A1806), fgDim: Color(hex: 0x7A4D16), accent: Color(hex: 0x3A2208), onAccent: Color(hex: 0xF6BD45),
        chip: Color(hex: 0x2A1806), chipFg: Color(hex: 0xF6BD45), ring: Color(hex: 0xC98A33),
        sidebar: Color(hex: 0xEDA83E), card: Color(hex: 0xFFFFFF, alpha: 0.2), line: Color(hex: 0x2A1806, alpha: 0.12),
        orbBase: Color(hex: 0x5A320C), orbRoughness: 0.22, orbMetalness: 0.1, iridescence: 0, glow: 0, glass: false,
        orb2D: [Color(hex: 0x9A6020), Color(hex: 0x6A3C10), Color(hex: 0x3E2207)],
        checkFace: Color(hex: 0xFFFFFF), checkSide: Color(hex: 0xD9CBB6),
        shardA: Color(hex: 0xFFF3D6), shardB: Color(hex: 0x6A3C10),
        plinth: Color(hex: 0x2A1806), pieceA: Color(hex: 0xFFF3D6), pieceB: Color(hex: 0x8A5418))

    static let aurora = Skin(
        id: "aurora", name: "Aurora", tagline: "Lavender ice, glowing glass", dark: false,
        bgTop: Color(hex: 0xCBA8F6), bgBottom: Color(hex: 0xD4F6FB),
        fg: Color(hex: 0x1B1238), fgDim: Color(hex: 0x5B4E86), accent: Color(hex: 0x6C4CE0), onAccent: .white,
        chip: Color(hex: 0x1B1238), chipFg: Color(hex: 0xEFE6FF), ring: Color(hex: 0xA99BD8),
        sidebar: Color(hex: 0xC4B3F4), card: Color(hex: 0xFFFFFF, alpha: 0.3), line: Color(hex: 0x1B1238, alpha: 0.1),
        orbBase: Color(hex: 0x5D5590), orbRoughness: 0.12, orbMetalness: 0.0, iridescence: 0.55, glow: 0.9, glass: true,
        orb2D: [Color(hex: 0x8F86B8), Color(hex: 0x5D5590), Color(hex: 0x3B3468)],
        checkFace: Color(hex: 0xFBE4FF), checkSide: Color(hex: 0xC79CF0),
        shardA: Color(hex: 0xFFFFFF), shardB: Color(hex: 0xA98CFF),
        plinth: Color(hex: 0x1B1238), pieceA: Color(hex: 0xFFFFFF), pieceB: Color(hex: 0xA98CFF))

    static let coral = Skin(
        id: "coral", name: "Coral", tagline: "Soft clay on dark plum", dark: true,
        bgTop: Color(hex: 0x2B1A1F), bgBottom: Color(hex: 0x170F12),
        fg: Color(hex: 0xF6E9E4), fgDim: Color(hex: 0xA07F86), accent: Color(hex: 0xFD6281), onAccent: Color(hex: 0x170F12),
        chip: Color(hex: 0xFD6281), chipFg: Color(hex: 0x170F12), ring: Color(hex: 0x4A2C34),
        sidebar: Color(hex: 0x130C0E), card: Color(hex: 0xFFFFFF, alpha: 0.045), line: Color(hex: 0xFFFFFF, alpha: 0.07),
        orbBase: Color(hex: 0xF0506F), orbRoughness: 0.62, orbMetalness: 0.0, iridescence: 0, glow: 0, glass: false,
        orb2D: [Color(hex: 0xFF8AA0), Color(hex: 0xFD6281), Color(hex: 0xE4405B), Color(hex: 0xA82640)],
        checkFace: Color(hex: 0xFFF6EF), checkSide: Color(hex: 0xE8CFC2),
        shardA: Color(hex: 0xFD6281), shardB: Color(hex: 0xFFD9A8),
        plinth: Color(hex: 0x3A2329), pieceA: Color(hex: 0xFD6281), pieceB: Color(hex: 0xFFD9A8))

    /// The desk from the design board: violet ink with an ember glow top-left and a violet glow bottom-right.
    static let ember = Skin(
        id: "ember", name: "Ember", tagline: "Violet ink, embers in the corner", dark: true,
        bgTop: Color(hex: 0x1E1B22), bgBottom: Color(hex: 0x17151B),
        fg: Color(hex: 0xEFEDF2), fgDim: Color(hex: 0x9A95A3), accent: Color(hex: 0xF2A23A), onAccent: Color(hex: 0x1A1410),
        chip: Color(hex: 0x060507), chipFg: Color(hex: 0xEFEDF2), ring: Color(hex: 0x3A3542),
        sidebar: Color(hex: 0x141217), card: Color(hex: 0xFFFFFF, alpha: 0.05), line: Color(hex: 0xFFFFFF, alpha: 0.08),
        orbBase: Color(hex: 0x0D0B10), orbRoughness: 0.3, orbMetalness: 0.05, iridescence: 0, glow: 0, glass: false,
        orb2D: [Color(hex: 0x221E27), Color(hex: 0x110F14), Color(hex: 0x060507)],
        checkFace: Color(hex: 0xF5F3F7), checkSide: Color(hex: 0x9E98A6),
        shardA: Color(hex: 0xF2A23A), shardB: Color(hex: 0xA47CF0),
        plinth: Color(hex: 0x100E13), pieceA: Color(hex: 0xE59A3C), pieceB: Color(hex: 0x8C6AD8),
        glows: [Glow(color: Color(hex: 0x5A2A14), center: UnitPoint(x: 0.12, y: 0.08), radius: 0.62),
                Glow(color: Color(hex: 0x3B2A52), center: UnitPoint(x: 0.9, y: 0.95), radius: 0.58)])

    static let all: [Skin] = [carbon, ember, paper, marigold, aurora, coral]
    static func named(_ id: String) -> Skin { all.first { $0.id == id } ?? carbon }
}
