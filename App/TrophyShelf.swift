import SwiftUI

/// Retired habits stand on a lit shelf. Mastered journeys get a cup with the gem; archived ones a stone marker.
/// Everything is drawn in 2D so it stays light.
struct ShelfView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID?
    @State private var confirmDelete: UUID?

    private let perShelf = 4

    var body: some View {
        let items = store.retiredHabits
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trophy shelf").font(.display(28)).foregroundStyle(skin.fg)
                    MonoCaps("\(items.filter(\.isMastered).count) mastered · \(items.filter { !$0.isMastered }.count) archived", size: 10)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PillButtonStyle(filled: true)).keyboardShortcut(.defaultAction)
            }
            .padding(24)

            ScrollView {
                VStack(spacing: 34) {
                    if items.isEmpty {
                        shelfRow([]).overlay {
                            Text("Finish a journey or archive a habit and it lands here.")
                                .font(.body(13)).foregroundStyle(skin.fgDim).offset(y: -50)
                        }
                    }
                    ForEach(Array(stride(from: 0, to: items.count, by: perShelf)), id: \.self) { i in
                        shelfRow(Array(items[i..<min(i + perShelf, items.count)]))
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 20).padding(.top, 6)
            }

            if let id = selected, let h = store.habit(id) { detail(h) }
        }
        .frame(width: 720, height: 560)
        .background(
            ZStack {
                SkinBackground()
                // a warm wash from above, like a picture light
                RadialGradient(colors: [Color(hex: 0xFFD9A0).opacity(skin.dark ? 0.10 : 0.18), .clear],
                               center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 520)
            }
        )
    }

    private func shelfRow(_ list: [Habit]) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(list) { h in
                    Button { selected = selected == h.id ? nil : h.id } label: {
                        Trophy(habit: h, highlighted: selected == h.id)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .help("\(h.name) · click for details")
                }
                ForEach(0..<(perShelf - list.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
            .frame(height: 170, alignment: .bottom)
            ShelfPlank()
        }
    }

    private func detail(_ h: Habit) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(h.name).font(.body(15, .bold)).foregroundStyle(skin.fg)
                Text("\(h.totalReps) reps · \(h.firstDone.map { "since " + $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "no reps yet")"
                     + (h.lastDone.map { " · last " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ""))
                    .font(.body(12)).foregroundStyle(skin.fgDim)
            }
            Spacer()
            if confirmDelete == h.id {
                Text("Delete it and its history?").font(.body(12)).foregroundStyle(skin.fgDim)
                Button("Keep") { confirmDelete = nil }.buttonStyle(PillButtonStyle())
                Button("Delete") { store.delete(h.id); selected = nil; confirmDelete = nil }.buttonStyle(PillButtonStyle(destructive: true))
            } else {
                Button("Bring back") { store.restore(h.id); dismiss() }.buttonStyle(PillButtonStyle(filled: true))
                Button("Delete…") { confirmDelete = h.id }.buttonStyle(PillButtonStyle(destructive: true))
            }
        }
        .padding(16)
        .background(skin.sidebar.opacity(0.9))
        .overlay(alignment: .top) { Rectangle().fill(skin.line).frame(height: 1) }
    }
}

/// A wooden plank with a lit top edge and a soft shadow underneath.
private struct ShelfPlank: View {
    @Environment(\.skin) private var skin
    var body: some View {
        let wood = skin.dark ? [Color(hex: 0x5A3A22), Color(hex: 0x3C2616)] : [Color(hex: 0xC99A6B), Color(hex: 0xA5784E)]
        ZStack(alignment: .top) {
            // shadow cast on the wall
            RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(skin.dark ? 0.55 : 0.2))
                .frame(height: 16).blur(radius: 8).offset(y: 16)
            VStack(spacing: 0) {
                Rectangle().fill(LinearGradient(colors: [wood[0].opacity(0.9), wood[0]], startPoint: .top, endPoint: .bottom)).frame(height: 8)
                Rectangle().fill(LinearGradient(colors: wood, startPoint: .top, endPoint: .bottom)).frame(height: 14)
            }
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1) }
            .overlay {
                // faint grain lines
                Canvas { ctx, size in
                    var rng = SplitMix(seed: 9)
                    for _ in 0..<14 {
                        let y = 9 + rng.next() * (size.height - 10), x = rng.next() * size.width, w = 40 + rng.next() * 160
                        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: 0.8)), with: .color(.black.opacity(0.18)))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 22)
    }
}

/// One trophy: a cup with the gem for a finished journey, a stone marker for an archived habit.
private struct Trophy: View {
    @Environment(\.skin) private var skin
    let habit: Habit
    let highlighted: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // pool of light on the shelf
                Ellipse().fill(RadialGradient(colors: [Color(hex: 0xFFE2B0).opacity(highlighted ? 0.35 : 0.16), .clear], center: .center, startRadius: 0, endRadius: 60))
                    .frame(width: 130, height: 26).offset(y: 10)
                Canvas { ctx, size in habit.isMastered ? drawCup(&ctx, size) : drawStone(&ctx, size) }
                    .frame(width: 110, height: 130)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
            }
            // engraved plaque
            VStack(spacing: 1) {
                Text(habit.name.uppercased()).font(.mono(8.5, .bold)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.7)
                Text(habit.isMastered ? "\(habit.totalReps) REPS" : "ARCHIVED").font(.mono(7.5)).opacity(0.7)
            }
            .foregroundStyle(Color(hex: 0x2A1A0C))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: 110)
            .background(RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(hex: 0xF2D58C), Color(hex: 0xC9A04E)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x8A6A2A).opacity(0.6), lineWidth: 0.8))
            .padding(.top, 2)
        }
        .scaleEffect(highlighted ? 1.05 : 1, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlighted)
    }

    private func poly(_ pts: [CGPoint]) -> Path { var p = Path(); p.addLines(pts); p.closeSubpath(); return p }

    /// Faceted cup: lit left faces, shaded right faces, the gem floating above. Colors come from the skin's monument tones.
    private func drawCup(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let cx = s.width / 2, b = s.height
        let light = Color(hex: 0xF7C64A), mid = Color(hex: 0xE09A1E), dark = Color(hex: 0xA8650E)
        // base
        ctx.fill(poly([CGPoint(x: cx - 30, y: b), CGPoint(x: cx + 30, y: b), CGPoint(x: cx + 24, y: b - 12), CGPoint(x: cx - 24, y: b - 12)]), with: .color(Color(hex: 0x2A2A2C)))
        ctx.fill(poly([CGPoint(x: cx, y: b), CGPoint(x: cx + 30, y: b), CGPoint(x: cx + 24, y: b - 12), CGPoint(x: cx, y: b - 12)]), with: .color(Color(hex: 0x1A1A1B)))
        // stem
        ctx.fill(poly([CGPoint(x: cx - 6, y: b - 12), CGPoint(x: cx + 6, y: b - 12), CGPoint(x: cx + 4, y: b - 34), CGPoint(x: cx - 4, y: b - 34)]), with: .color(mid))
        ctx.fill(poly([CGPoint(x: cx, y: b - 12), CGPoint(x: cx + 6, y: b - 12), CGPoint(x: cx + 4, y: b - 34), CGPoint(x: cx, y: b - 34)]), with: .color(dark))
        // bowl
        let top = b - 86
        ctx.fill(poly([CGPoint(x: cx - 30, y: top), CGPoint(x: cx, y: top), CGPoint(x: cx, y: b - 34), CGPoint(x: cx - 12, y: b - 38), CGPoint(x: cx - 26, y: b - 56)]), with: .color(light))
        ctx.fill(poly([CGPoint(x: cx, y: top), CGPoint(x: cx + 30, y: top), CGPoint(x: cx + 26, y: b - 56), CGPoint(x: cx + 12, y: b - 38), CGPoint(x: cx, y: b - 34)]), with: .color(mid))
        ctx.fill(poly([CGPoint(x: cx + 30, y: top), CGPoint(x: cx + 26, y: b - 56), CGPoint(x: cx + 12, y: b - 38), CGPoint(x: cx + 20, y: b - 56)]), with: .color(dark))
        // rim + handles
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 30, y: top - 5, width: 60, height: 10)), with: .color(dark))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 26, y: top - 3, width: 52, height: 6)), with: .color(Color(hex: 0x6A3E08)))
        ctx.stroke(Path { p in p.addArc(center: CGPoint(x: cx - 32, y: top + 16), radius: 10, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false) },
                   with: .color(mid), lineWidth: 4)
        ctx.stroke(Path { p in p.addArc(center: CGPoint(x: cx + 32, y: top + 16), radius: 10, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false) },
                   with: .color(dark), lineWidth: 4)
        // gem
        let gy = top - 26
        ctx.fill(poly([CGPoint(x: cx, y: gy - 14), CGPoint(x: cx - 8, y: gy), CGPoint(x: cx, y: gy + 14)]), with: .color(skin.pieceB))
        ctx.fill(poly([CGPoint(x: cx, y: gy - 14), CGPoint(x: cx + 8, y: gy), CGPoint(x: cx, y: gy + 14)]), with: .color(skin.pieceA))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - 18, y: gy - 18, width: 36, height: 36)), with: .color(skin.pieceA.opacity(0.12)))
        // highlight streak
        ctx.fill(poly([CGPoint(x: cx - 22, y: top + 4), CGPoint(x: cx - 17, y: top + 4), CGPoint(x: cx - 12, y: b - 44), CGPoint(x: cx - 15, y: b - 46)]), with: .color(.white.opacity(0.35)))
    }

    /// Stone marker for archived habits.
    private func drawStone(_ ctx: inout GraphicsContext, _ s: CGSize) {
        let cx = s.width / 2, b = s.height
        let l = skin.dark ? Color(hex: 0x6E6A72) : Color(hex: 0xB9B5AE), m = skin.dark ? Color(hex: 0x4E4B52) : Color(hex: 0x95918A), d = skin.dark ? Color(hex: 0x353338) : Color(hex: 0x76726C)
        ctx.fill(poly([CGPoint(x: cx - 26, y: b), CGPoint(x: cx, y: b), CGPoint(x: cx, y: b - 58), CGPoint(x: cx - 22, y: b - 50)]), with: .color(l))
        ctx.fill(poly([CGPoint(x: cx, y: b), CGPoint(x: cx + 26, y: b), CGPoint(x: cx + 22, y: b - 46), CGPoint(x: cx, y: b - 58)]), with: .color(m))
        ctx.fill(poly([CGPoint(x: cx - 22, y: b - 50), CGPoint(x: cx, y: b - 58), CGPoint(x: cx + 22, y: b - 46), CGPoint(x: cx + 4, y: b - 40)]), with: .color(d))
        // small crystal on top: how far the journey got
        let f = Double(habit.journeyReps) / Double(habit.journeyLength)
        let h = 10 + 22 * f
        ctx.fill(poly([CGPoint(x: cx + 2, y: b - 54 - h), CGPoint(x: cx - 5, y: b - 50), CGPoint(x: cx + 2, y: b - 46)]), with: .color(skin.pieceB.opacity(0.85)))
        ctx.fill(poly([CGPoint(x: cx + 2, y: b - 54 - h), CGPoint(x: cx + 9, y: b - 50), CGPoint(x: cx + 2, y: b - 46)]), with: .color(skin.pieceA.opacity(0.85)))
    }
}
