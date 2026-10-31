import SwiftUI

struct HabitEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit
    let isNew: Bool
    @State private var newGroup = ""
    @State private var addingGroup = false
    @State private var confirmDelete = false
    @State private var pickTime = ReminderTime(hour: 8, minute: 0)
    @State private var typedTime = ""
    @State private var typedError = false
    @State private var editingDaysFor: Int?
    @State private var customLength = ""
    @State private var targetText = ""

    private static let presets: [(String, Int, Int)] = [("Wake", 7, 0), ("Lunch", 13, 0), ("After work", 18, 0), ("Wind down", 22, 0)]
    private var use24h: Bool {
        switch store.settings.timeFormat {
        case .h24: return true
        case .h12: return false
        case .system: return !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h").contains("a")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New habit" : "Edit · \(habit.name)").font(.display(22)).foregroundStyle(skin.fg).lineLimit(1)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add habit" : "Save") { save() }
                    .buttonStyle(PillButtonStyle(filled: true))
                    .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            Divider().overlay(skin.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isNew && !store.settings.examples.isEmpty {
                        section("Pick one or write your own") {
                            FlowLayout(spacing: 8) {
                                ForEach(store.settings.examples, id: \.self) { ex in
                                    Button(ex) { habit.name = ex }.buttonStyle(PillButtonStyle(filled: habit.name == ex))
                                }
                            }
                        }
                    }
                    // Two columns: what the habit is on the left, when it happens on the right.
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 18) {
                            section("Habit") {
                                Panel {
                                    VStack(alignment: .leading, spacing: 10) {
                                        field("Name", text: $habit.name, prompt: "Meditate")
                                        field("Note (optional)", text: $habit.goal, prompt: "10 minutes, after coffee")
                                    }
                                }
                            }
                            section("Goal") { goalPanel }
                            section("Group") { groupPicker }
                            section("Journey length") { lengthPanel }
                        }
                        .frame(width: 400)
                        VStack(alignment: .leading, spacing: 18) {
                            section("Schedule") { schedulePanel }
                            section("Reminders") { remindersPanel }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if !isNew {
                        section("Danger zone") {
                            HStack {
                                if confirmDelete {
                                    Text("Delete \(habit.name) and its history?").foregroundStyle(skin.fg)
                                    Spacer()
                                    Button("Keep it") { confirmDelete = false }.buttonStyle(PillButtonStyle())
                                    Button("Delete") { store.delete(habit.id); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                                } else {
                                    Button("Archive to trophy shelf") { store.archive(habit.id); dismiss() }.buttonStyle(PillButtonStyle())
                                    Button("Delete habit…") { confirmDelete = true }.buttonStyle(PillButtonStyle(destructive: true))
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 940, height: 660)
        .background(SkinBackground())
        .onAppear {
            pickTime = store.settings.defaultReminder
            targetText = Habit.fmt(habit.target)
        }
    }

    // MARK: Sections

    private var goalPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 8) {
                    kindButton("Once a day", .once)
                    kindButton("Several times a day", .count)
                    kindButton("An amount", .amount)
                }
                if habit.goalKind != .once {
                    HStack(spacing: 8) {
                        TextField(habit.goalKind == .count ? "3" : "10", text: $targetText)
                            .textFieldStyle(.plain).font(.mono(15, .bold)).foregroundStyle(skin.fg)
                            .multilineTextAlignment(.center).frame(width: 70).padding(8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(skin.fg.opacity(0.07)))
                            .onChange(of: targetText) { _, v in if let d = Double(v.replacingOccurrences(of: ",", with: ".")), d > 0 { habit.target = d } }
                        if habit.goalKind == .count {
                            Text("times a day").foregroundStyle(skin.fg)
                        } else {
                            TextField("pages", text: $habit.unit).textFieldStyle(.plain).font(.body(14, .semibold))
                                .foregroundStyle(skin.fg).frame(width: 120).padding(8)
                                .background(RoundedRectangle(cornerRadius: 9).fill(skin.fg.opacity(0.07)))
                            Text("a day").foregroundStyle(skin.fgDim)
                        }
                    }
                }
                Text(habit.goalKind == .once ? "One hold on the orb completes the day."
                     : habit.goalKind == .count ? "Each hold adds one. The ring fills in steps, and the day counts as a rep when it's full."
                     : "Type what you did on the Today screen, or hold the orb to log the full amount.")
                    .font(.body(12)).foregroundStyle(skin.fgDim)
            }
        }
    }

    private func kindButton(_ label: String, _ kind: GoalKind) -> some View {
        Button(label) {
            habit.goalKind = kind
            if kind == .count && habit.target < 2 { habit.target = 3 }
            if kind == .amount && habit.target < 2 { habit.target = 10 }
            targetText = Habit.fmt(habit.target)
        }
        .buttonStyle(PillButtonStyle(filled: habit.goalKind == kind))
    }

    private var groupPicker: some View {
        FlowLayout(spacing: 8) {
            Button("None") { habit.groupID = nil }.buttonStyle(PillButtonStyle(filled: habit.groupID == nil))
            ForEach(store.groups) { g in
                Button(g.name) { habit.groupID = g.id }.buttonStyle(PillButtonStyle(filled: habit.groupID == g.id))
            }
            if addingGroup {
                TextField("Group name", text: $newGroup)
                    .textFieldStyle(.plain).font(.body(13, .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().strokeBorder(skin.accent))
                    .frame(width: 150)
                    .onSubmit {
                        let n = newGroup.trimmingCharacters(in: .whitespaces)
                        if !n.isEmpty { habit.groupID = store.addGroup(n) }
                        newGroup = ""; addingGroup = false
                    }
                    .onExitCommand { addingGroup = false }
            } else {
                Button { addingGroup = true } label: { Label("New group", systemImage: "plus") }.buttonStyle(PillButtonStyle())
            }
        }
    }

    private var schedulePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(Day.orderedWeekdays, id: \.self) { d in
                        let on = habit.weekdays.contains(d)
                        Button(Calendar.current.shortWeekdaySymbols[d - 1]) {
                            if on && habit.weekdays.count > 1 { habit.weekdays.remove(d) } else { habit.weekdays.insert(d) }
                        }
                        .buttonStyle(DayPill(on: on, width: 52))
                    }
                }
                HStack(spacing: 8) {
                    Button("Every day") { habit.weekdays = Set(1...7) }.buttonStyle(PillButtonStyle())
                    Button("Weekdays") { habit.weekdays = [2, 3, 4, 5, 6] }.buttonStyle(PillButtonStyle())
                    Button("Weekends") { habit.weekdays = [1, 7] }.buttonStyle(PillButtonStyle())
                }
                Text("Unscheduled days never count against you. You can still check in on them.")
                    .font(.body(12)).foregroundStyle(skin.fgDim)
            }
        }
    }

    private var remindersPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Send reminders", isOn: $habit.remindersOn).toggleStyle(.switch).tint(skin.accent).foregroundStyle(skin.fg)
                VStack(alignment: .leading, spacing: 14) {
                    if habit.reminders.isEmpty {
                        Text("No reminder times yet.").font(.body(12)).foregroundStyle(skin.fgDim)
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(Array(habit.reminders.sorted { $0.id < $1.id }.enumerated()), id: \.element.id) { _, t in
                            HStack(spacing: 0) {
                                Button { editingDaysFor = editingDaysFor == t.id ? nil : t.id } label: {
                                    HStack(spacing: 6) {
                                        Text(t.label(store.settings.timeFormat))
                                        if !t.weekdays.isEmpty {
                                            Text(daysShort(t.weekdays)).font(.mono(10)).opacity(0.75)
                                        }
                                    }
                                    .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                .help("Set which days this time applies to")
                                Button { habit.reminders.removeAll { $0.id == t.id }; if editingDaysFor == t.id { editingDaysFor = nil } } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .heavy)).padding(.trailing, 12).padding(.leading, 4).padding(.vertical, 9)
                                }
                                .buttonStyle(.plain)
                                .help("Remove \(t.label)")
                            }
                            .font(.body(13, .semibold))
                            .foregroundStyle(skin.onAccent)
                            .background(Capsule().fill(skin.accent))
                        }
                    }
                    if let tid = editingDaysFor, let i = habit.reminders.firstIndex(where: { $0.id == tid }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(habit.reminders[i].label(store.settings.timeFormat)) applies on").font(.body(12, .semibold)).foregroundStyle(skin.fg)
                            HStack(spacing: 6) {
                                ForEach(Day.orderedWeekdays.filter(habit.weekdays.contains), id: \.self) { d in
                                    let set = habit.reminders[i].weekdays
                                    let on = set.isEmpty || set.contains(d)
                                    Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) {
                                        var s = set.isEmpty ? habit.weekdays : set
                                        if on { s.remove(d) } else { s.insert(d) }
                                        if s.isEmpty { return }
                                        habit.reminders[i].weekdays = s == habit.weekdays ? [] : s
                                    }
                                    .buttonStyle(DayPill(on: on, compact: true))
                                }
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(skin.fg.opacity(0.05)))
                    }
                    FlowLayout(spacing: 10) {
                        TimePicker(time: $pickTime, use24h: use24h)
                        Button { add(pickTime) } label: { Label("Add time", systemImage: "plus") }.buttonStyle(PillButtonStyle(filled: true))
                        HStack(spacing: 8) {
                        Text("or type").font(.body(12)).foregroundStyle(skin.fgDim)
                        TextField("6:45pm", text: $typedTime)
                            .textFieldStyle(.plain).font(.body(14, .semibold)).foregroundStyle(skin.fg)
                            .padding(9).frame(width: 110)
                            .background(RoundedRectangle(cornerRadius: 9).fill(skin.fg.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(typedError ? Color(hex: 0xEF6A5E) : .clear, lineWidth: 1.5))
                            .onSubmit {
                                if let t = ReminderTime.parse(typedTime) { add(t); typedTime = ""; typedError = false } else { typedError = true }
                            }
                            .onChange(of: typedTime) { typedError = false }
                        }
                    }
                    if typedError {
                        Text("Couldn't read that time. Try \"7:15am\", \"19:30\" or \"9p\".").font(.body(12)).foregroundStyle(Color(hex: 0xEF6A5E))
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(Self.presets, id: \.0) { p in
                            let t = ReminderTime(hour: p.1, minute: p.2)
                            Button("\(p.0) · \(t.label(store.settings.timeFormat))") { add(t) }.buttonStyle(PillButtonStyle())
                        }
                    }
                    Text("Use the arrows, scroll over a digit, or type. Click a time to choose its days.")
                        .font(.body(12)).foregroundStyle(skin.fgDim)
                }
                .opacity(habit.remindersOn ? 1 : 0.4)
                .disabled(!habit.remindersOn)
                field("Reminder text (optional)", text: $habit.reminderNote, prompt: "Shown in the banner instead of the rep count")
            }
        }
    }

    private var lengthPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach([30, 60, 90], id: \.self) { n in
                        Button("\(n) reps") { habit.journeyLength = n; customLength = "" }.buttonStyle(PillButtonStyle(filled: habit.journeyLength == n))
                    }
                    TextField("Custom", text: $customLength)
                        .textFieldStyle(.plain).font(.mono(13, .bold)).foregroundStyle(skin.fg).multilineTextAlignment(.center)
                        .frame(width: 80).padding(8)
                        .background(Capsule().fill(![30, 60, 90].contains(habit.journeyLength) ? skin.accent.opacity(0.25) : skin.fg.opacity(0.07)))
                        .onSubmit { if let n = Int(customLength), (8...365).contains(n) { habit.journeyLength = n } }
                }
                Text("Always 8 levels; they stretch to fit. Currently \(habit.journeyLength) reps: " + habit.levelReps.map(String.init).joined(separator: " · "))
                    .font(.body(12)).foregroundStyle(skin.fgDim)
            }
        }
        .onAppear { if ![30, 60, 90].contains(habit.journeyLength) { customLength = String(habit.journeyLength) } }
    }

    // MARK: Helpers

    private func daysShort(_ s: Set<Int>) -> String {
        Day.orderedWeekdays.filter(s.contains).map { Calendar.current.veryShortWeekdaySymbols[$0 - 1] }.joined()
    }

    private func add(_ t: ReminderTime) {
        if !habit.reminders.contains(where: { $0.id == t.id }) { habit.reminders.append(ReminderTime(hour: t.hour, minute: t.minute)) }
        habit.reminders.sort { $0.id < $1.id }
        habit.remindersOn = true
    }

    private func save() {
        habit.name = habit.name.trimmingCharacters(in: .whitespaces)
        if habit.goalKind == .once { habit.target = 1 }
        if isNew { store.add(habit) } else { store.update(habit) }
        dismiss()
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { MonoCaps(title, size: 10); c() }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.body(11, .semibold)).foregroundStyle(skin.fgDim)
            TextField(prompt, text: text).textFieldStyle(.plain).font(.body(16, .semibold)).foregroundStyle(skin.fg)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(skin.fg.opacity(0.06)))
        }
    }
}

struct DayPill: ButtonStyle {
    @Environment(\.skin) private var skin
    let on: Bool
    var compact = false
    var width: CGFloat = 50
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body(12, .semibold))
            .frame(width: compact ? 30 : width, height: compact ? 26 : 34)
            .foregroundStyle(on ? skin.onAccent : skin.fgDim)
            .background(Capsule().fill(on ? skin.accent : skin.fg.opacity(0.07)))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Wraps children onto new lines like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 500
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w && x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing; row = max(row, sz.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > b.maxX && x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}
