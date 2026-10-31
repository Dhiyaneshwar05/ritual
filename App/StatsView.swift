import SwiftUI

struct StatsView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit
    @State private var year = Calendar.current.component(.year, from: .now)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                // Row 1: the two charts at the same height. Row 2: six uniform cards across the full width.
                HStack(alignment: .top, spacing: 18) {
                    Panel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                MonoCaps("Year field")
                                Spacer()
                                Button { year -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(IconButtonStyle())
                                Text(String(year)).font(.display(22)).foregroundStyle(skin.fg).monospacedDigit()
                                Button { year += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(IconButtonStyle())
                                    .disabled(year >= Calendar.current.component(.year, from: store.today))
                            }
                            YearField(habit: habit, year: year)
                                .frame(maxHeight: .infinity)
                            HStack {
                                MonoCaps("\(yearCount) reps in \(String(year))", size: 9)
                                Spacer()
                                MonoCaps("▲ done · · not yet", size: 9)
                            }
                        }
                        .frame(height: Self.chartHeight)
                    }
                    Panel {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                MonoCaps("Climb")
                                Spacer()
                                MonoCaps("Level \(habit.level + 1) · \(Journey.names[habit.level])", color: skin.accent)
                            }
                            ClimbChart(reps: habit.journeyReps, length: habit.journeyLength)
                                .frame(maxHeight: .infinity)
                            HStack {
                                MonoCaps("\(habit.journeyReps) of \(habit.journeyLength) reps", size: 9)
                                Spacer()
                                MonoCaps("Each flag is a level", size: 9)
                            }
                        }
                        .frame(height: Self.chartHeight)
                    }
                }
                cards
            }
            .padding(28)
        }
        .scrollContentBackground(.hidden)
    }

    private static let chartHeight: CGFloat = 400

    private var yearCount: Int {
        let cal = Calendar.current
        guard let a = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let b = cal.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        return habit.count(from: a, to: b)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(habit.name).font(.display(34)).foregroundStyle(skin.fg)
                Text([habit.goalText.isEmpty ? nil : habit.goalText, habit.scheduleText,
                      habit.reminders.isEmpty ? nil : "at " + habit.reminders.map(\.label).joined(separator: ", ")]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.body(13)).foregroundStyle(skin.fgDim)
            }
            Spacer()
            Text("\(habit.state == .endless ? habit.reps : habit.journeyReps)").font(.display(44)).foregroundStyle(skin.fg).monospacedDigit()
            MonoCaps(habit.state == .endless ? "reps" : "/ \(habit.journeyLength)")
        }
    }

    private var cards: some View {
        let t = store.today
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: t)?.start ?? t
        let monthStart = cal.dateInterval(of: .month, for: t)?.start ?? t
        let yearStart = cal.dateInterval(of: .year, for: t)?.start ?? t
        let lastWeek = habit.count(from: Day.add(-7, to: weekStart), to: Day.add(-1, to: weekStart))
        let lastMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let thisWeek = habit.count(from: weekStart, to: t)
        let thisMonth = habit.count(from: monthStart, to: t)
        let lastMonth = habit.count(from: lastMonthStart, to: Day.add(-1, to: monthStart))
        let c = habit.consistency(today: t, window: store.settings.consistencyWindow)
        let pct = c.scheduled == 0 ? 0 : Int((Double(c.shown) / Double(c.scheduled) * 100).rounded())
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
            StatCard(title: "This week", value: "\(thisWeek)", note: delta(thisWeek - lastWeek, "last week"))
            StatCard(title: "This month", value: "\(thisMonth)", note: delta(thisMonth - lastMonth, "last month"))
            StatCard(title: "Showed up", value: "\(pct)%", note: "\(c.shown) of the last \(c.scheduled) days", ring: Double(pct) / 100)
            StatCard(title: "This year", value: "\(habit.count(from: yearStart, to: t))",
                     note: habit.firstDone.map { "Since " + $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "No reps yet")
            StatCard(title: "To the gem", value: "\(max(0, habit.journeyLength - habit.journeyReps))", note: habit.isMastered ? "Mastered" : "reps left")
            StatCard(title: "Round", value: "\(habit.round + 1)", note: habit.state == .endless ? "Mastered · keeps counting" : "of this habit")
        }
    }

    private func delta(_ d: Int, _ label: String) -> String {
        d == 0 ? "Same as \(label)" : (d > 0 ? "+\(d)" : "\(d)") + " vs \(label)"
    }
}

struct StatCard: View {
    @Environment(\.skin) private var skin
    let title: String
    let value: String
    let note: String
    var ring: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoCaps(title, size: 10).lineLimit(1)
            HStack(alignment: .center) {
                Text(value).font(.display(34)).foregroundStyle(skin.fg).monospacedDigit()
                Spacer()
                if let ring {
                    ZStack {
                        Circle().stroke(skin.fg.opacity(0.12), lineWidth: 5)
                        Circle().trim(from: 0, to: ring).stroke(skin.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 34, height: 34)
                }
            }
            Spacer(minLength: 0)
            Text(note).font(.body(12, .medium)).foregroundStyle(skin.accent).lineLimit(1).minimumScaleFactor(0.85)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(skin.fg.opacity(0.05)))
    }
}

/// Months across, days down. Done days are faceted shards; missed days are quiet dots.
struct YearField: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit
    let year: Int
    @State private var hover: String?

    var body: some View {
        GeometryReader { geo in
            let colW = geo.size.width / 12
            let top: CGFloat = 22
            let rowH = (geo.size.height - top - 4) / 31
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let cal = Calendar.current
                    let todayKey = Day.key(store.today)
                    let letters = Array("JFMAMJJASOND")
                    for m in 0..<12 {
                        let x = colW * (CGFloat(m) + 0.5)
                        ctx.draw(Text(String(letters[m])).font(.mono(10)).foregroundColor(skin.fg), at: CGPoint(x: x, y: 8))
                        guard let first = cal.date(from: DateComponents(year: year, month: m + 1, day: 1)),
                              let range = cal.range(of: .day, in: .month, for: first) else { continue }
                        for d in range {
                            let date = cal.date(from: DateComponents(year: year, month: m + 1, day: d))!
                            let k = Day.key(date)
                            let y = top + rowH * (CGFloat(d) - 0.5)
                            if (habit.log[k] ?? 0) >= habit.effectiveTarget {
                                let h = min(rowH * 1.05, 12), w = h * 0.75
                                var a = Path(); a.move(to: CGPoint(x: x, y: y - h * 0.6)); a.addLine(to: CGPoint(x: x + w / 2, y: y + h * 0.4)); a.addLine(to: CGPoint(x: x - w / 2, y: y + h * 0.4)); a.closeSubpath()
                                var b = Path(); b.move(to: CGPoint(x: x, y: y - h * 0.6)); b.addLine(to: CGPoint(x: x + w / 2, y: y + h * 0.4)); b.addLine(to: CGPoint(x: x, y: y + h * 0.2)); b.closeSubpath()
                                ctx.fill(a, with: .color(skin.shardA))
                                ctx.fill(b, with: .color(skin.shardB))
                            } else {
                                let isToday = k == todayKey
                                let r: CGFloat = isToday ? 2.6 : 1.2
                                let future = k > todayKey
                                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                         with: .color(isToday ? skin.accent : skin.fg.opacity(future ? 0.12 : 0.3)))
                            }
                        }
                    }
                }
                if let hover {
                    MonoCaps(hover, size: 10, color: skin.fg)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(skin.bgBottom.opacity(0.95)))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .offset(y: -2)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    let m = Int(p.x / colW), d = Int((p.y - top) / rowH) + 1
                    if let date = Calendar.current.date(from: DateComponents(year: year, month: m + 1, day: d)),
                       Calendar.current.component(.month, from: date) == m + 1 {
                        hover = date.formatted(.dateTime.day().month(.abbreviated)) + (habit.isDone(on: date) ? " · done" : "")
                    } else { hover = nil }
                case .ended: hover = nil
                }
            }
        }
    }
}
