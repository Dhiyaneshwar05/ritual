import SwiftUI

/// "How Ritual works" — one short card per idea, each with a small live drawing from the app itself.
struct GuideView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Card { let eyebrow: String; let title: String; let body: String; let art: Art }
    private enum Art { case orb, journey, monument, week, bar, year, climb, dust, pane, tasks, shelf }

    private let cards: [Card] = [
        Card(eyebrow: "What this is", title: "A habit builder, not a to-do list",
             body: "Pick something small. Each day you do it, hold the orb. Repeat it enough times and it becomes automatic. That's the whole idea.",
             art: .orb),
        Card(eyebrow: "Reps, not streaks", title: "Missed days cost nothing",
             body: "A journey is 60 check-ins (you can pick 30 or 90). They don't have to be in a row. Skip a day and you simply pick up where you left off.",
             art: .journey),
        Card(eyebrow: "Journey", title: "Eight levels, one monument each",
             body: "Every rep places one piece on the current level's monument. Faint outlines show the pieces still to come. Finish the last level to place the gem.",
             art: .monument),
        Card(eyebrow: "Week row", title: "Your last seven days",
             body: "Black circles are days you did it. Click any day to tick or untick it. Dashed circles are rest days you didn't schedule; they never count against you.",
             art: .week),
        Card(eyebrow: "Journey bar", title: "The bar along the bottom",
             body: "Each section is a level. Yellow is done, the lighter part is where your current pace gets you in two weeks, and the date is when you'd place the gem.",
             art: .bar),
        Card(eyebrow: "Year field", title: "A whole year on one page",
             body: "Months run left to right and days top to bottom. A small shard marks each day you did it. Quiet dots are days you didn't.",
             art: .year),
        Card(eyebrow: "Climb", title: "How far up the mountain",
             body: "The trail winds from base to peak in 60 steps. Each flag is a level. The dot is you.",
             art: .climb),
        Card(eyebrow: "Showed up · dust", title: "Gentle signals, never guilt",
             body: "\"Showed up 22 of the last 30 days\" tells you how steady you are. Away a week and a little dust settles on the orb. One check clears it.",
             art: .dust),
        Card(eyebrow: "Day pane · All habits", title: "The whole day at a glance",
             body: "The right pane shows today across every habit, your groups, the last week and what's coming up next. The All habits tab adds a year of totals.",
             art: .pane),
        Card(eyebrow: "Tasks", title: "One-off things, same reminders",
             body: "The Tasks tab is a plain to-do list for things you do once. Type “Call the bank tomorrow 11am #bank !2” and it picks up the day, time, label and priority. Unfinished tasks move up to today.",
             art: .tasks),
        Card(eyebrow: "Trophy shelf", title: "Where finished habits live",
             body: "When a journey ends you choose: keep going, start a new journey, or retire the habit to the shelf. You can bring anything back later.",
             art: .shelf),
    ]

    var body: some View {
        let c = cards[page]
        VStack(spacing: 0) {
            HStack {
                MonoCaps("How Ritual works · \(page + 1) of \(cards.count)", size: 10)
                Spacer()
                Button("Close") { finish() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24).padding(.top, 20)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(skin.fg.opacity(0.04))
                art(c.art).padding(26)
            }
            .frame(height: 250)
            .padding(.horizontal, 24).padding(.top, 16)
            .id(page)
            .transition(.opacity)

            VStack(alignment: .leading, spacing: 8) {
                MonoCaps(c.eyebrow, size: 10, color: skin.accent)
                Text(c.title).font(.display(26)).foregroundStyle(skin.fg)
                Text(c.body).font(.body(14.5)).foregroundStyle(skin.fgDim).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 20)

            Spacer(minLength: 12)

            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(cards.indices, id: \.self) { i in
                        Button { withAnimation(.easeInOut(duration: 0.2)) { page = i } } label: {
                            Capsule().fill(i == page ? skin.accent : skin.fg.opacity(0.2)).frame(width: i == page ? 18 : 7, height: 7)
                        }
                        .buttonStyle(.plain)
                        .help(cards[i].eyebrow)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { page -= 1 } }
                        .buttonStyle(PillButtonStyle()).keyboardShortcut(.leftArrow, modifiers: [])
                }
                Button(page == cards.count - 1 ? "Start" : "Next") {
                    if page == cards.count - 1 { finish() } else { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } }
                }
                .buttonStyle(PillButtonStyle(filled: true)).keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 640, height: 600)
        .background(SkinBackground())
    }

    private func finish() {
        store.updateSettings { $0.seenGuide = true }
        dismiss()
    }

    // MARK: Art — real components with sample data

    private var sample: Habit {
        var h = Habit(name: "Meditate", goal: "10 minutes")
        let t = store.today
        h.created = Day.add(-60, to: t)
        for back in [1, 2, 3, 5, 6, 8, 9, 10, 12, 13, 15, 16, 17, 19, 20, 22, 23, 24, 26, 27, 29, 30, 31, 33, 34, 36, 37, 38, 40]
        { h.log[Day.key(Day.add(-back, to: t))] = 1 }
        return h
    }

    @ViewBuilder private func art(_ a: Art) -> some View {
        switch a {
        case .orb:
            HStack(spacing: 40) {
                VStack(spacing: 10) { MiniOrb(skin: skin, done: false, size: 130); MonoCaps("Hold to check", size: 9) }
                Image(systemName: "arrow.right").font(.system(size: 20, weight: .bold)).foregroundStyle(skin.fgDim)
                VStack(spacing: 10) { MiniOrb(skin: skin, done: true, size: 130); MonoCaps("Done for today", size: 9, color: skin.accent) }
            }
        case .journey:
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ForEach(0..<14, id: \.self) { i in
                        let on = ![3, 4, 8].contains(i)
                        VStack(spacing: 5) {
                            Circle().fill(on ? skin.chip : .clear).overlay(Circle().strokeBorder(skin.ring, lineWidth: on ? 0 : 1.5))
                                .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(skin.chipFg) } }
                                .frame(width: 26, height: 26)
                            Text(on ? "\([0, 1, 2, 2, 2, 3, 4, 5, 5, 6, 7, 8, 9, 10][i] + 1)" : "–").font(.mono(8.5)).foregroundStyle(on ? skin.fg : skin.fgDim)
                        }
                    }
                }
                MonoCaps("Gaps are fine · the count only goes up", size: 9)
            }
        case .monument:
            HStack(spacing: 22) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 8) {
                        MiniMonument(placed: [1, 3, 5, 7][i], total: 7, skin: skin).frame(width: 96, height: 120)
                        MonoCaps(["Rep 1", "Rep 3", "Rep 5", "Gem"][i], size: 8.5, color: i == 3 ? skin.accent : nil)
                    }
                }
            }
        case .week:
            VStack(spacing: 14) {
                WeekRow(habit: sample).allowsHitTesting(false)
                HStack(spacing: 18) {
                    legend(AnyView(Circle().fill(skin.chip).frame(width: 14, height: 14)), "Done")
                    legend(AnyView(Circle().strokeBorder(skin.ring, lineWidth: 1.5).frame(width: 14, height: 14)), "Not yet")
                    legend(AnyView(Circle().strokeBorder(skin.ring, style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])).frame(width: 14, height: 14)), "Rest day")
                }
            }
        case .bar:
            JourneyBar(habit: sample).allowsHitTesting(false).frame(maxWidth: 520)
        case .year:
            YearField(habit: sample, year: Calendar.current.component(.year, from: store.today)).allowsHitTesting(false).frame(maxWidth: 360)
        case .climb:
            ClimbChart(reps: sample.journeyReps).frame(maxWidth: 420)
        case .dust:
            HStack(spacing: 40) {
                VStack(spacing: 10) {
                    ZStack { MiniOrb(skin: skin, done: false, size: 120); DustOverlay(amount: 0.8).frame(width: 120, height: 120) }
                    MonoCaps("12 days away", size: 9)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("26 of 30").font(.display(40)).foregroundStyle(skin.fg)
                    MonoCaps("Showed up · last 30 days", size: 9)
                }
            }
        case .pane:
            HStack(spacing: 28) {
                ZStack {
                    Circle().stroke(skin.fg.opacity(0.12), lineWidth: 9)
                    Circle().trim(from: 0, to: 0.6).stroke(skin.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("3/5").font(.display(26)).foregroundStyle(skin.fg)
                }
                .frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(["Morning", "Body", "Evening"], id: \.self) { g in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(g).font(.body(12, .medium)).foregroundStyle(skin.fg)
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { j in
                                    RoundedRectangle(cornerRadius: 2).fill(j < (g == "Body" ? 1 : 2) ? skin.accent : skin.fg.opacity(0.13))
                                }
                            }
                            .frame(width: 170, height: 6)
                        }
                    }
                }
            }
        case .tasks:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array([("Pay electricity bill", 1, true, "1 day late"), ("Call the bank", 2, false, "11:30 AM"), ("Pick up dry cleaning", 0, false, "")].enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 12) {
                        TaskCheckbox(done: i == 2, priority: r.1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.0).font(.body(14, .semibold)).foregroundStyle(i == 2 ? skin.fgDim : skin.fg).strikethrough(i == 2, color: skin.fgDim)
                            if !r.3.isEmpty { Text(r.3).font(.mono(10)).foregroundStyle(r.2 ? PriorityColor.color(1, dark: skin.dark) : skin.fgDim) }
                        }
                        Spacer()
                        Text(TaskItem.bangs(r.1)).font(.mono(12, .bold)).foregroundStyle(PriorityColor.color(r.1, dark: skin.dark))
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Rectangle().fill(skin.line).frame(height: 1) }
                }
            }
            .frame(maxWidth: 380)
        case .shelf:
            VStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 30) {
                    Image(systemName: "trophy.fill").font(.system(size: 64)).foregroundStyle(LinearGradient(colors: [Color(hex: 0xF7C64A), Color(hex: 0xC27A12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "trophy.fill").font(.system(size: 48)).foregroundStyle(LinearGradient(colors: [Color(hex: 0xF7C64A), Color(hex: 0xC27A12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: "seal.fill").font(.system(size: 40)).foregroundStyle(skin.fgDim)
                }
                .padding(.bottom, 4)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: skin.dark ? [Color(hex: 0x5A3A22), Color(hex: 0x3C2616)] : [Color(hex: 0xC99A6B), Color(hex: 0xA5784E)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 300, height: 16)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 8)
            }
        }
    }

    private func legend(_ shape: AnyView, _ label: String) -> some View {
        HStack(spacing: 6) { shape; Text(label).font(.body(12)).foregroundStyle(skin.fgDim) }
    }
}

/// A flat isometric stand-in for a level monument, for the guide.
private struct MiniMonument: View {
    let placed: Int
    let total: Int
    let skin: Skin
    var body: some View {
        Canvas { ctx, size in
            let s: CGFloat = 16, ox = size.width / 2, oy = size.height - 30
            func P(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint { CGPoint(x: ox + (x - y) * s * 0.866, y: oy + (x + y) * s * 0.5 - z * s) }
            func box(_ x0: CGFloat, _ y0: CGFloat, _ z0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ z1: CGFloat, _ c: Color?, ghost: Bool) {
                let faces: [([CGPoint], Double)] = [
                    ([P(x0, y1, z1), P(x1, y1, z1), P(x1, y1, z0), P(x0, y1, z0)], 0.62),
                    ([P(x1, y0, z1), P(x1, y1, z1), P(x1, y1, z0), P(x1, y0, z0)], 0.42),
                    ([P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1)], 1.0),
                ]
                for (pts, k) in faces {
                    var p = Path(); p.addLines(pts); p.closeSubpath()
                    if ghost { ctx.stroke(p, with: .color(skin.fg.opacity(0.14)), lineWidth: 1) }
                    else { ctx.fill(p, with: .color(c!.opacity(1))); ctx.fill(p, with: .color(.black.opacity(1 - k))) }
                }
            }
            box(-2, -2, -0.5, 2, 2, 0, skin.plinth, ghost: false)
            let blocks: [(CGFloat, CGFloat, CGFloat)] = [(-1, -1, 0), (0, -1, 0), (-1, 0, 0), (0, 0, 0), (-0.5, -0.5, 1), (-0.5, -0.5, 2)]
            for (i, b) in blocks.enumerated() {
                box(b.0, b.1, b.2, b.0 + 1, b.1 + 1, b.2 + 0.95, i % 3 == 0 ? skin.pieceB : skin.pieceA, ghost: i >= placed)
            }
            // gem
            let g = P(0, 0, 4.4), on = placed >= total
            var a = Path(); a.addLines([CGPoint(x: g.x, y: g.y - 12), CGPoint(x: g.x - 7, y: g.y), CGPoint(x: g.x, y: g.y + 12)]); a.closeSubpath()
            var b = Path(); b.addLines([CGPoint(x: g.x, y: g.y - 12), CGPoint(x: g.x + 7, y: g.y), CGPoint(x: g.x, y: g.y + 12)]); b.closeSubpath()
            if on { ctx.fill(a, with: .color(skin.pieceB)); ctx.fill(b, with: .color(skin.pieceA)) }
            else { ctx.stroke(a, with: .color(skin.fg.opacity(0.18)), lineWidth: 1); ctx.stroke(b, with: .color(skin.fg.opacity(0.18)), lineWidth: 1) }
        }
    }
}
