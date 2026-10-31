import SwiftUI

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit
    var openJourney: () -> Void

    @State private var orbScene = OrbScene()
    @State private var hold: Double = 0
    @State private var holding = false
    @State private var undoing = false
    @State private var holdTask: Task<Void, Never>?
    @State private var wave = false
    @State private var lastQuarter = 0
    @State private var amountText = ""
    @FocusState private var focused: Bool

    private var done: Bool { habit.isDone(on: store.today) }

    var body: some View {
        GeometryReader { geo in
            let orbSize = min(geo.size.width * 0.5, geo.size.height * 0.5, 400)
            VStack(spacing: 0) {
                Spacer(minLength: 8)
                orb(size: orbSize)
                Spacer(minLength: 14)
                caption.padding(.bottom, 16)
                if habit.goalKind == .amount { amountRow.padding(.bottom, 14) }
                WeekRow(habit: habit)
                LevelStrip(habit: habit, action: openJourney).padding(.top, 18)
                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.space, phases: [.down, .up]) { press in
            if press.phase == .down { startHold() } else { endHold() }
            return .handled
        }
        .onAppear {
            orbScene.apply(skin: skin)
            orbScene.setDone(done, animated: false)
            focused = true
        }
        .onChange(of: skin.id) { orbScene.apply(skin: skin) }
        .onChange(of: habit.id) {
            cancelHold()
            orbScene.setDone(done, animated: false)
        }
        .onChange(of: done) { _, d in if d != orbScene.isDone { orbScene.setDone(d, animated: true) } }
    }

    // MARK: Orb

    private func orb(size: CGFloat) -> some View {
        let dust = habit.dust(today: store.today, after: store.settings.dustDays)
        let partial = habit.progress(on: store.today)
        return ZStack {
            // today's partial progress for count / amount goals
            if !done && partial > 0 {
                Circle().trim(from: 0, to: partial)
                    .stroke(skin.accent.opacity(0.45), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 34, height: size + 34)
            }
            // hold ring: accent when checking, runs backwards in grey when unchecking
            Circle()
                .trim(from: undoing ? 1 - hold : 0, to: undoing ? 1 : hold)
                .stroke(undoing ? skin.fgDim : skin.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: size + 34, height: size + 34)
                .opacity(hold > 0 ? 1 : 0)
            Circle()
                .strokeBorder(skin.accent, lineWidth: 3)
                .frame(width: size, height: size)
                .scaleEffect(wave ? 1.7 : 1)
                .opacity(wave ? 0 : 0)
            SceneKitView(scene: orbScene.scene)
                .frame(width: size * 1.4, height: size * 1.4)
                .allowsHitTesting(false)
            if dust > 0 { DustOverlay(amount: dust).frame(width: size, height: size).allowsHitTesting(false) }
            if !done {
                VStack(spacing: 8) {
                    Text(habit.name)
                        .font(.display(size * 0.1))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    let sub = habit.goalKind == .once ? habit.goal : habit.progressText(on: store.today)
                    if !sub.isEmpty { MonoCaps(sub, size: max(10, size * 0.034), color: .white.opacity(0.55)) }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                .padding(.horizontal, size * 0.16)
                .frame(width: size)
                .opacity(1 - hold * 0.6)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
            Circle()
                .fill(Color.white.opacity(0.0001))
                .frame(width: size, height: size)
                .contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !holding { startHold() } }
                    .onEnded { _ in endHold() })
                .contextMenu {
                    if done || partial > 0 { Button("Untick today") { uncheck() } }
                    Button("Show journey") { openJourney() }
                }
                .help(done ? (store.settings.holdToUncheck ? "Done. Hold again to untick." : "Done. Right-click to untick.")
                           : "Press and hold to check (or hold Space)")
        }
        .frame(width: size * 1.4, height: size * 1.4)
        .padding(.vertical, -size * 0.2)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: done)
    }

    private var caption: some View {
        let reps = habit.reps
        let c = habit.consistency(today: store.today, window: store.settings.consistencyWindow)
        let dust = habit.dust(today: store.today, after: store.settings.dustDays)
        let len = habit.journeyLength
        return VStack(spacing: 8) {
            Group {
                if habit.state == .endless {
                    Text(done ? "DONE TODAY · REP \(reps)" : "MASTERED · \(reps) REPS · KEEP GOING")
                } else if done {
                    Text("DONE TODAY · ") + Text("REP \(reps)").foregroundStyle(skin.fg).bold() + Text(" OF \(len)")
                        + Text(store.settings.holdToUncheck ? " · HOLD TO UNDO" : "")
                } else if habit.goalKind == .count {
                    Text("HOLD TO ADD ONE · ") + Text(habit.progressText(on: store.today).uppercased()).foregroundStyle(skin.fg).bold() + Text(" · \(reps) / \(len)")
                } else if !habit.isScheduled(store.today) {
                    Text("REST DAY · \(reps) / \(len) · CHECK ANYWAY IF YOU LIKE")
                } else {
                    Text("HOLD TO CHECK · LEVEL \(habit.level + 1) · ") + Text("\(reps)").foregroundStyle(skin.fg).bold() + Text(" / \(len)")
                }
            }
            .font(.mono(11)).tracking(1.5).foregroundStyle(skin.fgDim).monospacedDigit()

            if dust > 0 {
                MonoCaps("Welcome back · pick up right where you left off", size: 10, color: skin.accent)
            } else if c.scheduled >= 3 {
                MonoCaps("Showed up \(c.shown) of the last \(c.scheduled) days", size: 10)
            }
        }
    }

    /// Amount goals: type what you did today, or hold the orb to log the full goal.
    private var amountRow: some View {
        HStack(spacing: 8) {
            TextField("0", text: $amountText)
                .textFieldStyle(.plain).multilineTextAlignment(.center)
                .font(.mono(14, .bold)).foregroundStyle(skin.fg)
                .frame(width: 70).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(skin.fg.opacity(0.07)))
                .onSubmit(logAmount)
            Text("/ \(Habit.fmt(habit.effectiveTarget)) \(habit.unit)").font(.mono(12)).foregroundStyle(skin.fgDim)
            Button("Log", action: logAmount).buttonStyle(PillButtonStyle())
        }
        .onAppear { amountText = habit.value(on: store.today) > 0 ? Habit.fmt(habit.value(on: store.today)) : "" }
        .onChange(of: habit.id) { amountText = habit.value(on: store.today) > 0 ? Habit.fmt(habit.value(on: store.today)) : "" }
    }

    private func logAmount() {
        guard let v = Double(amountText.replacingOccurrences(of: ",", with: ".")) else { return }
        let wasDone = done
        let beforeLevel = habit.level
        store.setValue(habit.id, v)
        if !wasDone && store.habit(habit.id)?.isDone(on: store.today) == true { celebrate(leveled: (store.habit(habit.id)?.level ?? 0) > beforeLevel) }
    }

    // MARK: Hold logic

    private func startHold() {
        guard !holding else { return }
        if done && !store.settings.holdToUncheck {
            orbScene.nudge()
            Feedback.shared.haptic(.generic)
            return
        }
        undoing = done
        holding = true
        lastQuarter = 0
        Feedback.shared.play(.tick)
        Feedback.shared.haptic(.alignment)
        orbScene.setHold(0)
        let start = Date()
        let duration = max(0.3, store.settings.holdSeconds) * (undoing ? 0.75 : 1)
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            while !Task.isCancelled {
                let p = min(1, Date().timeIntervalSince(start) / duration)
                hold = p
                orbScene.setHold(p)
                let q = Int(p * 4)
                if q > lastQuarter && q < 4 {
                    lastQuarter = q
                    Feedback.shared.play(.tick)
                    Feedback.shared.haptic(.alignment)
                }
                if p >= 1 { undoing ? finishUndo() : complete(); return }
                try? await Task.sleep(for: .milliseconds(12))
            }
        }
    }

    private func endHold() {
        guard holding else { return }
        holding = false
        holdTask?.cancel()
        withAnimation(.easeOut(duration: 0.25)) { hold = 0 }
        orbScene.setHold(0)
    }

    private func cancelHold() {
        holding = false
        holdTask?.cancel()
        hold = 0
        orbScene.setHold(0)
    }

    private func complete() {
        holding = false
        hold = 0
        orbScene.setHold(0)
        let beforeLevel = habit.level
        let becameDone = store.check(habit.id, toast: true)
        if !becameDone {
            // one more step on a count habit
            Feedback.shared.play(.tick)
            Feedback.shared.haptic(.levelChange)
            orbScene.celebrate(skin: skin, big: false, count: 14)
            return
        }
        let leveled = store.levelUp?.habit == habit.id || store.masteryPrompt == habit.id || (store.habit(habit.id)?.level ?? 0) > beforeLevel
        celebrate(leveled: leveled)
    }

    private func celebrate(leveled: Bool) {
        orbScene.setDone(true, animated: true)
        let mode = store.settings.celebration
        if mode != .off { orbScene.celebrate(skin: skin, big: leveled, count: mode == .calm ? 18 : nil) }
        Feedback.shared.play(leveled ? .levelUp : .done)
        Feedback.shared.haptic(.levelChange)
        guard mode == .full else { return }
        wave = false
        withAnimation(.easeOut(duration: 0.7)) { wave = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            Feedback.shared.haptic(.levelChange)
            try? await Task.sleep(for: .milliseconds(600))
            wave = false
        }
    }

    private func finishUndo() {
        holding = false
        hold = 0
        undoing = false
        orbScene.setHold(0)
        uncheck()
    }

    private func uncheck() {
        store.uncheck(habit.id, toast: true)
        orbScene.setDone(false, animated: true)
        Feedback.shared.play(.undo)
        Feedback.shared.haptic(.generic)
    }
}

// MARK: - Week row

struct WeekRow: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach((0..<7).reversed(), id: \.self) { back in
                let day = Day.add(-back, to: store.today)
                let on = habit.isDone(on: day)
                let partial = habit.progress(on: day)
                let scheduled = habit.isScheduled(day)
                VStack(spacing: 8) {
                    Button { store.toggle(habit.id, on: day) } label: {
                        ZStack {
                            if on {
                                Circle().fill(skin.chip)
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(skin.chipFg)
                            } else {
                                Circle().strokeBorder(skin.ring, style: StrokeStyle(lineWidth: 1.5, dash: scheduled ? [] : [2, 3]))
                                if partial > 0 {
                                    Circle().trim(from: 0, to: partial).stroke(skin.fg, lineWidth: 2).rotationEffect(.degrees(-90)).padding(1)
                                }
                                Text("\(Calendar.current.component(.day, from: day))").font(.mono(11)).foregroundStyle(skin.fgDim)
                            }
                        }
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "Click to untick \(day.formatted(.dateTime.weekday(.wide)))" : "Click to tick \(day.formatted(.dateTime.weekday(.wide)))")

                    MonoCaps(back == 0 ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)), size: 10, color: skin.fg)
                    if back == 0 { Capsule().fill(skin.accent).frame(width: 28, height: 2).offset(y: -4) }
                }
                .frame(minWidth: 36)
            }
        }
    }
}

// MARK: - Level strip

struct LevelStrip: View {
    @Environment(\.skin) private var skin
    let habit: Habit
    var action: () -> Void

    var body: some View {
        let level = habit.level
        Button(action: action) {
            HStack(spacing: 16) {
                ForEach(0..<Journey.levelCount, id: \.self) { i in
                    Image(systemName: Journey.symbols[i])
                        .font(.body(14, .bold))
                        .foregroundStyle(i == level && !habit.isMastered ? skin.accent : skin.fg)
                        .opacity(i <= level || habit.isMastered ? 1 : 0.28)
                        .frame(width: 20, height: 20)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Level \(level + 1): \(Journey.names[level]) · open the journey")
    }
}

// MARK: - Dust

/// The orb or monument gathers dust after a stretch away. It never removes progress.
struct DustOverlay: View {
    let amount: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let r = min(size.width, size.height) / 2
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [Color(hex: 0xBFB8A8).opacity(0.0), Color(hex: 0xBFB8A8).opacity(0.38 * amount)]),
                                               center: c, startRadius: r * 0.2, endRadius: r))
                var rng = SplitMix(seed: 7)
                for _ in 0..<Int(140 * amount) {
                    let a = rng.next() * .pi * 2, d = sqrt(rng.next()) * r * 0.98
                    let drift = sin(t * 0.4 + rng.next() * 6) * 2
                    let p = CGPoint(x: c.x + cos(a) * d + drift, y: c.y + sin(a) * d + cos(t * 0.3 + a) * 1.5)
                    let s = 0.8 + rng.next() * 2.2
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x, y: p.y, width: s, height: s)),
                             with: .color(Color(hex: 0xD8D0C0).opacity(0.25 + rng.next() * 0.45 * amount)))
                }
            }
        }
    }
}
