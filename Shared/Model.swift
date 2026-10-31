import Foundation

// MARK: - Journey

/// A journey is `length` reps split into 8 levels. The default is 60 (3, 5, 6, 7, 8, 9, 10, 12);
/// other lengths scale those proportions, so the early levels always move quickly.
enum Journey {
    static let defaultLength = 60
    static let levelCount = 8
    private static let baseReps = [3, 5, 6, 7, 8, 9, 10, 12]

    static func levelReps(length: Int) -> [Int] {
        let length = max(levelCount, length)
        if length == 60 { return baseReps }
        // largest-remainder rounding, every level at least 1 rep
        let raw = baseReps.map { Double($0) * Double(length) / 60 }
        var out = raw.map { max(1, Int($0)) }
        var short = length - out.reduce(0, +)
        let order = raw.indices.sorted { (raw[$0] - floor(raw[$0])) > (raw[$1] - floor(raw[$1])) }
        var i = 0
        while short > 0 { out[order[i % order.count]] += 1; short -= 1; i += 1 }
        while short < 0, let j = out.indices.reversed().first(where: { out[$0] > 1 }) { out[j] -= 1; short += 1 }
        return out
    }

    static func cumulative(length: Int) -> [Int] {
        var sum = 0
        return levelReps(length: length).map { sum += $0; return sum }
    }

    static func level(forReps reps: Int, length: Int = defaultLength) -> Int {
        cumulative(length: length).firstIndex { reps < $0 } ?? levelCount - 1
    }
    static func levelStart(_ level: Int, length: Int = defaultLength) -> Int {
        level == 0 ? 0 : cumulative(length: length)[level - 1]
    }
    static func placed(level: Int, reps: Int, length: Int = defaultLength) -> Int {
        max(0, min(levelReps(length: length)[level], reps - levelStart(level, length: length)))
    }

    static let names = ["Spark", "Foothills", "Fog", "The Long Field", "Storm", "Ridge", "Ascent", "Peak"]
    static let symbols = ["sparkle", "mountain.2.fill", "cloud.fog.fill", "wind", "cloud.bolt.fill", "triangle.fill", "figure.stairs", "diamond.fill"]
    static let copy = [
        "Starting feels easy. Enjoy that, and keep it small enough to do on a bad day.",
        "The first friction shows up. Shrink the habit if you need to. Showing up is the rep.",
        "The novelty fades and motivation dips. That is normal. Routines carry you when motivation won't.",
        "Nothing dramatic happens here. Boring is fine. Boring is where habits set.",
        "Life gets in the way. Missed days don't cost you any pieces. Pick up where you left off.",
        "You start to see yourself as someone who does this. Identity is the real prize.",
        "It takes less effort now. Notice how automatic it has become.",
        "Final stretch. When you place the gem, the habit is yours.",
    ]
}

// MARK: - Days

/// Days are stored as "yyyy-MM-dd" keys in the user's current time zone, so string order is date order.
enum Day {
    static var calendar: Calendar {
        var c = Calendar.current
        if let first = weekStartOverride { c.firstWeekday = first }
        return c
    }
    /// 1 = Sunday, 2 = Monday. Set from settings by the app and the widget.
    nonisolated(unsafe) static var weekStartOverride: Int?

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(_ date: Date) -> String { formatter.timeZone = .current; return formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.timeZone = .current; return formatter.date(from: key) }
    static func start(_ date: Date = .now) -> Date { calendar.startOfDay(for: date) }
    static func add(_ days: Int, to date: Date) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
    static func between(_ a: Date, _ b: Date) -> Int { calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0 }
    static func weekday(_ date: Date) -> Int { calendar.component(.weekday, from: date) } // 1 = Sunday
    static func startOfWeek(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? start(date) }
    /// Weekday numbers (1 = Sunday) in display order for the configured week start.
    static var orderedWeekdays: [Int] { let f = calendar.firstWeekday; return (0..<7).map { (f - 1 + $0) % 7 + 1 } }
}

// MARK: - Habit

struct ReminderTime: Codable, Hashable, Identifiable {
    var hour: Int
    var minute: Int
    /// Empty = every scheduled day of the habit.
    var weekdays: Set<Int> = []
    var id: Int { hour * 60 + minute }

    init(hour: Int, minute: Int, weekdays: Set<Int> = []) {
        self.hour = hour; self.minute = minute; self.weekdays = weekdays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hour = c.value(.hour, 8)
        minute = c.value(.minute, 0)
        weekdays = c.value(.weekdays, [])
    }

    func label(_ format: TimeFormat = .system) -> String {
        switch format {
        case .h24: return String(format: "%02d:%02d", hour, minute)
        case .h12: return "\(hour % 12 == 0 ? 12 : hour % 12):\(String(format: "%02d", minute)) \(hour < 12 ? "AM" : "PM")"
        case .system:
            let d = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            return d.formatted(date: .omitted, time: .shortened)
        }
    }
    var label: String { label(.system) }

    /// Parses "6:45pm", "18:45", "645p", "7am", "7".
    static func parse(_ text: String) -> ReminderTime? {
        let s = text.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ".", with: "")
        var digits = "", suffix = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) } else if ch == ":" || ch == "h" { continue } else { suffix.append(ch) }
        }
        guard !digits.isEmpty, digits.count <= 4, ["", "a", "am", "p", "pm"].contains(suffix) else { return nil }
        var h: Int, m = 0
        if digits.count <= 2 { h = Int(digits)! } else {
            h = Int(digits.prefix(digits.count - 2))!
            m = Int(digits.suffix(2))!
        }
        if suffix.hasPrefix("p") { guard h <= 12 else { return nil }; h = h % 12 + 12 }
        if suffix.hasPrefix("a") { guard h <= 12 else { return nil }; h = h % 12 }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return ReminderTime(hour: h, minute: m)
    }
}

enum GoalKind: String, Codable, CaseIterable { case once, count, amount }

enum HabitState: String, Codable {
    case active   // on a journey
    case endless  // mastered, still tracking
    case retired  // on the trophy shelf
}

struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var goal = ""
    var groupID: UUID?
    var weekdays: Set<Int> = Set(1...7)
    var reminders: [ReminderTime] = []
    var remindersOn = true
    var reminderNote = ""
    /// Day key → progress. For `once` habits the value is 1. A day counts as a rep when value ≥ target.
    var log: [String: Double] = [:]
    var goalKind: GoalKind = .once
    var target: Double = 1
    var unit = ""
    var journeyLength = Journey.defaultLength
    var created = Date()
    /// Reps for the current journey count from this day key onward.
    var journeyStart = "0000-00-00"
    var round = 0
    var state: HabitState = .active
    var masteryAsked = false
    var order = 0

    init(name: String, goal: String = "", groupID: UUID? = nil, reminders: [ReminderTime] = [], order: Int = 0) {
        self.name = name; self.goal = goal; self.groupID = groupID; self.reminders = reminders; self.order = order
    }

    var effectiveTarget: Double { goalKind == .once ? 1 : max(1, target) }

    func value(on date: Date) -> Double { log[Day.key(date)] ?? 0 }
    func progress(on date: Date) -> Double { min(1, value(on: date) / effectiveTarget) }
    func isDone(on date: Date) -> Bool { value(on: date) >= effectiveTarget }
    func isScheduled(_ date: Date) -> Bool { weekdays.contains(Day.weekday(date)) }

    /// Day keys that count as a rep, sorted.
    var doneKeys: [String] { log.filter { $0.value >= effectiveTarget }.keys.sorted() }
    var done: Set<String> { Set(doneKeys) }

    var reps: Int { log.reduce(0) { ($1.key >= journeyStart && $1.value >= effectiveTarget) ? $0 + 1 : $0 } }
    var totalReps: Int { log.reduce(0) { $1.value >= effectiveTarget ? $0 + 1 : $0 } }
    var journeyReps: Int { min(reps, journeyLength) }
    var level: Int { Journey.level(forReps: journeyReps, length: journeyLength) }
    var levelReps: [Int] { Journey.levelReps(length: journeyLength) }
    var levelStart: Int { Journey.levelStart(level, length: journeyLength) }
    var placedInLevel: Int { Journey.placed(level: level, reps: journeyReps, length: journeyLength) }
    var isMastered: Bool { reps >= journeyLength }
    var needsMasteryChoice: Bool { state == .active && isMastered && !masteryAsked }

    var lastDone: Date? { doneKeys.last.flatMap(Day.date) }
    var firstDone: Date? { doneKeys.first.flatMap(Day.date) }
    /// Dates of each rep in the current journey, oldest first.
    var journeyDates: [Date] { doneKeys.filter { $0 >= journeyStart }.compactMap(Day.date) }

    func daysAway(today: Date) -> Int { Day.between(lastDone ?? created, today) }

    /// 0 = clean. Starts after `after` days away and thickens over two weeks. One check clears it.
    func dust(today: Date, after: Int = 7) -> Double {
        guard after > 0, state != .retired, !isDone(on: today) else { return 0 }
        let away = daysAway(today: today)
        guard away >= after else { return 0 }
        return min(1, 0.35 + Double(away - after) / 14)
    }

    /// How many of the last `window` days you showed up, out of the days that were scheduled.
    func consistency(today: Date, window: Int = 30) -> (shown: Int, scheduled: Int) {
        let windowStart = Day.add(-(window - 1), to: today)
        let origin = min(Day.start(created), firstDone ?? today)
        var day = max(windowStart, origin)
        var shown = 0, scheduled = 0
        while day <= today {
            if isScheduled(day) { scheduled += 1 }
            if isDone(on: day) { shown += 1 }
            day = Day.add(1, to: day)
        }
        return (shown, max(scheduled, shown))
    }

    func count(from a: Date, to b: Date) -> Int {
        let ka = Day.key(a), kb = Day.key(b)
        return log.reduce(0) { ($1.key >= ka && $1.key <= kb && $1.value >= effectiveTarget) ? $0 + 1 : $0 }
    }

    /// Average reps per calendar day since the journey began (used for the projected pace).
    func pace(today: Date) -> Double {
        let dates = journeyDates
        guard let first = dates.first else { return 0 }
        let span = max(7, Day.between(first, today) + 1)
        return Double(dates.count) / Double(span)
    }

    func projectedFinish(today: Date) -> Date? {
        let left = journeyLength - journeyReps
        guard left > 0 else { return nil }
        let p = pace(today: today)
        guard p > 0 else { return nil }
        return Day.add(Int((Double(left) / p).rounded(.up)), to: today)
    }

    var goalText: String {
        switch goalKind {
        case .once: return goal
        case .count: return "\(Int(effectiveTarget))× a day" + (goal.isEmpty ? "" : " · \(goal)")
        case .amount: return "\(Self.fmt(effectiveTarget)) \(unit)".trimmingCharacters(in: .whitespaces) + (goal.isEmpty ? "" : " · \(goal)")
        }
    }

    func progressText(on date: Date) -> String {
        switch goalKind {
        case .once: return ""
        case .count: return "\(Int(value(on: date))) / \(Int(effectiveTarget))×"
        case .amount: return "\(Self.fmt(value(on: date))) / \(Self.fmt(effectiveTarget)) \(unit)"
        }
    }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

    var scheduleText: String {
        if weekdays.count == 7 { return "Every day" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return Day.orderedWeekdays.filter(weekdays.contains).map { symbols[$0 - 1] }.joined(separator: " ")
    }
}

struct HabitGroup: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var order = 0
}

// MARK: - Settings

enum TimeFormat: String, Codable, CaseIterable { case system, h12, h24 }
enum StartTab: String, Codable, CaseIterable { case today, journey, stats, all, tasks }
enum PaneMode: String, Codable, CaseIterable { case auto, always, never }
enum Celebration: String, Codable, CaseIterable { case full, calm, off }
enum MasteryDefault: String, Codable, CaseIterable { case ask, keepGoing, retire }
enum MenuBarLabel: String, Codable, CaseIterable { case count, icon, next }

struct AppSettings: Codable, Hashable {
    var skin = "carbon"
    // General
    var weekStart = 0              // 0 = system, 1 = Sunday, 2 = Monday
    var startTab: StartTab = .today
    var pane: PaneMode = .auto
    var timeFormat: TimeFormat = .system
    // Check-in
    var holdSeconds = 0.85
    var holdToUncheck = true
    var sound = true
    var volume = 0.6
    var haptics = true
    var celebration: Celebration = .full
    // Journey
    var defaultJourneyLength = 60
    var dustDays = 7               // 0 = off
    var consistencyWindow = 30
    var mastery: MasteryDefault = .ask
    var showPace = true
    // Reminders
    var defaultReminder = ReminderTime(hour: 8, minute: 0)
    var snoozeMinutes = 30
    var catchUpOn = false
    var catchUpTime = ReminderTime(hour: 21, minute: 0)
    var quietOn = false
    var quietStart = ReminderTime(hour: 23, minute: 0)
    var quietEnd = ReminderTime(hour: 7, minute: 0)
    // Menu bar & widgets
    var menuBar = true
    var menuBarLabel: MenuBarLabel = .count
    var menuBarTasks = true
    var widgetsFollowSkin = true
    // Data
    var backups = true
    var seenGuide = false
    var examples: [String] = ["Meditate", "Read", "Walk", "Stretch", "Journal", "No phone in bed", "Drink water", "Practice"]

    var widgetSkin: String { widgetsFollowSkin ? skin : "carbon" }
}

struct AppData: Codable {
    var groups: [HabitGroup] = []
    var habits: [Habit] = []
    var tasks: [TaskItem] = []
    /// Label name → index into the label palette.
    var labelColors: [String: Int] = [:]
    var settings = AppSettings()
    var version = 2
}

// MARK: - Lenient decoding (missing keys fall back to defaults, so the file format can grow)

extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, _ fallback: @autoclosure () -> T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback()
    }
}

extension Habit {
    private enum LegacyKeys: String, CodingKey { case done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = Habit(name: "")
        id = c.value(.id, base.id)
        name = c.value(.name, "Habit")
        goal = c.value(.goal, base.goal)
        groupID = c.value(.groupID, nil)
        weekdays = c.value(.weekdays, base.weekdays)
        reminders = c.value(.reminders, base.reminders)
        remindersOn = c.value(.remindersOn, base.remindersOn)
        reminderNote = c.value(.reminderNote, "")
        goalKind = c.value(.goalKind, .once)
        target = c.value(.target, 1)
        unit = c.value(.unit, "")
        journeyLength = c.value(.journeyLength, Journey.defaultLength)
        created = c.value(.created, base.created)
        journeyStart = c.value(.journeyStart, base.journeyStart)
        round = c.value(.round, base.round)
        state = c.value(.state, base.state)
        masteryAsked = c.value(.masteryAsked, base.masteryAsked)
        order = c.value(.order, base.order)
        log = c.value(.log, [:])
        // v1 files stored a set of done day keys
        if log.isEmpty, let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let keys = try? legacy.decodeIfPresent(Set<String>.self, forKey: .done) {
            log = Dictionary(uniqueKeysWithValues: keys.map { ($0, 1.0) })
        }
    }
}

extension AppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let b = AppSettings()
        skin = c.value(.skin, b.skin)
        weekStart = c.value(.weekStart, b.weekStart)
        startTab = c.value(.startTab, b.startTab)
        pane = c.value(.pane, b.pane)
        timeFormat = c.value(.timeFormat, b.timeFormat)
        holdSeconds = c.value(.holdSeconds, b.holdSeconds)
        holdToUncheck = c.value(.holdToUncheck, b.holdToUncheck)
        sound = c.value(.sound, b.sound)
        volume = c.value(.volume, b.volume)
        haptics = c.value(.haptics, b.haptics)
        celebration = c.value(.celebration, b.celebration)
        defaultJourneyLength = c.value(.defaultJourneyLength, b.defaultJourneyLength)
        dustDays = c.value(.dustDays, b.dustDays)
        consistencyWindow = c.value(.consistencyWindow, b.consistencyWindow)
        mastery = c.value(.mastery, b.mastery)
        showPace = c.value(.showPace, b.showPace)
        defaultReminder = c.value(.defaultReminder, b.defaultReminder)
        snoozeMinutes = c.value(.snoozeMinutes, b.snoozeMinutes)
        catchUpOn = c.value(.catchUpOn, b.catchUpOn)
        catchUpTime = c.value(.catchUpTime, b.catchUpTime)
        quietOn = c.value(.quietOn, b.quietOn)
        quietStart = c.value(.quietStart, b.quietStart)
        quietEnd = c.value(.quietEnd, b.quietEnd)
        menuBar = c.value(.menuBar, b.menuBar)
        menuBarLabel = c.value(.menuBarLabel, b.menuBarLabel)
        menuBarTasks = c.value(.menuBarTasks, b.menuBarTasks)
        widgetsFollowSkin = c.value(.widgetsFollowSkin, b.widgetsFollowSkin)
        backups = c.value(.backups, b.backups)
        seenGuide = c.value(.seenGuide, b.seenGuide)
        examples = c.value(.examples, b.examples)
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        groups = c.value(.groups, [])
        habits = c.value(.habits, [])
        tasks = c.value(.tasks, [])
        labelColors = c.value(.labelColors, [:])
        settings = c.value(.settings, AppSettings())
        version = 2
    }
}

/// Small deterministic RNG for decorative noise and demo data.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

// MARK: - Storage

/// One JSON file in ~/Library/Application Support/Ritual, shared with the widget extension.
enum Storage {
    static let realHome: URL = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
    static let folder = realHome.appendingPathComponent("Library/Application Support/Ritual", isDirectory: true)
    static let backupFolder = folder.appendingPathComponent("Backups", isDirectory: true)
    static var isDemo: Bool { CommandLine.arguments.contains("--demo") }
    static var file: URL { folder.appendingPathComponent(isDemo ? "demo.json" : "data.json") }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// `readOnly` callers (the widget, notification checks) never move a bad file aside.
    static func load(readOnly: Bool = false) -> AppData? {
        guard let raw = try? Data(contentsOf: file) else { return nil }
        do {
            return try decoder.decode(AppData.self, from: raw)
        } catch {
            if readOnly { return nil }
            // Never overwrite a file we couldn't read; keep it aside for recovery.
            let backup = folder.appendingPathComponent("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file, to: backup)
            NSLog("Ritual: could not read \(file.path) (\(error)); moved to \(backup.lastPathComponent)")
            return nil
        }
    }

    static func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(data).write(to: file, options: .atomic)
    }

    /// One copy per day, newest 14 kept.
    static func backupIfNeeded() {
        guard !isDemo, FileManager.default.fileExists(atPath: file.path) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        let target = backupFolder.appendingPathComponent("data-\(Day.key(.now)).json")
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: file, to: target) }
        let all = ((try? fm.contentsOfDirectory(atPath: backupFolder.path)) ?? []).filter { $0.hasPrefix("data-") }.sorted()
        for old in all.dropLast(14) { try? fm.removeItem(at: backupFolder.appendingPathComponent(old)) }
    }
}
