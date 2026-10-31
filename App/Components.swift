import SwiftUI

// MARK: - Journey bar

/// A video-player style bar for one habit's journey. Each level is a "chapter" sized by its reps.
/// The filled part is reps done; a lighter segment shows where the current pace lands in two weeks.
struct JourneyBar: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit
    @State private var hoverX: CGFloat?

    private var reps: Int { habit.journeyReps }
    private var length: Int { habit.journeyLength }
    private var projected: Int {
        guard store.settings.showPace, !habit.isMastered else { return reps }
        return min(length, reps + Int((habit.pace(today: store.today) * 14).rounded()))
    }

    var body: some View {
        let chapters = habit.levelReps
        let level = habit.level
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                (Text("JOURNEY · ") + Text("\(reps)").foregroundStyle(skin.fg).bold() + Text(" / \(length) · LEVEL \(level + 1) \(Journey.names[level].uppercased())"))
                Spacer(minLength: 12)
                if habit.isMastered {
                    Text("GEM PLACED")
                } else if store.settings.showPace, let eta = habit.projectedFinish(today: store.today) {
                    Text("AT YOUR PACE: GEM AROUND ") + Text(eta.formatted(.dateTime.day().month(.abbreviated)).uppercased()).foregroundStyle(skin.fg).bold()
                }
            }
            .font(.mono(10.5)).tracking(1.1).foregroundStyle(skin.fgDim).lineLimit(1).minimumScaleFactor(0.7)

            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(chapters.count - 1)
                let widths = chapters.map { usable * CGFloat($0) / CGFloat(length) }
                let tall = hoverX != nil
                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        ForEach(chapters.indices, id: \.self) { i in
                            let start = Journey.levelStart(i, length: length)
                            let f = Double(max(0, min(chapters[i], reps - start))) / Double(chapters[i])
                            let p = Double(max(0, min(chapters[i], projected - start))) / Double(chapters[i])
                            ZStack(alignment: .leading) {
                                Capsule().fill(skin.fg.opacity(0.14))
                                Capsule().fill(skin.fg.opacity(0.28)).frame(width: widths[i] * p)
                                Capsule().fill(skin.accent).frame(width: widths[i] * f)
                            }
                            .frame(width: widths[i], height: tall ? 7 : 4)
                        }
                    }
                    .frame(height: 18)
                    Circle().fill(skin.accent)
                        .overlay(Circle().stroke(skin.accent.opacity(0.3), lineWidth: 6))
                        .frame(width: 13, height: 13)
                        .scaleEffect(tall ? 1.2 : 1)
                        .offset(x: x(forRep: reps, widths: widths, gap: gap) - 6.5)
                    if let hx = hoverX {
                        Rectangle().fill(skin.fg.opacity(0.6)).frame(width: 2, height: 14).offset(x: hx - 1)
                        tooltip(rep: rep(at: hx, widths: widths, gap: gap))
                            .fixedSize()
                            .offset(x: min(max(0, hx - 80), geo.size.width - 160), y: -40)
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hoverX = max(0, min(geo.size.width, p.x))
                    case .ended: hoverX = nil
                    }
                }
                .animation(.easeOut(duration: 0.12), value: tall)
            }
            .frame(height: 18)

            GeometryReader { geo in
                let gap: CGFloat = 3
                let usable = geo.size.width - gap * CGFloat(chapters.count - 1)
                HStack(spacing: gap) {
                    ForEach(chapters.indices, id: \.self) { i in
                        Text(i == level || i == chapters.count - 1 ? Journey.names[i].uppercased() : "")
                            .font(.mono(9)).tracking(0.8)
                            .foregroundStyle(i == level ? skin.accent : skin.fgDim)
                            .lineLimit(1).fixedSize()
                            .frame(width: usable * CGFloat(chapters[i]) / CGFloat(length), alignment: .leading)
                    }
                }
            }
            .frame(height: 12)
        }
    }

    private func x(forRep r: Int, widths: [CGFloat], gap: CGFloat) -> CGFloat {
        var x: CGFloat = 0
        for (i, n) in habit.levelReps.enumerated() {
            let start = Journey.levelStart(i, length: length)
            if r <= start + n { return x + widths[i] * CGFloat(r - start) / CGFloat(n) }
            x += widths[i] + gap
        }
        return x - gap
    }

    private func rep(at px: CGFloat, widths: [CGFloat], gap: CGFloat) -> Int {
        var x: CGFloat = 0
        for (i, n) in habit.levelReps.enumerated() {
            if px <= x + widths[i] + gap / 2 {
                let f = max(0, min(1, (px - x) / widths[i]))
                return max(1, Journey.levelStart(i, length: length) + Int((f * CGFloat(n)).rounded(.up)))
            }
            x += widths[i] + gap
        }
        return length
    }

    private func tooltip(rep: Int) -> some View {
        let dates = habit.journeyDates
        let lv = Journey.level(forReps: rep - 1, length: length)
        let when: String = rep <= dates.count
            ? dates[rep - 1].formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            : rep <= projected ? "Projected · next 2 weeks" : "Not yet"
        return VStack(alignment: .leading, spacing: 2) {
            Text("Rep \(rep) · \(Journey.names[lv])").font(.body(12, .bold))
            Text(when).font(.mono(10))
        }
        .foregroundStyle(skin.chipFg)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(skin.chip))
        .allowsHitTesting(false)
    }
}

// MARK: - Day pane

/// The right-hand pane: the whole day at a glance, across every habit.
struct DayPane: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin

    var body: some View {
        let habits = store.visibleHabits
        let n = max(1, habits.count)
        let done = store.todayDone
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    header("Today", store.today.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(skin.fg.opacity(0.12), lineWidth: 7)
                            Circle().trim(from: 0, to: Double(done) / Double(n))
                                .stroke(skin.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
                        }
                        .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 3) {
                            (Text("\(done)").font(.display(30)) + Text("/\(habits.count)").font(.display(16)).foregroundStyle(skin.fgDim))
                                .foregroundStyle(skin.fg).monospacedDigit()
                            Text(done >= habits.count && !habits.isEmpty ? "All done. Nice." : "\(habits.count - done) left today")
                                .font(.body(12)).foregroundStyle(skin.fgDim)
                        }
                    }
                }

                tasksBlock

                if !store.sections.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        header("Groups", "")
                        ForEach(store.sections) { s in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(s.title).font(.body(12.5, .medium)).foregroundStyle(skin.fg)
                                    Spacer()
                                    Text("\(s.habits.filter { $0.isDone(on: store.today) }.count)/\(s.habits.count)").font(.mono(10.5)).foregroundStyle(skin.fgDim)
                                }
                                HStack(spacing: 2) {
                                    ForEach(s.habits) { h in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(h.isDone(on: store.today) ? skin.accent : skin.fg.opacity(0.13))
                                            .overlay(alignment: .leading) {
                                                if !h.isDone(on: store.today) && h.progress(on: store.today) > 0 {
                                                    GeometryReader { g in
                                                        RoundedRectangle(cornerRadius: 2).fill(skin.accent.opacity(0.55))
                                                            .frame(width: g.size.width * h.progress(on: store.today))
                                                    }
                                                }
                                            }
                                    }
                                }
                                .frame(height: 6)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    header("Last 7 days · all habits", "")
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach((0..<7).reversed(), id: \.self) { back in
                            let d = Day.add(-back, to: store.today)
                            let c = habits.filter { $0.isDone(on: d) }.count
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(skin.accent.opacity(back == 0 ? 1 : 0.75))
                                    .frame(height: max(2, CGFloat(c) / CGFloat(n) * 42))
                                Text(d.formatted(.dateTime.weekday(.narrow))).font(.mono(8.5)).foregroundStyle(skin.fgDim)
                            }
                            .frame(maxWidth: .infinity)
                            .help("\(d.formatted(.dateTime.weekday(.wide).day().month())): \(c) of \(habits.count)")
                        }
                    }
                    .frame(height: 58, alignment: .bottom)
                }

                VStack(alignment: .leading, spacing: 9) {
                    header("All journeys", "\(habits.reduce(0) { $0 + $1.totalReps }) reps")
                    ForEach(habits) { h in
                        Button { store.selectedID = h.id } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(h.name).font(.body(12)).foregroundStyle(skin.fg).lineLimit(1)
                                    Spacer()
                                    Text(h.state == .endless ? "\(h.reps)" : "\(h.journeyReps)/\(h.journeyLength)").font(.mono(10)).foregroundStyle(skin.fgDim)
                                }
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(skin.fg.opacity(0.12))
                                        Capsule().fill(h.id == store.selected?.id ? skin.accent : skin.fg)
                                            .frame(width: g.size.width * Double(h.journeyReps) / Double(h.journeyLength))
                                    }
                                }
                                .frame(height: 3)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                let upcoming = comingUp
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Coming up", "habits · tasks")
                        ForEach(Array(upcoming.enumerated()), id: \.offset) { i, r in
                            HStack(spacing: 10) {
                                Group {
                                    if r.task { TaskCheckbox(done: false, priority: r.priority, size: 13) }
                                    else { Image(systemName: i == 0 ? "bell.fill" : "bell").font(.system(size: 12, weight: .semibold)) }
                                }
                                .foregroundStyle(i == 0 ? skin.accent : skin.fgDim).frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.name).font(.body(12.5, i == 0 ? .semibold : .regular)).foregroundStyle(skin.fg).lineLimit(1)
                                    MonoCaps(when(r.at), size: 9)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(i == 0 ? skin.card : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(i == 0 ? skin.line : .clear))
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.never)
        .background(skin.sidebar.opacity(0.55))
    }

    private func header(_ a: String, _ b: String) -> some View {
        HStack { MonoCaps(a, size: 10); Spacer(); MonoCaps(b, size: 10) }
    }

    /// Next reminders across habits and tasks, soonest first.
    private var comingUp: [(name: String, at: Date, task: Bool, priority: Int)] {
        let habits = store.upcomingReminders(limit: 4).map { ($0.habit.name, $0.at, false, 0) }
        let horizon = Day.add(8, to: store.today)
        let tasks = store.tasks.filter { !$0.isDone }.compactMap { t in t.remindAt.map { (t.title, $0, true, t.priority) } }
            .filter { $0.1 > .now && $0.1 < horizon }
        return (habits + tasks).sorted { $0.1 < $1.1 }.prefix(4).map { (name: $0.0, at: $0.1, task: $0.2, priority: $0.3) }
    }

    /// Tasks due today (and late ones): a count, a segment per task, and a way in.
    @ViewBuilder private var tasksBlock: some View {
        let d = store.taskDay
        if d.total > 0 || !store.tasks.isEmpty {
            Button {
                store.taskView = .today; store.taskLabelFilter = nil
                NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    header("Tasks today", d.late > 0 ? "\(d.late) late" : "")
                    HStack(alignment: .firstTextBaseline) {
                        (Text("\(d.done)").font(.display(24)) + Text(" of \(d.total)").font(.display(14)).foregroundStyle(skin.fgDim))
                            .foregroundStyle(skin.fg).monospacedDigit()
                        Spacer()
                        Text(d.total == 0 ? "Nothing due" : d.done == d.total ? "All done" : "\(d.total - d.done) open")
                            .font(.body(12)).foregroundStyle(d.late > 0 ? PriorityColor.color(1, dark: skin.dark) : skin.fgDim)
                    }
                    if d.total > 0 {
                        HStack(spacing: 2) {
                            ForEach(0..<d.total, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2).fill(i < d.done ? skin.accent : skin.fg.opacity(0.13))
                            }
                        }
                        .frame(height: 6)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open today's tasks")
        }
    }

    private func when(_ d: Date) -> String {
        let time = d.formatted(date: .omitted, time: .shortened)
        let days = Day.between(store.today, d)
        return days == 0 ? "Today · \(time)" : days == 1 ? "Tomorrow · \(time)" : "\(d.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
    }
}

// MARK: - Time picker

/// Hour / minute fields with arrows and scroll, AM/PM, plus a free-text field ("6:45pm").
struct TimePicker: View {
    @Environment(\.skin) private var skin
    @Binding var time: ReminderTime
    var use24h: Bool
    @State private var hourText = ""
    @State private var minuteText = ""

    var body: some View {
        HStack(spacing: 2) {
            column(text: $hourText, up: { step(hours: 1) }, down: { step(hours: -1) }, commit: commitHour)
            Text(":").font(.mono(22, .bold)).foregroundStyle(skin.fgDim)
            column(text: $minuteText, up: { step(minutes: 5) }, down: { step(minutes: -5) }, commit: commitMinute)
            if !use24h {
                VStack(spacing: 3) {
                    ampm("AM", on: time.hour < 12) { if time.hour >= 12 { time.hour -= 12 } }
                    ampm("PM", on: time.hour >= 12) { if time.hour < 12 { time.hour += 12 } }
                }
                .padding(.leading, 4)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(skin.fg.opacity(0.07)))
        .onAppear(perform: sync)
        .onChange(of: time) { sync() }
    }

    private func column(text: Binding<String>, up: @escaping () -> Void, down: @escaping () -> Void, commit: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: up) { Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold)).frame(width: 46, height: 18) }
                .buttonStyle(.plain).foregroundStyle(skin.fgDim)
            TextField("", text: text)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.mono(22, .bold)).foregroundStyle(skin.fg)
                .frame(width: 46)
                .onSubmit(commit)
                .onChange(of: text.wrappedValue) { _, v in if v.count >= 2 { commit() } }
            Button(action: down) { Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).frame(width: 46, height: 18) }
                .buttonStyle(.plain).foregroundStyle(skin.fgDim)
        }
        .background(ScrollCatcher { dy in dy > 0 ? up() : down() })
    }

    private func ampm(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(on ? skin.accent : skin.fg.opacity(0.08))
                Text(label).font(.mono(11, .bold)).foregroundColor(on ? skin.onAccent : skin.fgDim)
            }
            .frame(width: 34, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label == "AM" ? "Morning" : "Afternoon / evening")
    }

    private func sync() {
        let h = use24h ? time.hour : (time.hour % 12 == 0 ? 12 : time.hour % 12)
        hourText = String(format: "%02d", h)
        minuteText = String(format: "%02d", time.minute)
    }

    private func step(hours: Int = 0, minutes: Int = 0) {
        var total = time.hour * 60 + time.minute
        if minutes != 0 {
            let snapped = minutes > 0 ? (time.minute / 5 + 1) * 5 : ((time.minute + 4) / 5 - 1) * 5
            total = time.hour * 60 + snapped
        }
        total += hours * 60
        total = (total % 1440 + 1440) % 1440
        time.hour = total / 60
        time.minute = total % 60
    }

    private func commitHour() {
        guard let v = Int(hourText.filter(\.isNumber)) else { sync(); return }
        if use24h { time.hour = min(23, max(0, v)) } else {
            let h = min(12, max(1, v)) % 12
            time.hour = time.hour >= 12 ? h + 12 : h
        }
        sync()
    }

    private func commitMinute() {
        guard let v = Int(minuteText.filter(\.isNumber)) else { sync(); return }
        time.minute = min(59, max(0, v))
        sync()
    }
}

/// Reports vertical scroll-wheel deltas over its area.
struct ScrollCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSView { V(onScroll) }
    func updateNSView(_ v: NSView, context: Context) { (v as? V)?.onScroll = onScroll }
    final class V: NSView {
        var onScroll: (CGFloat) -> Void
        private var acc: CGFloat = 0
        init(_ f: @escaping (CGFloat) -> Void) { onScroll = f; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func scrollWheel(with e: NSEvent) {
            acc += e.scrollingDeltaY
            if abs(acc) > (e.hasPreciseScrollingDeltas ? 14 : 0.5) { onScroll(acc); acc = 0 }
        }
    }
}

// MARK: - Toast

struct ToastView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let toast: Store.Toast

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message).font(.body(13, .medium)).foregroundStyle(skin.chipFg)
            if toast.undo != nil {
                Button("Undo") { store.undo(toast) }
                    .buttonStyle(.plain)
                    .font(.body(12, .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 8).fill(skin.accent))
                    .foregroundStyle(skin.onAccent)
                    .keyboardShortcut("z", modifiers: .command)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(skin.chip))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(5))
            if store.toast?.id == toast.id { store.toast = nil }
        }
    }
}

// MARK: - Habit menu

/// The same actions for the ⋯ button in the top bar and each sidebar row.
struct HabitMenuItems: View {
    @Environment(Store.self) private var store
    let habit: Habit
    var edit: () -> Void
    @Binding var confirmDelete: Habit?

    var body: some View {
        let done = habit.isDone(on: store.today)
        Button(done ? "Untick today" : "Tick today") { store.toggle(habit.id) }
        Button("Edit habit…", action: edit)
        Menu("Move to group") {
            Button("None") { store.move(habit.id, to: nil) }
            ForEach(store.groups) { g in Button(g.name) { store.move(habit.id, to: g.id) } }
        }
        Button("Move up") { store.nudge(habit.id, by: -1) }
        Button("Move down") { store.nudge(habit.id, by: 1) }
        Divider()
        Button("Archive to trophy shelf") { store.archive(habit.id) }
        Button("Delete habit…", role: .destructive) { confirmDelete = habit }
    }
}
