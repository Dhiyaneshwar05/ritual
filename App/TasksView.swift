import SwiftUI

// MARK: - Colours

/// Label colours: a fixed set that reads on all six skins, with a deeper step for light ones.
enum LabelPalette {
    static let names = ["Blue", "Green", "Amber", "Violet", "Teal", "Rose", "Lime", "Slate"]
    private static let onDark: [UInt32] = [0x7AA7FF, 0x5FD08A, 0xE8A86A, 0xD58CF0, 0x5AD1C8, 0xFF7E9D, 0xB5D65A, 0xA7B0C0]
    private static let onLight: [UInt32] = [0x3D6FE0, 0x1F9D57, 0xB8692A, 0x9B4FC0, 0x169489, 0xD43E66, 0x6E8F12, 0x5C6577]
    static func color(_ i: Int, dark: Bool) -> Color {
        let k = ((i % names.count) + names.count) % names.count
        return Color(hex: dark ? onDark[k] : onLight[k])
    }
}

/// Priority keeps the same three colours on every skin and always comes with ! marks.
enum PriorityColor {
    static func color(_ p: Int, dark: Bool) -> Color {
        switch p {
        case 1: return Color(hex: dark ? 0xFF5A4E : 0xE5372B)
        case 2: return Color(hex: dark ? 0xFF9F1A : 0xE07C00)
        case 3: return Color(hex: dark ? 0x5B8CFF : 0x2B6BFF)
        default: return .clear
        }
    }
}

extension Notification.Name {
    static let ritualNewTask = Notification.Name("ritual.newTask")
    /// Opens the editor for a task (object: UUID), or the first open task due today.
    static let ritualEditTask = Notification.Name("ritual.editTask")
    static let ritualCloseTaskEditor = Notification.Name("ritual.closeTaskEditor")
}

// MARK: - Small pieces

struct TaskCheckbox: View {
    @Environment(\.skin) private var skin
    let done: Bool
    let priority: Int
    var size: CGFloat = 22
    @State private var hover = false

    var body: some View {
        let pc = PriorityColor.color(priority, dark: skin.dark)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(done ? skin.chip : priority > 0 ? pc.opacity(0.13) : .clear)
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .strokeBorder(done ? skin.chip : priority > 0 ? pc : skin.ring, lineWidth: 2)
            if done || hover {
                Image(systemName: "checkmark").font(.system(size: size * 0.45, weight: .black))
                    .foregroundStyle(done ? skin.chipFg : skin.fg.opacity(0.35))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct LabelChip: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let name: String
    var removable: (() -> Void)? = nil

    var body: some View {
        let c = LabelPalette.color(store.labelColorIndex(name), dark: skin.dark)
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(name).font(.body(11.5, .semibold)).foregroundStyle(c)
            if let removable {
                Button(action: removable) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(c).help("Remove \(name)")
            }
        }
        .padding(.leading, 7).padding(.trailing, removable == nil ? 9 : 7).padding(.vertical, 2)
        .background(Capsule().fill(c.opacity(0.15)))
    }
}

/// Mono-caps meta like "⏰ 5:00 PM" or "2d late".
private struct Meta: View {
    @Environment(\.skin) private var skin
    let text: String
    var icon: String? = nil
    var color: Color? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .semibold)) }
            Text(text).font(.mono(10.5))
        }
        .foregroundStyle(color ?? skin.fgDim)
    }
}

func taskDayLabel(_ d: Date, today: Date) -> String {
    switch Day.between(today, d) {
    case 0: return "Today"
    case 1: return "Tomorrow"
    case -1: return "Yesterday"
    case 2...6: return d.formatted(.dateTime.weekday(.wide))
    default: return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Tasks tab

struct TasksView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @State private var editing: TaskItem?
    @State private var draft = ""
    @FocusState private var addFocused: Bool
    // Picker choices for the add bar; they win over words typed in the title.
    @State private var pickDay: TaskParser.DayChoice = .unset
    @State private var pickTime: ReminderTime?
    @State private var pickLabels: [String] = []
    @State private var pickPriority: Int?
    @State private var popover: Pop?
    @State private var confirmClear = false
    private enum Pop: Hashable { case day, time, labels, priority }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            addBar
            preview
            if !store.labels.isEmpty { filters }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) { sections }
                    .padding(.bottom, 90)
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, 28).padding(.top, 10)
        .sheet(item: $editing) { t in TaskEditor(task: t).environment(\.skin, skin) }
        .onReceive(NotificationCenter.default.publisher(for: .ritualNewTask)) { _ in addFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .ritualCloseTaskEditor)) { _ in editing = nil }
        .onReceive(NotificationCenter.default.publisher(for: .ritualEditTask)) { n in
            editing = (n.object as? UUID).flatMap(store.task) ?? (store.tasksEarlier + store.tasksToday).first { !$0.isDone }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(store.taskView.rawValue).font(.display(34)).foregroundStyle(skin.fg)
                Text(subtitle).font(.body(13.5)).foregroundStyle(skin.fgDim)
            }
            Spacer()
            HStack(spacing: 2) {
                ForEach(Store.TaskView.allCases, id: \.self) { v in
                    let on = store.taskView == v
                    Button { store.taskView = v } label: {
                        HStack(spacing: 5) {
                            Text(v.rawValue).font(.body(12.5, .semibold))
                            let n = store.count(v)
                            if n > 0 { Text("\(n)").font(.mono(10)).opacity(0.7) }
                        }
                        .foregroundStyle(on ? skin.bgBottom : skin.fgDim)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(Capsule().fill(on ? skin.fg : .clear))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(skin.fg.opacity(0.06)))
        }
    }

    private var subtitle: String {
        switch store.taskView {
        case .today:
            let d = store.taskDay
            return store.today.formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · \(d.done) of \(d.total) done"
        case .inbox: return "Tasks without a day. Give one a day from its ⋯ menu, or drag it onto Today."
        case .upcoming: return "Everything with a day after today"
        case .done: return "Finished before today"
        }
    }

    // MARK: Add bar

    private var parsed: TaskParser.Result { TaskParser.parse(draft, today: store.today) }

    /// What the add bar would create right now.
    private var pending: TaskItem {
        let p = parsed
        let choice = pickDay != .unset ? pickDay : p.day
        var day: Date?
        switch choice {
        case .on(let d): day = d
        case .inbox: day = nil
        case .unset:
            switch store.taskView {
            case .inbox: day = nil
            case .upcoming: day = Day.add(1, to: store.today)
            case .today, .done: day = store.today
            }
        }
        let time = pickTime ?? p.time
        if time != nil && day == nil { day = store.today } // a reminder needs a day
        var labels = p.labels
        for l in pickLabels where !labels.contains(l) { labels.append(l) }
        if let f = store.taskLabelFilter, !labels.contains(f) { labels.append(f) }
        return TaskItem(title: p.title, day: day.map(Day.key), remind: time, labels: labels, priority: pickPriority ?? p.priority ?? 0)
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(skin.fgDim).padding(.leading, 4)
            TextField("Add a task · try “Send invoice tomorrow 4pm #work !1”", text: $draft)
                .textFieldStyle(.plain).font(.body(15, .medium)).foregroundStyle(skin.fg)
                .focused($addFocused)
                .onSubmit(add)
            pickerButton(.day, "calendar", "Pick a day", active: pickDay != .unset) { dayPopover }
            pickerButton(.time, "bell", "Set a reminder", active: pickTime != nil) { timePopover }
            pickerButton(.labels, "tag", "Labels", active: !pickLabels.isEmpty) { labelsPopover }
            pickerButton(.priority, "flag", "Priority", active: pickPriority != nil) { priorityPopover }
            Button("Add", action: add).buttonStyle(PillButtonStyle(filled: true))
                .disabled(parsed.title.isEmpty).opacity(parsed.title.isEmpty ? 0.5 : 1)
        }
        .padding(.leading, 10).padding(.trailing, 5).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(skin.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(addFocused ? skin.accent : skin.line, lineWidth: addFocused ? 1.5 : 1))
    }

    private func pickerButton<P: View>(_ which: Pop, _ icon: String, _ help: String, active: Bool, @ViewBuilder content: @escaping () -> P) -> some View {
        Button { popover = popover == which ? nil : which } label: {
            Image(systemName: active ? icon + ".fill" : icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? skin.accent : skin.fgDim)
                .frame(width: 30, height: 30)
                .background(Circle().fill(popover == which ? skin.fg.opacity(0.08) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .popover(isPresented: Binding(get: { popover == which }, set: { if !$0 && popover == which { popover = nil } }), arrowEdge: .bottom) {
            content().padding(14).background(SkinBackground()).environment(\.skin, skin)
        }
    }

    private var dayPopover: some View {
        DayChooser(choice: Binding(get: { pickDay == .unset ? pendingChoice : pickDay }, set: { pickDay = $0; popover = nil }), today: store.today)
    }

    private var pendingChoice: TaskParser.DayChoice { pending.date.map { .on($0) } ?? .inbox }

    private var timePopover: some View {
        ReminderChooser(time: Binding(get: { pickTime ?? parsed.time }, set: { pickTime = $0 }), use24h: store.use24h) { popover = nil }
    }

    private var labelsPopover: some View {
        LabelChooser(selected: Binding(get: { pickLabels }, set: { pickLabels = $0 }))
    }

    private var priorityPopover: some View {
        PriorityChooser(priority: Binding(get: { pickPriority ?? parsed.priority ?? 0 }, set: { pickPriority = $0; popover = nil }))
    }

    private var preview: some View {
        HStack(spacing: 8) {
            if draft.trimmingCharacters(in: .whitespaces).isEmpty && pickDay == .unset && pickTime == nil && pickLabels.isEmpty && pickPriority == nil {
                Text("Type #label, !1 !2 !3 for priority, today / tomorrow / fri / next week / no date, and a time like 5pm. Or use the buttons.")
                    .font(.body(12)).foregroundStyle(skin.fgDim)
            } else {
                let t = pending
                Meta(text: t.date.map { taskDayLabel($0, today: store.today) } ?? "Inbox", icon: t.date == nil ? "tray" : "calendar")
                if let r = t.remind { Meta(text: r.label(store.settings.timeFormat), icon: "bell") }
                ForEach(t.labels, id: \.self) { LabelChip(name: $0) }
                if t.priority > 0 {
                    Text("\(TaskItem.bangs(t.priority)) \(TaskItem.priorityNames[t.priority])").font(.mono(10.5, .bold))
                        .foregroundStyle(PriorityColor.color(t.priority, dark: skin.dark))
                }
                if pickDay != .unset || pickTime != nil || !pickLabels.isEmpty || pickPriority != nil {
                    Button("Clear picks") { clearPicks() }.buttonStyle(.plain).font(.body(11.5, .semibold)).foregroundStyle(skin.fgDim)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 20)
        .padding(.top, -4).padding(.leading, 6)
    }

    private func add() {
        let t = pending
        guard !t.title.isEmpty else { return }
        store.addTask(t)
        Feedback.shared.play(.tick)
        draft = ""
        clearPicks()
        // Show it where it landed.
        if t.day == nil { if store.taskView != .inbox { store.taskView = .inbox } }
        else if let d = t.date, d > store.today, store.taskView == .today { store.taskView = .upcoming }
        else if let d = t.date, d <= store.today, store.taskView != .today { store.taskView = .today }
        addFocused = true
    }

    private func clearPicks() { pickDay = .unset; pickTime = nil; pickLabels = []; pickPriority = nil }

    // MARK: Filters

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                filterChip(nil)
                ForEach(store.labels, id: \.self) { filterChip($0) }
            }
        }
        .scrollIndicators(.never)
    }

    private func filterChip(_ l: String?) -> some View {
        let on = store.taskLabelFilter == l
        return Button { store.taskLabelFilter = on ? nil : l } label: {
            HStack(spacing: 6) {
                if let l { Circle().fill(LabelPalette.color(store.labelColorIndex(l), dark: skin.dark)).frame(width: 7, height: 7) }
                Text(l ?? "All").font(.body(12, .semibold))
            }
            .foregroundStyle(on ? skin.fg : skin.fgDim)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Capsule().strokeBorder(on ? skin.fg : skin.line, lineWidth: on ? 1.5 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Lists

    @ViewBuilder private var sections: some View {
        switch store.taskView {
        case .today:
            let early = store.tasksEarlier
            if !early.isEmpty { section("From earlier", early, late: true, showDay: true) }
            section("Today", store.tasksToday, empty: store.taskLabelFilter == nil ? "Nothing due today. Add one above." : "Nothing with this label today.")
        case .inbox:
            section("No day yet", store.tasksInbox, empty: "Inbox is empty. Tasks you add with “no date” land here.")
        case .upcoming:
            let groups = store.tasksUpcoming
            if groups.isEmpty { section("Later", [], empty: "Nothing planned after today.") }
            ForEach(groups, id: \.day) { g in section(taskDayLabel(g.day, today: store.today), g.tasks) }
        case .done:
            let done = store.tasksDone
            section("Finished", done, showDay: true, empty: "Finished tasks move here the day after you tick them.")
            if !done.isEmpty {
                HStack {
                    if confirmClear {
                        Text("Remove \(done.count) finished tasks?").font(.body(12.5)).foregroundStyle(skin.fgDim)
                        Button("Remove") { store.clearDoneTasks(); confirmClear = false }.buttonStyle(PillButtonStyle(destructive: true))
                        Button("Keep") { confirmClear = false }.buttonStyle(PillButtonStyle())
                    } else {
                        Button("Clear history…") { confirmClear = true }.buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
    }

    private func section(_ title: String, _ list: [TaskItem], late: Bool = false, showDay: Bool = false, empty: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MonoCaps(title, size: 10.5, color: late ? PriorityColor.color(1, dark: skin.dark) : skin.fg, weight: .bold)
                if !list.isEmpty { MonoCaps("· \(list.filter { !$0.isDone }.count) open", size: 10.5) }
            }
            .padding(.bottom, 8)
            Rectangle().fill(skin.line).frame(height: 1)
            if list.isEmpty, let empty {
                Text(empty).font(.body(13)).foregroundStyle(skin.fgDim).padding(.vertical, 14).padding(.horizontal, 6)
            }
            ForEach(list) { t in
                TaskRow(task: t, showDay: showDay || store.taskView == .inbox && t.date != nil) { editing = t }
            }
        }
    }
}

// MARK: - Row

struct TaskRow: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let task: TaskItem
    var showDay = false
    var edit: () -> Void
    @State private var hover = false

    var body: some View {
        let late = task.daysLate(today: store.today)
        HStack(alignment: .top, spacing: 12) {
            Button { withAnimation(.easeInOut(duration: 0.15)) { store.toggleTask(task.id) }; Feedback.shared.play(task.isDone ? .undo : .tick) } label: {
                TaskCheckbox(done: task.isDone, priority: task.priority)
            }
            .buttonStyle(.plain)
            .help(task.isDone ? "Mark not done" : "Mark done")

            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).font(.body(15, .semibold))
                    .foregroundStyle(task.isDone ? skin.fgDim : skin.fg)
                    .strikethrough(task.isDone, color: skin.fgDim)
                    .fixedSize(horizontal: false, vertical: true)
                let hasMeta = late > 0 || showDay || task.remind != nil || !task.labels.isEmpty || !task.note.isEmpty
                if hasMeta {
                    HStack(spacing: 8) {
                        if late > 0 { Meta(text: late == 1 ? "1 day late" : "\(late) days late", color: PriorityColor.color(1, dark: skin.dark)) }
                        else if showDay, let d = task.date { Meta(text: taskDayLabel(d, today: store.today), icon: "calendar") }
                        if let r = task.remind, task.date != nil { Meta(text: r.label(store.settings.timeFormat), icon: "bell") }
                        ForEach(task.labels, id: \.self) { LabelChip(name: $0) }
                        if !task.note.isEmpty { Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(skin.fgDim).help(task.note) }
                    }
                }
            }
            .opacity(task.isDone ? 0.75 : 1)
            Spacer(minLength: 8)
            ZStack(alignment: .trailing) {
                if task.priority > 0 {
                    Text(TaskItem.bangs(task.priority)).font(.mono(12, .bold))
                        .foregroundStyle(PriorityColor.color(task.priority, dark: skin.dark).opacity(task.isDone ? 0.4 : 1))
                        .opacity(hover ? 0 : 1)
                }
                Menu { TaskMenuItems(task: task, edit: edit) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(skin.fg)
                        .frame(width: 26, height: 22).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .opacity(hover ? 1 : 0).allowsHitTesting(hover)
                .help("Task menu")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 11).padding(.horizontal, 6)
        .background(LinearGradient(colors: [skin.fg.opacity(hover ? 0.045 : 0), .clear], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .bottom) { Rectangle().fill(skin.line).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
        .onHover { hover = $0 }
        .contextMenu { TaskMenuItems(task: task, edit: edit) }
        .draggable(task.id.uuidString)
    }
}

struct TaskMenuItems: View {
    @Environment(Store.self) private var store
    let task: TaskItem
    var edit: () -> Void

    var body: some View {
        Button("Edit…", action: edit)
        Button(task.isDone ? "Mark not done" : "Mark done") { store.toggleTask(task.id) }
        Menu("Priority") {
            ForEach([1, 2, 3, 0], id: \.self) { p in
                Toggle("\(TaskItem.bangs(p)) \(TaskItem.priorityNames[p])".trimmingCharacters(in: .whitespaces),
                       isOn: Binding(get: { task.priority == p }, set: { if $0 { store.setPriority(task.id, p) } }))
            }
        }
        Menu("Move to") {
            Button("Today") { store.moveTask(task.id, to: store.today) }
            Button("Tomorrow") { store.moveTask(task.id, to: Day.add(1, to: store.today)) }
            Button("Next week") { store.moveTask(task.id, to: Day.add(7, to: Day.startOfWeek(store.today))) }
            Button("Pick a day…", action: edit)
            Divider()
            Button("Inbox (no day)") { store.moveTask(task.id, to: nil) }
        }
        Divider()
        Button("Delete", role: .destructive) { store.deleteTask(task.id) }
    }
}

// MARK: - Choosers (shared by the add bar and the editor)

struct DayChooser: View {
    @Environment(\.skin) private var skin
    @Binding var choice: TaskParser.DayChoice
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                quick("Today", .on(today))
                quick("Tomorrow", .on(Day.add(1, to: today)))
                quick("Next week", .on(Day.add(7, to: Day.startOfWeek(today))))
                quick("No date", .inbox)
            }
            DatePicker("", selection: Binding(get: { selected ?? today }, set: { choice = .on(Day.start($0)) }),
                       in: min(today, selected ?? today)..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(skin.accent)
            .frame(width: 260)
        }
    }

    private var selected: Date? {
        if case .on(let d) = choice { return d }
        return nil
    }

    private func quick(_ label: String, _ c: TaskParser.DayChoice) -> some View {
        let on = choice == c
        return Button(label) { choice = c }
            .buttonStyle(.plain).font(.body(12, .semibold))
            .foregroundStyle(on ? skin.bgBottom : skin.fg)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(on ? skin.fg : skin.fg.opacity(0.08)))
    }
}

struct ReminderChooser: View {
    @Environment(\.skin) private var skin
    @Binding var time: ReminderTime?
    let use24h: Bool
    var done: () -> Void = {}
    @State private var pick = ReminderTime(hour: 9, minute: 0)
    @State private var typed = ""
    @State private var typedError = false
    private static let presets = [(9, 0), (12, 0), (15, 0), (17, 0), (20, 0)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoCaps("Remind me at", size: 10)
            HStack(spacing: 10) {
                TimePicker(time: $pick, use24h: use24h)
                VStack(alignment: .leading, spacing: 6) {
                    TextField("or type 6:45pm", text: $typed)
                        .textFieldStyle(.plain).font(.body(13, .semibold)).foregroundStyle(skin.fg)
                        .padding(8).frame(width: 130)
                        .background(RoundedRectangle(cornerRadius: 8).fill(skin.fg.opacity(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(typedError ? Color(hex: 0xEF6A5E) : .clear, lineWidth: 1.5))
                        .onSubmit {
                            if let t = ReminderTime.parse(typed) { pick = t; time = t; typed = ""; done() } else { typedError = true }
                        }
                        .onChange(of: typed) { typedError = false }
                    Button("Set \(pick.label(use24h ? .h24 : .h12))") { time = pick; done() }
                        .buttonStyle(PillButtonStyle(filled: true))
                }
            }
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.0) { h, m in
                    let t = ReminderTime(hour: h, minute: m)
                    Button(t.label(use24h ? .h24 : .h12)) { pick = t; time = t; done() }
                        .buttonStyle(.plain).font(.body(11.5, .semibold)).foregroundStyle(skin.fg)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(skin.fg.opacity(time == t ? 0.18 : 0.07)))
                }
                Spacer(minLength: 6)
                if time != nil {
                    Button("No reminder") { time = nil; done() }.buttonStyle(.plain).font(.body(11.5, .semibold)).foregroundStyle(skin.fgDim)
                }
            }
        }
        .frame(width: 330)
        .onAppear { if let time { pick = time } }
    }
}

struct LabelChooser: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Binding var selected: [String]
    var showTitle = true
    @State private var newLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showTitle { MonoCaps("Labels", size: 10) }
            if !store.labels.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(store.labels, id: \.self) { l in
                        let on = selected.contains(l)
                        Button { if on { selected.removeAll { $0 == l } } else { selected.append(l) } } label: {
                            HStack(spacing: 5) {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 11))
                                    .foregroundStyle(LabelPalette.color(store.labelColorIndex(l), dark: skin.dark))
                                Text(l).font(.body(12, .semibold)).foregroundStyle(skin.fg)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(skin.fg.opacity(on ? 0.12 : 0.05)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TextField("New label, then ↩", text: $newLabel)
                .textFieldStyle(.plain).font(.body(13)).foregroundStyle(skin.fg)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(skin.fg.opacity(0.07)))
                .onSubmit {
                    let l = newLabel.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                    if !l.isEmpty && !selected.contains(l) { selected.append(l) }
                    newLabel = ""
                }
        }
        .frame(width: 280)
    }
}

struct PriorityChooser: View {
    @Environment(\.skin) private var skin
    @Binding var priority: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([1, 2, 3, 0], id: \.self) { p in
                Button { priority = p } label: {
                    HStack(spacing: 10) {
                        TaskCheckbox(done: false, priority: p, size: 16)
                        Text(TaskItem.priorityNames[p]).font(.body(13, .semibold)).foregroundStyle(skin.fg)
                        Spacer()
                        Text(TaskItem.bangs(p)).font(.mono(12, .bold)).foregroundStyle(PriorityColor.color(p, dark: skin.dark))
                        if priority == p { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(skin.accent) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(priority == p ? skin.fg.opacity(0.07) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 200)
    }
}

// MARK: - Editor

struct TaskEditor: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State var task: TaskItem
    @State private var showCalendar = false
    @State private var showTime = false
    @State private var confirmDelete = false

    private var dayChoice: Binding<TaskParser.DayChoice> {
        Binding(get: { task.date.map { .on($0) } ?? .inbox }, set: { c in
            switch c {
            case .on(let d): task.day = Day.key(d)
            case .inbox, .unset: task.day = nil
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                MonoCaps("Task", size: 10)
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Save") { save() }.buttonStyle(PillButtonStyle(filled: true)).keyboardShortcut(.defaultAction)
                    .disabled(task.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            TextField("What needs doing?", text: $task.title)
                .textFieldStyle(.plain).font(.display(24, .bold)).foregroundStyle(skin.fg)
            TextField("Note (optional)", text: $task.note, axis: .vertical)
                .textFieldStyle(.plain).font(.body(13.5)).foregroundStyle(skin.fg).lineLimit(2...5)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(skin.fg.opacity(0.05)))

            field("Day") {
                HStack(spacing: 6) {
                    seg("Today", task.day == Day.key(store.today)) { task.day = Day.key(store.today) }
                    seg("Tomorrow", task.day == Day.key(Day.add(1, to: store.today))) { task.day = Day.key(Day.add(1, to: store.today)) }
                    seg(customDayLabel ?? "Pick…", customDayLabel != nil) { showCalendar = true }
                        .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                            DayChooser(choice: Binding(get: { dayChoice.wrappedValue }, set: { dayChoice.wrappedValue = $0; showCalendar = false }), today: store.today)
                                .padding(14).background(SkinBackground()).environment(\.skin, skin)
                        }
                    seg("No date", task.day == nil) { task.day = nil }
                }
            }
            field("Remind me") {
                HStack(spacing: 6) {
                    seg("None", task.remind == nil) { task.remind = nil }
                    seg(task.remind.map { $0.label(store.settings.timeFormat) } ?? "Set a time…", task.remind != nil) { showTime = true }
                        .popover(isPresented: $showTime, arrowEdge: .bottom) {
                            ReminderChooser(time: $task.remind, use24h: store.use24h) { showTime = false }
                                .padding(14).background(SkinBackground()).environment(\.skin, skin)
                        }
                    if task.remind != nil && task.day == nil {
                        Text("Reminders need a day. Saving puts it on today.").font(.body(11.5)).foregroundStyle(skin.fgDim)
                    }
                }
            }
            field("Labels") {
                LabelChooser(selected: $task.labels, showTitle: false)
            }
            field("Priority") {
                HStack(spacing: 6) {
                    ForEach([0, 1, 2, 3], id: \.self) { p in
                        let on = task.priority == p
                        Button { task.priority = p } label: {
                            Text(p == 0 ? "None" : "\(TaskItem.bangs(p)) \(TaskItem.priorityNames[p])").font(.body(12, .semibold))
                                .foregroundStyle(on ? (p == 0 ? skin.bgBottom : .white) : skin.fg)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(on ? (p == 0 ? skin.fg : PriorityColor.color(p, dark: skin.dark)) : skin.fg.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                if store.task(task.id) != nil {
                    if confirmDelete {
                        Text("Delete this task?").font(.body(12.5)).foregroundStyle(skin.fgDim)
                        Button("Delete") { store.deleteTask(task.id); dismiss() }.buttonStyle(PillButtonStyle(destructive: true))
                        Button("Keep") { confirmDelete = false }.buttonStyle(PillButtonStyle())
                    } else {
                        Button("Delete…") { confirmDelete = true }.buttonStyle(PillButtonStyle())
                    }
                }
                Spacer()
                if let at = task.remindAt, at < .now, !task.isDone {
                    Text("That reminder time has passed, so it won't ring.").font(.body(11.5)).foregroundStyle(skin.fgDim)
                }
            }
        }
        .padding(24)
        .frame(width: 600, height: 640)
        .background(SkinBackground())
    }

    private var customDayLabel: String? {
        guard let d = task.date, task.day != Day.key(store.today), task.day != Day.key(Day.add(1, to: store.today)) else { return nil }
        return taskDayLabel(d, today: store.today)
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.body(13, .semibold)).foregroundStyle(skin.fgDim).frame(width: 84, alignment: .leading)
            c()
            Spacer(minLength: 0)
        }
    }

    private func seg(_ label: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain).font(.body(12.5, .semibold))
            .foregroundStyle(on ? skin.bgBottom : skin.fg)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Capsule().fill(on ? skin.fg : skin.fg.opacity(0.08)))
    }

    private func save() {
        var t = task
        if t.remind != nil && t.day == nil { t.day = Day.key(store.today) }
        if store.task(t.id) != nil { store.updateTask(t) } else { store.addTask(t) }
        dismiss()
    }
}

// MARK: - Sidebar section

struct SidebarTasks: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let active: Bool
    @State private var dropTarget: Store.TaskView?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                MonoCaps("Tasks", size: 10)
                Spacer()
                let d = store.taskDay
                if d.total > 0 { MonoCaps("\(d.done)/\(d.total)", size: 10) }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
            row(.today, "calendar", drop: store.today)
            row(.inbox, "tray", drop: nil, isInbox: true)
            row(.upcoming, "arrow.right.to.line", drop: Day.add(1, to: store.today))
            row(.done, "checkmark.circle", drop: nil, droppable: false)
            if !store.labels.isEmpty {
                MonoCaps("Labels", size: 10).padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 4)
                ForEach(store.labels, id: \.self) { l in labelRow(l) }
            }
        }
    }

    private func show(_ v: Store.TaskView) {
        store.taskView = v
        NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks)
    }

    private func row(_ v: Store.TaskView, _ icon: String, drop: Date?, isInbox: Bool = false, droppable: Bool = true) -> some View {
        let on = active && store.taskView == v && store.taskLabelFilter == nil
        let n = store.count(v)
        let late = v == .today && store.taskDay.late > 0
        return Button { store.taskLabelFilter = nil; show(v) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(skin.fgDim).frame(width: 22)
                Text(v.rawValue).font(.body(13.5, .semibold)).foregroundStyle(skin.fg)
                Spacer()
                if n > 0 { Text("\(n)").font(.mono(10.5)).foregroundStyle(late ? PriorityColor.color(1, dark: skin.dark) : skin.fgDim) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(dropTarget == v ? skin.accent.opacity(0.2) : on ? skin.fg.opacity(0.09) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { items, _ in
            guard droppable else { return false }
            for raw in items { if let id = UUID(uuidString: raw) { store.moveTask(id, to: isInbox ? nil : drop) } }
            return true
        } isTargeted: { dropTarget = $0 && droppable ? v : (dropTarget == v ? nil : dropTarget) }
        .help(droppable ? "Drop a task here to move it" : "")
    }

    private func labelRow(_ l: String) -> some View {
        let on = active && store.taskLabelFilter == l
        return Button { store.taskLabelFilter = on ? nil : l; show(store.taskView) } label: {
            HStack(spacing: 10) {
                Circle().fill(LabelPalette.color(store.labelColorIndex(l), dark: skin.dark)).frame(width: 8, height: 8).frame(width: 22)
                Text(l).font(.body(13)).foregroundStyle(skin.fg)
                Spacer()
                let n = store.tasks.filter { !$0.isDone && $0.labels.contains(l) }.count
                if n > 0 { Text("\(n)").font(.mono(10.5)).foregroundStyle(skin.fgDim) }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? skin.fg.opacity(0.09) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
