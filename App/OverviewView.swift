import SwiftUI

/// Accumulated stats across every active habit.
struct OverviewView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin

    var body: some View {
        let habits = store.visibleHabits
        let t = store.today
        let n = max(1, habits.count)
        let span = 364
        let counts: [Int] = (0...span).map { back in let d = Day.add(-(span - back), to: t); return habits.filter { $0.isDone(on: d) }.count }
        let active = counts.filter { $0 > 0 }.count
        let full = habits.isEmpty ? 0 : counts.filter { $0 == habits.count }.count
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("All habits").font(.display(34)).foregroundStyle(skin.fg)
                    Spacer()
                    MonoCaps("Last 52 weeks · \(habits.count) active habits", size: 10)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    tile("Total reps", "\(habits.reduce(0) { $0 + $1.totalReps })", "all habits")
                    tile("Active days", "\(active)", "at least one tick")
                    tile("Full days", "\(full)", "every habit done")
                    tile("Levels", "\(habits.reduce(0) { $0 + ($1.isMastered ? 8 : $1.level) })", "cleared of \(habits.count * 8)")
                    tile("Mastered", "\(habits.filter(\.isMastered).count + store.retiredHabits.filter(\.isMastered).count)", "journeys done")
                }
                Panel {
                    VStack(alignment: .leading, spacing: 10) {
                        MonoCaps("Habits done per day", size: 10)
                        AllHeatmap(counts: counts, total: n, today: t).frame(height: 132)
                        HStack(spacing: 6) {
                            MonoCaps("Fewer", size: 9)
                            ForEach([0, 0.25, 0.5, 0.75, 1], id: \.self) { v in
                                RoundedRectangle(cornerRadius: 3).fill(AllHeatmap.color(v, skin)).frame(width: 11, height: 11)
                            }
                            MonoCaps("More · darker = more habits done", size: 9)
                        }
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    Panel { perHabit(habits).frame(maxHeight: .infinity, alignment: .top) }
                        .frame(maxHeight: .infinity)
                    VStack(spacing: 14) {
                        Panel { weekdays(habits) }
                        Panel { byGroup().frame(maxHeight: .infinity, alignment: .top) }.frame(maxHeight: .infinity)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
    }

    private func tile(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoCaps(title, size: 10).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.display(32)).foregroundStyle(skin.fg).monospacedDigit()
            Spacer(minLength: 0)
            Text(note).font(.body(12)).foregroundStyle(skin.fgDim).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(skin.fg.opacity(0.05)))
    }

    private func perHabit(_ habits: [Habit]) -> some View {
        let rows = habits.map { h -> (Habit, Int) in
            let c = h.consistency(today: store.today, window: store.settings.consistencyWindow)
            return (h, c.scheduled == 0 ? 0 : Int((Double(c.shown) / Double(c.scheduled) * 100).rounded()))
        }.sorted { $0.0.totalReps > $1.0.totalReps }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                MonoCaps("Per habit", size: 10)
                Spacer()
                MonoCaps("Reps", size: 9).frame(width: 56, alignment: .trailing)
                MonoCaps("\(store.settings.consistencyWindow)d", size: 9).frame(width: 40, alignment: .trailing)
            }
            ForEach(rows, id: \.0.id) { h, pct in
                Button { store.selectedID = h.id; NotificationCenter.default.post(name: .ritualShowTab, object: Tab.stats) } label: {
                    HStack(spacing: 10) {
                        Text(h.name).font(.body(13, .medium)).foregroundStyle(skin.fg).lineLimit(1).frame(width: 120, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(skin.fg.opacity(0.12))
                                Capsule().fill(skin.accent).frame(width: g.size.width * Double(h.journeyReps) / Double(h.journeyLength))
                            }
                        }
                        .frame(height: 4)
                        Text(h.state == .endless ? "\(h.reps)" : "\(h.journeyReps)/\(h.journeyLength)").font(.mono(11)).foregroundStyle(skin.fg).frame(width: 56, alignment: .trailing)
                        Text("\(pct)%").font(.mono(11)).foregroundStyle(skin.fgDim).frame(width: 40, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open \(h.name) stats")
            }
        }
    }

    private func weekdays(_ habits: [Habit]) -> some View {
        // share of scheduled habit-days done, per weekday, over the last 12 weeks
        var done = [Int: Int](), due = [Int: Int]()
        for back in 0..<84 {
            let d = Day.add(-back, to: store.today), w = Day.weekday(d)
            for h in habits where h.isScheduled(d) && d >= Day.start(h.created) {
                due[w, default: 0] += 1
                if h.isDone(on: d) { done[w, default: 0] += 1 }
            }
        }
        let order = Day.orderedWeekdays
        let share = order.map { w in due[w, default: 0] == 0 ? 0 : Double(done[w, default: 0]) / Double(due[w]!) }
        let best = share.max() ?? 0
        let symbols = Calendar.current.shortWeekdaySymbols
        return VStack(alignment: .leading, spacing: 10) {
            MonoCaps("Best days · last 12 weeks", size: 10)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(order.indices, id: \.self) { i in
                    VStack(spacing: 5) {
                        Text("\(Int((share[i] * 100).rounded()))").font(.mono(10, .semibold)).foregroundStyle(skin.fg)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skin.accent.opacity(share[i] == best && best > 0 ? 1 : 0.55))
                            .frame(height: max(3, best == 0 ? 3 : share[i] / best * 70))
                        Text(symbols[order[i] - 1].prefix(2).uppercased()).font(.mono(9.5)).foregroundStyle(skin.fgDim)
                    }
                    .frame(maxWidth: .infinity)
                    .help("\(symbols[order[i] - 1]): \(Int((share[i] * 100).rounded()))% of scheduled habits done")
                }
            }
            .frame(height: 110, alignment: .bottom)
            if best > 0, let i = share.firstIndex(of: best) {
                Text("\(Calendar.current.weekdaySymbols[order[i] - 1]) is your strongest day.").font(.body(12)).foregroundStyle(skin.fgDim)
            }
        }
    }

    private func byGroup() -> some View {
        let rows = store.sections.map { ($0.title, $0.habits.reduce(0) { $0 + $1.totalReps }) }.filter { $0.1 > 0 || store.sections.count == 1 }
        let top = max(1, rows.map(\.1).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            MonoCaps("By group · reps", size: 10)
            ForEach(rows, id: \.0) { name, c in
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(name).font(.body(12.5)).foregroundStyle(skin.fg); Spacer(); Text("\(c)").font(.mono(11)).foregroundStyle(skin.fgDim) }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(skin.fg.opacity(0.1))
                            Capsule().fill(skin.accent).frame(width: g.size.width * Double(c) / Double(top))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }
}

/// 53 week columns × 7 weekday rows; each cell is shaded by how many habits were done that day.
struct AllHeatmap: View {
    @Environment(\.skin) private var skin
    let counts: [Int]   // oldest → today
    let total: Int
    let today: Date
    @State private var hover: String?

    static func color(_ v: Double, _ skin: Skin) -> Color {
        v <= 0 ? skin.fg.opacity(0.08) : skin.accent.opacity(0.25 + 0.75 * v)
    }

    var body: some View {
        GeometryReader { geo in
            let weeks = 53
            let left: CGFloat = 22, top: CGFloat = 16
            let cell = min((geo.size.width - left) / CGFloat(weeks), (geo.size.height - top) / 7)
            let gap = max(1.5, cell * 0.18)
            let order = Day.orderedWeekdays
            let todayRow = order.firstIndex(of: Day.weekday(today)) ?? 0
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    var lastMonth = -1
                    for col in 0..<weeks {
                        for row in 0..<7 {
                            let back = (weeks - 1 - col) * 7 + (todayRow - row)
                            guard back >= 0, back < counts.count else { continue }
                            let v = Double(counts[counts.count - 1 - back]) / Double(max(1, total))
                            let r = CGRect(x: left + CGFloat(col) * cell, y: top + CGFloat(row) * cell, width: cell - gap, height: cell - gap)
                            ctx.fill(Path(roundedRect: r, cornerRadius: (cell - gap) * 0.28), with: .color(Self.color(v, skin)))
                            if row == 0 {
                                let d = Day.add(-back, to: today)
                                let m = Calendar.current.component(.month, from: d)
                                if m != lastMonth && Calendar.current.component(.day, from: d) <= 7 {
                                    ctx.draw(Text(d.formatted(.dateTime.month(.abbreviated)).uppercased()).font(.mono(9)).foregroundColor(skin.fgDim),
                                             at: CGPoint(x: r.minX, y: 5), anchor: .leading)
                                    lastMonth = m
                                }
                            }
                        }
                    }
                    let symbols = Calendar.current.veryShortWeekdaySymbols
                    for row in [1, 3, 5] {
                        ctx.draw(Text(symbols[order[row] - 1]).font(.mono(9)).foregroundColor(skin.fgDim),
                                 at: CGPoint(x: 4, y: top + CGFloat(row) * cell + (cell - gap) / 2), anchor: .leading)
                    }
                }
                if let hover {
                    Text(hover).font(.mono(10)).foregroundStyle(skin.chipFg)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6).fill(skin.chip))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: -22)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let col = Int((p.x - left) / cell), row = Int((p.y - top) / cell)
                    let back = (weeks - 1 - col) * 7 + (todayRow - row)
                    if col >= 0, col < weeks, row >= 0, row < 7, back >= 0, back < counts.count {
                        let d = Day.add(-back, to: today)
                        hover = "\(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(counts[counts.count - 1 - back]) of \(total)"
                    } else { hover = nil }
                case .ended: hover = nil
                }
            }
        }
    }
}
