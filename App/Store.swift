import SwiftUI
import Observation
import WidgetKit

@MainActor
@Observable
final class Store {
    private(set) var data: AppData
    var selectedID: UUID?
    /// Tasks tab: which list, and an optional label filter.
    var taskView: TaskView = .today
    var taskLabelFilter: String?
    var today = Day.start()
    /// Set after a check that finished a level, so the stage can play the level-up moment.
    var levelUp: (habit: UUID, level: Int)?
    /// Habit that just finished its journey and is waiting for "keep going / retire / new journey".
    var masteryPrompt: UUID?
    var saveError: String?
    /// Last change, offered as "Undo" in a toast.
    var toast: Toast?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let undo: AppData?
        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    var onChange: (() -> Void)?

    init() {
        if let loaded = Storage.load() {
            data = loaded
        } else {
            data = Storage.isDemo ? Seed.demo() : Seed.starter()
        }
        Day.weekStartOverride = data.settings.weekStart == 0 ? nil : data.settings.weekStart
        today = Day.start()
        persist()
        if data.settings.backups { Storage.backupIfNeeded() }
        selectedID = visibleHabits.first?.id
        masteryPrompt = data.habits.first { $0.needsMasteryChoice }?.id
    }

    // MARK: Reading

    var skin: Skin { Skin.named(data.settings.skin) }
    var use24h: Bool {
        switch data.settings.timeFormat {
        case .h24: return true
        case .h12: return false
        case .system: return !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "h").contains("a")
        }
    }
    var settings: AppSettings { data.settings }
    var groups: [HabitGroup] { data.groups.sorted { $0.order < $1.order } }

    var visibleHabits: [Habit] { sections.flatMap { $0.habits } }
    var retiredHabits: [Habit] { data.habits.filter { $0.state == .retired }.sorted { $0.order < $1.order } }

    struct Section: Identifiable {
        let id: String
        let groupID: UUID?
        let title: String
        let habits: [Habit]
    }

    var sections: [Section] {
        let live = data.habits.filter { $0.state != .retired }.sorted { $0.order < $1.order }
        var out: [Section] = groups.compactMap { g in
            let hs = live.filter { $0.groupID == g.id }
            return hs.isEmpty ? nil : Section(id: g.id.uuidString, groupID: g.id, title: g.name, habits: hs)
        }
        let known = Set(data.groups.map(\.id))
        let loose = live.filter { $0.groupID == nil || !known.contains($0.groupID!) }
        if !loose.isEmpty { out.append(Section(id: "loose", groupID: nil, title: "Habits", habits: loose)) }
        return out
    }

    var selected: Habit? {
        if let id = selectedID, let h = habit(id), h.state != .retired { return h }
        return visibleHabits.first
    }

    func habit(_ id: UUID) -> Habit? { data.habits.first { $0.id == id } }
    func habits(in group: UUID?) -> [Habit] { data.habits.filter { $0.groupID == group }.sorted { $0.order < $1.order } }

    var todayDone: Int { visibleHabits.filter { $0.isDone(on: today) }.count }

    /// Upcoming reminders across every habit, soonest first, the same way the notification queue fires them:
    /// it respects each time's days, quiet hours, and skips habits already done today.
    func upcomingReminders(limit: Int = 3, now: Date = .now) -> [(habit: Habit, at: Date)] {
        var out: [(Habit, Date)] = []
        for h in visibleHabits where h.remindersOn {
            for t in h.reminders where !Notifier.isQuiet(t, settings) {
                for offset in 0..<8 {
                    let day = Day.add(offset, to: today)
                    guard h.isScheduled(day), t.weekdays.isEmpty || t.weekdays.contains(Day.weekday(day)) else { continue }
                    if offset == 0 && h.isDone(on: day) { continue }
                    guard let at = Calendar.current.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day), at > now else { continue }
                    out.append((h, at))
                    break
                }
            }
        }
        return out.sorted { $0.1 < $1.1 }.prefix(limit).map { ($0.0, $0.1) }
    }

    // MARK: Checking

    /// Marks the day done (or adds one step for count habits). Returns true if the day became done.
    @discardableResult
    func check(_ id: UUID, on date: Date? = nil, toast: Bool = false) -> Bool {
        let date = date ?? today
        guard let i = index(id) else { return false }
        let h0 = data.habits[i]
        guard !h0.isDone(on: date) else { return false }
        let before = data
        let k = Day.key(date)
        switch h0.goalKind {
        case .once, .amount: data.habits[i].log[k] = h0.effectiveTarget
        case .count: data.habits[i].log[k] = min(h0.effectiveTarget, h0.value(on: date) + 1)
        }
        let h = data.habits[i]
        let becameDone = h.isDone(on: date)
        if becameDone { afterRep(i, wasLevel: h0.level, wasMastered: h0.isMastered) }
        commit()
        if becameDone { Notifier.shared.clearDelivered(for: id) }
        if toast { self.toast = Toast(message: becameDone ? "Ticked \(h.name)" : "\(h.name) · \(h.progressText(on: date))", undo: before) }
        return becameDone
    }

    func uncheck(_ id: UUID, on date: Date? = nil, toast: Bool = false) {
        let date = date ?? today
        guard let i = index(id), data.habits[i].value(on: date) > 0 else { return }
        let before = data
        data.habits[i].log[Day.key(date)] = nil
        if !data.habits[i].isMastered {
            data.habits[i].masteryAsked = false
            if masteryPrompt == id { masteryPrompt = nil }
        }
        commit()
        if toast { self.toast = Toast(message: "Unticked \(data.habits[i].name)", undo: before) }
    }

    /// One rule for every tick surface: done → untick, not done → tick (or one more step).
    func toggle(_ id: UUID, on date: Date? = nil) {
        guard let h = habit(id) else { return }
        let d = date ?? today
        if h.isDone(on: d) {
            uncheck(id, on: d, toast: true)
            Feedback.shared.play(.undo)
        } else if check(id, on: d, toast: true) {
            Feedback.shared.play(.done)
            Feedback.shared.haptic()
        } else {
            Feedback.shared.play(.tick)
        }
    }

    func setValue(_ id: UUID, _ value: Double, on date: Date? = nil) {
        guard let i = index(id) else { return }
        let d = date ?? today
        let h0 = data.habits[i]
        let wasDone = h0.isDone(on: d)
        data.habits[i].log[Day.key(d)] = value > 0 ? value : nil
        if !wasDone && data.habits[i].isDone(on: d) { afterRep(i, wasLevel: h0.level, wasMastered: h0.isMastered) }
        commit()
    }

    private func afterRep(_ i: Int, wasLevel: Int, wasMastered: Bool) {
        let h = data.habits[i]
        guard h.state == .active else { return }
        if !wasMastered && h.isMastered {
            switch settings.mastery {
            case .ask: masteryPrompt = h.id
            case .keepGoing: data.habits[i].state = .endless; data.habits[i].masteryAsked = true
            case .retire: data.habits[i].state = .retired; data.habits[i].masteryAsked = true
            }
        } else if h.level > wasLevel {
            levelUp = (h.id, h.level)
        }
    }

    func undo(_ t: Toast) {
        guard let prev = t.undo else { return }
        data = prev
        toast = nil
        if selected == nil { selectedID = visibleHabits.first?.id }
        commit()
    }

    // MARK: Mastery

    enum MasteryChoice { case keepGoing, retire, newJourney }

    func resolveMastery(_ id: UUID, _ choice: MasteryChoice) {
        guard let i = index(id) else { return }
        data.habits[i].masteryAsked = true
        switch choice {
        case .keepGoing:
            data.habits[i].state = .endless
        case .retire:
            data.habits[i].state = .retired
            if selectedID == id { selectedID = visibleHabits.first { $0.id != id }?.id }
        case .newJourney:
            data.habits[i].state = .active
            data.habits[i].round += 1
            data.habits[i].masteryAsked = false
            // The next journey starts tomorrow so today's check stays with the finished one.
            data.habits[i].journeyStart = Day.key(Day.add(1, to: today))
        }
        masteryPrompt = data.habits.first { $0.needsMasteryChoice && $0.id != id }?.id
        commit()
    }

    func archive(_ id: UUID) {
        guard let i = index(id) else { return }
        let before = data
        data.habits[i].state = .retired
        if selectedID == id { selectedID = visibleHabits.first { $0.id != id }?.id }
        commit()
        toast = Toast(message: "Moved \(data.habits[i].name) to the trophy shelf", undo: before)
    }

    func restore(_ id: UUID) {
        guard let i = index(id) else { return }
        data.habits[i].state = data.habits[i].isMastered ? .endless : .active
        selectedID = id
        commit()
    }

    // MARK: Editing

    func add(_ habit: Habit) {
        var h = habit
        h.order = (data.habits.map(\.order).max() ?? 0) + 1
        data.habits.append(h)
        selectedID = h.id
        commit()
    }

    func update(_ habit: Habit) {
        guard let i = index(habit.id) else { return }
        data.habits[i] = habit
        commit()
    }

    func delete(_ id: UUID) {
        guard let i = index(id) else { return }
        let before = data
        let name = data.habits[i].name
        data.habits.remove(at: i)
        if selectedID == id { selectedID = visibleHabits.first?.id }
        Notifier.shared.clearDelivered(for: id)
        commit()
        toast = Toast(message: "Deleted \(name)", undo: before)
    }

    func move(_ id: UUID, to group: UUID?) {
        guard let i = index(id) else { return }
        data.habits[i].groupID = group
        data.habits[i].order = (habits(in: group).map(\.order).max() ?? 0) + 1
        commit()
    }

    /// Moves a habit one step up or down within its group.
    func nudge(_ id: UUID, by delta: Int) {
        guard let h = habit(id) else { return }
        var list = habits(in: h.groupID).filter { $0.state != .retired }
        guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        for (n, item) in list.enumerated() { if let k = index(item.id) { data.habits[k].order = n } }
        commit()
    }

    @discardableResult
    func addGroup(_ name: String) -> UUID {
        let g = HabitGroup(name: name, order: (data.groups.map(\.order).max() ?? 0) + 1)
        data.groups.append(g)
        commit()
        return g.id
    }

    func renameGroup(_ id: UUID, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let i = data.groups.firstIndex(where: { $0.id == id }) else { return }
        data.groups[i].name = n
        commit()
    }

    func nudgeGroup(_ id: UUID, by delta: Int) {
        var list = groups
        guard let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + delta) else { return }
        list.swapAt(i, i + delta)
        for (n, g) in list.enumerated() { if let k = data.groups.firstIndex(where: { $0.id == g.id }) { data.groups[k].order = n } }
        commit()
    }

    func deleteGroup(_ id: UUID) {
        let before = data
        let name = data.groups.first { $0.id == id }?.name ?? "group"
        data.groups.removeAll { $0.id == id }
        for i in data.habits.indices where data.habits[i].groupID == id { data.habits[i].groupID = nil }
        commit()
        toast = Toast(message: "Deleted group \(name). Its habits moved to Habits.", undo: before)
    }

    func select(offset: Int) {
        let list = visibleHabits
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = list[(i + offset + list.count) % list.count].id
    }

    func setSettings(_ s: AppSettings) {
        guard s != data.settings else { return }
        if s.weekStart != data.settings.weekStart { Day.weekStartOverride = s.weekStart == 0 ? nil : s.weekStart }
        data.settings = s
        commit()
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = data.settings
        change(&s)
        setSettings(s)
    }

    /// Called on wake, on the minute timer, and when the app becomes active.
    func refreshDay() {
        let now = Day.start()
        if now != today { today = now; onChange?() }
    }

    // MARK: Import / export

    func exportJSON(to url: URL) throws { try Storage.encoder.encode(data).write(to: url, options: .atomic) }

    func exportCSV(to url: URL) throws {
        var rows = ["date,habit,group,value,target,done"]
        let groupNames = Dictionary(uniqueKeysWithValues: data.groups.map { ($0.id, $0.name) })
        for h in data.habits {
            for (k, v) in h.log.sorted(by: { $0.key < $1.key }) {
                let g = h.groupID.flatMap { groupNames[$0] } ?? ""
                rows.append([k, csv(h.name), csv(g), Habit.fmt(v), Habit.fmt(h.effectiveTarget), v >= h.effectiveTarget ? "1" : "0"].joined(separator: ","))
            }
        }
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        // Tasks go next to it as <name>-tasks.csv.
        guard !data.tasks.isEmpty else { return }
        var trows = ["title,day,reminder,labels,priority,done,note"]
        for t in data.tasks.sorted(by: { ($0.day ?? "~") < ($1.day ?? "~") }) {
            trows.append([csv(t.title), t.day ?? "", t.remind.map { $0.label(.h24) } ?? "", csv(t.labels.joined(separator: " ")),
                          TaskItem.priorityNames[t.priority].lowercased(), t.doneAt.map { Day.key($0) } ?? "", csv(t.note)].joined(separator: ","))
        }
        let turl = url.deletingPathExtension().appendingPathExtension("tasks").appendingPathExtension("csv")
        try trows.joined(separator: "\n").write(to: turl, atomically: true, encoding: .utf8)
    }

    private func csv(_ s: String) -> String {
        s.contains(",") || s.contains("\"") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    func importJSON(from url: URL) throws {
        let incoming = try Storage.decoder.decode(AppData.self, from: Data(contentsOf: url))
        let before = data
        data = incoming
        selectedID = visibleHabits.first?.id
        commit()
        toast = Toast(message: "Imported \(incoming.habits.count) habits", undo: before)
    }

    func resetAll(habits: Bool = true, tasks: Bool = false) {
        let before = data
        if habits { data.habits = []; data.groups = []; selectedID = nil }
        if tasks { data.tasks = []; data.labelColors = [:] }
        commit()
        toast = Toast(message: habits && tasks ? "Habits and tasks deleted" : habits ? "All habits deleted" : "All tasks deleted", undo: before)
    }

    // MARK: Plumbing

    private func index(_ id: UUID) -> Int? { data.habits.firstIndex { $0.id == id } }

    func commit() {
        persist()
        WidgetCenter.shared.reloadAllTimelines()
        Notifier.shared.reschedule(data.habits, tasks: data.tasks, settings: data.settings)
        onChange?()
    }

    private func persist() {
        do {
            try Storage.save(data)
            saveError = nil
        } catch {
            saveError = "Couldn't save to \(Storage.file.path): \(error.localizedDescription)"
            NSLog("Ritual: \(saveError!)")
        }
    }
}

// MARK: - Seed data

enum Seed {
    static func starter() -> AppData {
        var d = AppData()
        let morning = HabitGroup(name: "Morning", order: 0)
        let evening = HabitGroup(name: "Evening", order: 1)
        d.groups = [morning, evening]
        d.habits = [
            Habit(name: "Meditate", goal: "10 minutes", groupID: morning.id, reminders: [ReminderTime(hour: 7, minute: 30)], order: 0),
            Habit(name: "Read", goal: "10 pages", groupID: evening.id, reminders: [ReminderTime(hour: 21, minute: 30)], order: 1),
        ]
        return d
    }

    /// Plausible history for screenshots and design review (`--demo`, stored separately).
    static func demo() -> AppData {
        var d = AppData()
        let g = [HabitGroup(name: "Morning", order: 0), HabitGroup(name: "Body", order: 1), HabitGroup(name: "Evening", order: 2)]
        d.groups = g
        let spec: [(String, String, Int, Int, Double, UInt64)] = [
            ("Meditate", "10 minutes", 0, 62, 0.72, 3), ("Read", "10 pages", 0, 20, 0.65, 7),
            ("Walk", "10,000 steps", 1, 40, 0.7, 11), ("Stretch", "5 minutes", 1, 9, 0.7, 5),
            ("Drink water", "", 1, 70, 0.5, 13), ("No phone in bed", "after 10:30 pm", 2, 75, 0.82, 2),
            ("Journal", "3 lines", 2, 40, 0.45, 17),
        ]
        let today = Day.start()
        for (n, (name, goal, gi, span, rate, seed)) in spec.enumerated() {
            var rng = SplitMix(seed: seed)
            var h = Habit(name: name, goal: goal, groupID: g[gi].id, reminders: [ReminderTime(hour: 7 + n * 2, minute: n * 5 % 60)], order: n)
            if name == "Drink water" { h.goalKind = .count; h.target = 8; h.unit = "glasses" }
            h.created = Day.add(-span, to: today)
            for back in stride(from: span, through: 1, by: -1) where rng.next() < rate {
                h.log[Day.key(Day.add(-back, to: today))] = h.effectiveTarget
            }
            while h.doneKeys.count > 59 { h.log[h.doneKeys.first!] = nil }
            if name == "Journal" { for back in 0..<10 { h.log[Day.key(Day.add(-back, to: today))] = nil } }
            if name == "Drink water" { h.log[Day.key(today)] = 3 }
            d.habits.append(h)
        }
        // a finished journey and an archived habit for the trophy shelf
        var done = Habit(name: "Floss", goal: "every night", groupID: g[2].id, order: 20)
        done.created = Day.add(-120, to: today)
        for back in 30..<90 { done.log[Day.key(Day.add(-back, to: today))] = 1 }
        done.state = .retired; done.masteryAsked = true
        var paused = Habit(name: "Cold shower", groupID: g[1].id, order: 21)
        paused.created = Day.add(-80, to: today)
        for back in stride(from: 40, to: 70, by: 2) { paused.log[Day.key(Day.add(-back, to: today))] = 1 }
        paused.state = .retired
        d.habits += [done, paused]
        func key(_ n: Int) -> String { Day.key(Day.add(n, to: today)) }
        var bill = TaskItem(title: "Pay electricity bill", day: key(-1), labels: ["home"], priority: 1)
        bill.created = Day.add(-3, to: today)
        var cleaning = TaskItem(title: "Pick up dry cleaning", day: key(0), labels: ["home"])
        cleaning.doneAt = .now
        var report = TaskItem(title: "Finish and send the Q3 report", day: key(0), remind: ReminderTime(hour: 17, minute: 0), labels: ["work"], priority: 1)
        report.note = "Attach the deck."
        d.tasks = [
            bill, report, cleaning,
            TaskItem(title: "Call the bank about the card limit", day: key(0), remind: ReminderTime(hour: 11, minute: 30), labels: ["bank"], priority: 2),
            TaskItem(title: "Reply about Sunday plans", day: key(0), remind: ReminderTime(hour: 19, minute: 0), labels: ["personal"], priority: 3),
            TaskItem(title: "Renew health insurance", day: key(2), remind: ReminderTime(hour: 10, minute: 0), labels: ["health", "bank"], priority: 2),
            TaskItem(title: "Buy a birthday gift", day: key(3), labels: ["personal"]),
            TaskItem(title: "Book a dentist appointment", labels: ["health"]),
            TaskItem(title: "Look into a standing desk", labels: ["home"]),
        ]
        d.labelColors = ["work": 0, "bank": 1, "home": 2, "personal": 3, "health": 4]
        if false {
        }
        return d
    }
}

// MARK: - Tasks

extension Store {
    enum TaskView: String, CaseIterable { case today = "Today", inbox = "Inbox", upcoming = "Upcoming", done = "Done" }

    var tasks: [TaskItem] { data.tasks }
    func task(_ id: UUID) -> TaskItem? { data.tasks.first { $0.id == id } }
    private func taskIndex(_ id: UUID) -> Int? { data.tasks.firstIndex { $0.id == id } }

    private func filtered(_ list: [TaskItem]) -> [TaskItem] {
        guard let l = taskLabelFilter else { return list }
        return list.filter { $0.labels.contains(l) }
    }

    /// Open tasks from earlier days. They stay on their own day and show how late they are.
    var tasksEarlier: [TaskItem] {
        filtered(data.tasks.filter { !$0.isDone && ($0.date.map { $0 < today } ?? false) }).sorted(by: TaskItem.ordered)
    }
    /// Due today, plus anything ticked today (crossed out until midnight).
    var tasksToday: [TaskItem] {
        let k = Day.key(today)
        return filtered(data.tasks.filter { $0.day == k || ($0.doneToday(today) && ($0.date.map { $0 < today } ?? false)) }).sorted(by: TaskItem.ordered)
    }
    var tasksInbox: [TaskItem] {
        filtered(data.tasks.filter { $0.day == nil && (!$0.isDone || $0.doneToday(today)) }).sorted(by: TaskItem.ordered)
    }
    /// Future days, grouped and in order.
    var tasksUpcoming: [(day: Date, tasks: [TaskItem])] {
        let future = filtered(data.tasks.filter { t in t.date.map { $0 > today } ?? false })
        return Dictionary(grouping: future) { $0.day! }.sorted { $0.key < $1.key }
            .compactMap { k, v in Day.date(k).map { ($0, v.sorted(by: TaskItem.ordered)) } }
    }
    /// Finished before today, newest first.
    var tasksDone: [TaskItem] {
        filtered(data.tasks.filter { $0.isDone && !$0.doneToday(today) }).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    /// Everything due today or earlier, ignoring the label filter (for the day pane and menu bar).
    var taskDay: (done: Int, total: Int, late: Int) {
        let k = Day.key(today)
        let due = data.tasks.filter { t in t.day == k || (t.date.map { $0 < today } ?? false) && (!t.isDone || t.doneToday(today)) }
        return (due.filter(\.isDone).count, due.count, due.filter { $0.daysLate(today: today) > 0 }.count)
    }
    var openTasksToday: Int { taskDay.total - taskDay.done }

    func count(_ v: TaskView) -> Int {
        let k = Day.key(today)
        switch v {
        case .today: return data.tasks.filter { !$0.isDone && ($0.day == k || ($0.date.map { $0 < today } ?? false)) }.count
        case .inbox: return data.tasks.filter { !$0.isDone && $0.day == nil }.count
        case .upcoming: return data.tasks.filter { !$0.isDone && ($0.date.map { $0 > today } ?? false) }.count
        case .done: return 0
        }
    }

    /// Labels in use, most used first.
    var labels: [String] {
        var n: [String: Int] = [:]
        for t in data.tasks { for l in t.labels { n[l, default: 0] += 1 } }
        for l in data.labelColors.keys where n[l] == nil { n[l] = 0 }
        return n.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    func labelColorIndex(_ name: String) -> Int {
        data.labelColors[name] ?? name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    func setLabelColor(_ name: String, _ index: Int) {
        data.labelColors[name] = index
        commit()
    }

    func renameLabel(_ old: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        guard !n.isEmpty, n != old else { return }
        for i in data.tasks.indices {
            if let k = data.tasks[i].labels.firstIndex(of: old) {
                data.tasks[i].labels[k] = n
                data.tasks[i].labels = data.tasks[i].labels.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
            }
        }
        if let c = data.labelColors.removeValue(forKey: old) { data.labelColors[n] = c }
        if taskLabelFilter == old { taskLabelFilter = n }
        commit()
    }

    func deleteLabel(_ name: String) {
        let before = data
        for i in data.tasks.indices { data.tasks[i].labels.removeAll { $0 == name } }
        data.labelColors[name] = nil
        if taskLabelFilter == name { taskLabelFilter = nil }
        commit()
        toast = Toast(message: "Removed label \(name)", undo: before)
    }

    @discardableResult
    func addTask(_ t: TaskItem) -> UUID {
        var t = t
        t.title = t.title.trimmingCharacters(in: .whitespaces)
        guard !t.title.isEmpty else { return t.id }
        data.tasks.append(t)
        commit()
        return t.id
    }

    func updateTask(_ t: TaskItem) {
        guard let i = taskIndex(t.id) else { return }
        data.tasks[i] = t
        commit()
    }

    func toggleTask(_ id: UUID) {
        guard let i = taskIndex(id) else { return }
        let before = data
        let done = !data.tasks[i].isDone
        data.tasks[i].doneAt = done ? .now : nil
        commit()
        if done {
            Notifier.shared.clearDelivered(for: id)
            toast = Toast(message: "Done · \(data.tasks[i].title)", undo: before)
        }
    }

    func completeTask(_ id: UUID) {
        guard let i = taskIndex(id), !data.tasks[i].isDone else { return }
        data.tasks[i].doneAt = .now
        commit()
        Notifier.shared.clearDelivered(for: id)
    }

    /// nil moves it to the Inbox.
    func moveTask(_ id: UUID, to day: Date?) {
        guard let i = taskIndex(id) else { return }
        data.tasks[i].day = day.map(Day.key)
        commit()
    }

    func setPriority(_ id: UUID, _ p: Int) {
        guard let i = taskIndex(id) else { return }
        data.tasks[i].priority = p
        commit()
    }

    func deleteTask(_ id: UUID) {
        guard let i = taskIndex(id) else { return }
        let before = data
        let title = data.tasks[i].title
        data.tasks.remove(at: i)
        Notifier.shared.clearDelivered(for: id)
        commit()
        toast = Toast(message: "Deleted \(title)", undo: before)
    }

    func clearDoneTasks() {
        let before = data
        data.tasks.removeAll { $0.isDone && !$0.doneToday(today) }
        commit()
        toast = Toast(message: "Cleared finished tasks", undo: before)
    }
}
