import SwiftUI
import CoreText

/// Bricolage Grotesque (display), Hanken Grotesk (body), JetBrains Mono (labels), all SIL OFL.
/// They ship inside the bundle and register at launch; if a file is missing we fall back to the system faces.
enum Fonts {
    nonisolated(unsafe) private(set) static var available = false

    static func register(in bundle: Bundle = .main) {
        let names = ["BricolageGrotesque", "HankenGrotesk", "JetBrainsMono"]
        var ok = 0
        for n in names {
            guard let url = bundle.url(forResource: n, withExtension: "ttf") else { continue }
            var err: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err) { ok += 1 }
            else if let e = err?.takeRetainedValue(), CFErrorGetCode(e) == 105 { ok += 1 } // already registered
        }
        available = ok == names.count
    }
}

extension Font {
    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        Fonts.available ? .custom("Bricolage Grotesque", fixedSize: size).weight(weight == .heavy || weight == .black ? .heavy : weight)
                        : .system(size: size, weight: weight, design: .default)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        Fonts.available ? .custom("JetBrains Mono", fixedSize: size).weight(weight) : .system(size: size, weight: weight, design: .monospaced)
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        Fonts.available ? .custom("Hanken Grotesk", fixedSize: size).weight(weight) : .system(size: size, weight: weight)
    }
}

/// Uppercase monospaced micro-label, the app's only "UI chrome" type.
struct MonoCaps: View {
    let text: String
    var size: CGFloat = 11
    var color: Color? = nil
    var weight: Font.Weight = .medium
    @Environment(\.skin) private var skin

    init(_ text: String, size: CGFloat = 11, color: Color? = nil, weight: Font.Weight = .medium) {
        self.text = text; self.size = size; self.color = color; self.weight = weight
    }

    var body: some View {
        Text(text.uppercased())
            .font(.mono(size, weight))
            .tracking(size * 0.13)
            .foregroundStyle(color ?? skin.fgDim)
            .monospacedDigit()
    }
}

private struct SkinKey: EnvironmentKey { static let defaultValue = Skin.carbon }
extension EnvironmentValues {
    var skin: Skin {
        get { self[SkinKey.self] }
        set { self[SkinKey.self] = newValue }
    }
}

struct SkinBackground: View {
    @Environment(\.skin) private var skin
    var body: some View {
        ZStack {
            LinearGradient(colors: [skin.bgTop, skin.bgBottom], startPoint: .top, endPoint: .bottom)
            SkinGlows(skin: skin)
            if skin.dark {
                // fine film grain so dark skins feel like a material, not a flat fill
                Canvas { ctx, size in
                    var rng = SplitMix(seed: 42)
                    for _ in 0..<Int(size.width * size.height / 90) {
                        let x = rng.next() * size.width, y = rng.next() * size.height
                        ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                                 with: .color(.white.opacity(rng.next() * 0.035)))
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}

/// Soft radial light pools some skins paint behind everything.
struct SkinGlows: View {
    let skin: Skin
    var body: some View {
        GeometryReader { g in
            let side = max(g.size.width, g.size.height)
            ZStack {
                ForEach(skin.glows, id: \.self) { glow in
                    RadialGradient(colors: [glow.color, glow.color.opacity(0)], center: glow.center,
                                   startRadius: 0, endRadius: side * glow.radius)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A rounded panel that reads as part of the skin, not as system chrome.
struct Panel<Content: View>: View {
    @Environment(\.skin) private var skin
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(skin.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(skin.line))
    }
}

struct PillButtonStyle: ButtonStyle {
    @Environment(\.skin) private var skin
    var filled = false
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(13, .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(destructive ? .white : filled ? skin.onAccent : skin.fg)
            .background(Capsule().fill(destructive ? Color(hex: 0xB6423E) : filled ? skin.accent : skin.fg.opacity(0.08)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

struct IconButtonStyle: ButtonStyle {
    @Environment(\.skin) private var skin
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(15, .bold))
            .foregroundStyle(skin.fg)
            .frame(width: 32, height: 32)
            .background(Circle().fill(skin.fg.opacity(configuration.isPressed ? 0.14 : 0.0001)))
            .contentShape(Circle())
    }
}
