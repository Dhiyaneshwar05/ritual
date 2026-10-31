import Foundation

/// A one-off to-do. Plain on purpose: a title, an optional day and reminder, labels and an optional priority.
struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var note = ""
    /// Day.key of the day it's due. nil = Inbox.
    var day: String?
    /// Reminder on that day. Ignored while the task has no day.
    var remind: ReminderTime?
    var labels: [String] = []
    /// 0 none · 1 high · 2 medium · 3 low
    var priority = 0
    var doneAt: Date?
    var created = Date()

    init(title: String, day: String? = nil, remind: ReminderTime? = nil, labels: [String] = [], priority: Int = 0) {
        self.title = title; self.day = day; self.remind = remind; self.labels = labels; self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = TaskItem(title: "")
        id = c.value(.id, base.id)
        title = c.value(.title, "Task")
        note = c.value(.note, "")
        day = c.value(.day, nil)
        remind = c.value(.remind, nil)
        labels = c.value(.labels, [])
        priority = min(3, max(0, c.value(.priority, 0)))
        doneAt = c.value(.doneAt, nil)
        created = c.value(.created, base.created)
    }

    var isDone: Bool { doneAt != nil }
    var date: Date? { day.flatMap(Day.date) }

    /// When the reminder fires, if it has one.
    var remindAt: Date? {
        guard let d = date, let r = remind else { return nil }
        return Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: d)
    }

    /// Days past its due day while still open (0 when on time, done, or undated).
    func daysLate(today: Date) -> Int {
        guard !isDone, let d = date else { return 0 }
        return max(0, Day.between(d, today))
    }

    /// Done on `today`: still shown crossed out until the day ends.
    func doneToday(_ today: Date) -> Bool { doneAt.map { Day.start($0) == Day.start(today) } ?? false }

    static let priorityNames = ["None", "High", "Medium", "Low"]
    static func bangs(_ p: Int) -> String { p == 0 ? "" : String(repeating: "!", count: 4 - p) }

    /// Open first, then priority (none last), then reminder time, then oldest first.
    static func ordered(_ a: TaskItem, _ b: TaskItem) -> Bool {
        if a.isDone != b.isDone { return !a.isDone }
        let pa = a.priority == 0 ? 9 : a.priority, pb = b.priority == 0 ? 9 : b.priority
        if pa != pb { return pa < pb }
        let ta = a.remind?.id ?? 9999, tb = b.remind?.id ?? 9999
        if ta != tb { return ta < tb }
        return a.created < b.created
    }
}

/// Quick-add rules, no guessing beyond these:
/// `#label` · `!1` `!2` `!3` (or `!!!` `!!` `!`) · today / tomorrow / mon…sun / next week / no date ·
/// a time with am/pm or a colon ("5pm", "5:30 pm", "17:30", "at 9am").
enum TaskParser {
    enum DayChoice: Equatable { case unset, inbox, on(Date) }

    struct Result: Equatable {
        var title = ""
        var day: DayChoice = .unset
        var time: ReminderTime?
        var labels: [String] = []
        var priority: Int?
    }

    private static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "mon": 2, "monday": 2, "tue": 3, "tues": 3, "tuesday": 3, "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "fri": 6, "friday": 6, "sat": 7, "saturday": 7,
    ]

    static func parse(_ text: String, today: Date) -> Result {
        var r = Result()
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var keep: [String] = []
        var i = 0
        func lower(_ k: Int) -> String { words[k].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;")) }
        while i < words.count {
            let w = lower(i)
            let next = i + 1 < words.count ? lower(i + 1) : ""
            if w.hasPrefix("#"), w.count > 1 {
                let l = String(w.dropFirst())
                if !r.labels.contains(l) { r.labels.append(l) }
            } else if ["!1", "!2", "!3"].contains(w) {
                r.priority = Int(w.dropFirst())
            } else if ["!!!", "!!", "!"].contains(w) {
                r.priority = 4 - w.count
            } else if w == "today" || w == "tonight" {
                r.day = .on(today)
            } else if ["tomorrow", "tmrw", "tmr"].contains(w) {
                r.day = .on(Day.add(1, to: today))
            } else if w == "next", next == "week" {
                r.day = .on(Day.add(7, to: Day.startOfWeek(today))); i += 1
            } else if w == "no", next == "date" {
                r.day = .inbox; i += 1
            } else if w == "someday" {
                r.day = .inbox
            } else if let wd = weekdays[w] {
                let ahead = (wd - Day.weekday(today) + 7) % 7
                r.day = .on(Day.add(ahead == 0 ? 7 : ahead, to: today))
            } else if let t = time(w, next) {
                r.time = t.time; i += t.extra
                if keep.last?.lowercased() == "at" { keep.removeLast() }
            } else {
                keep.append(words[i])
            }
            i += 1
        }
        words = keep
        r.title = words.joined(separator: " ")
        return r
    }

    /// A time needs am/pm or a colon so "10000 steps" or "Read 2 chapters" stay in the title.
    private static func time(_ w: String, _ next: String) -> (time: ReminderTime, extra: Int)? {
        if ["am", "pm", "a.m.", "p.m."].contains(next), w.allSatisfy({ $0.isNumber || $0 == ":" }), let t = ReminderTime.parse(w + next) {
            return (t, 1)
        }
        let hasSuffix = w.hasSuffix("am") || w.hasSuffix("pm")
        guard hasSuffix || w.contains(":"), w.first?.isNumber == true else { return nil }
        return ReminderTime.parse(w).map { ($0, 0) }
    }
}
