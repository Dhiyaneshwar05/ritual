// Logic checks for journey math, goals, dust, consistency, time parsing and migration. Run: ./test.sh
import Foundation
var failures = 0
func expect(_ ok: Bool, _ msg: String, line: Int = #line) { if !ok { failures += 1; print("✗ line \(line): \(msg)") } }
let today = Day.start()
func habit(doneBack: [Int], createdBack: Int = 90) -> Habit {
    var h = Habit(name: "T"); h.created = Day.add(-createdBack, to: today)
    for b in doneBack { h.log[Day.key(Day.add(-b, to: today))] = 1 }
    return h
}

// journey lengths
expect(Journey.levelReps(length: 60) == [3, 5, 6, 7, 8, 9, 10, 12], "60 keeps the hand-tuned split")
for n in [8, 21, 30, 45, 90, 100, 365] {
    let r = Journey.levelReps(length: n)
    expect(r.reduce(0, +) == n && r.count == 8 && r.allSatisfy { $0 >= 1 }, "length \(n) splits into 8 positive levels: \(r)")
}
expect(Journey.level(forReps: 0) == 0 && Journey.level(forReps: 2) == 0 && Journey.level(forReps: 3) == 1, "level boundaries")
expect(Journey.level(forReps: 59) == 7 && Journey.level(forReps: 60) == 7 && Journey.level(forReps: 99) == 7, "last level clamps")
expect(Journey.placed(level: 1, reps: 5) == 2, "pieces placed within a level")

// reps, gaps, mastery, custom length
let gappy = habit(doneBack: [80, 60, 40, 20, 1])
expect(gappy.reps == 5, "reps count check-ins, not streaks")
var short = habit(doneBack: Array(1...30)); short.journeyLength = 30
expect(short.isMastered && short.journeyReps == 30 && short.level == 7, "30-rep journey masters at 30")
var m = habit(doneBack: Array(0...59))
expect(m.isMastered && m.journeyReps == 60, "mastered at 60")
m.journeyStart = Day.key(Day.add(1, to: today))
expect(m.reps == 0 && m.level == 0 && m.totalReps == 60, "new journey starts from zero, history kept")

// goal kinds
var water = Habit(name: "Water"); water.goalKind = .count; water.target = 8
water.log[Day.key(today)] = 3
expect(!water.isDone(on: today) && abs(water.progress(on: today) - 0.375) < 0.001 && water.reps == 0, "count habit partial")
water.log[Day.key(today)] = 8
expect(water.isDone(on: today) && water.reps == 1, "count habit full = one rep")
var pages = Habit(name: "Read"); pages.goalKind = .amount; pages.target = 10; pages.unit = "pages"
pages.log[Day.key(today)] = 12
expect(pages.isDone(on: today) && pages.progressText(on: today) == "12 / 10 pages", "amount habit over target")

// dust
expect(habit(doneBack: [3]).dust(today: today) == 0, "no dust under 7 days")
expect(habit(doneBack: [7]).dust(today: today) > 0, "dust at 7 days")
expect(habit(doneBack: [4]).dust(today: today, after: 3) > 0, "dust threshold is configurable")
expect(habit(doneBack: [40]).dust(today: today, after: 0) == 0, "dust can be turned off")
expect(habit(doneBack: [0, 30]).dust(today: today) == 0, "a check today clears dust")
expect(habit(doneBack: [100]).dust(today: today) == 1, "dust caps at 1")

// consistency respects schedule
var mwf = habit(doneBack: Array(0..<30)); mwf.weekdays = [2, 4, 6]
let c = mwf.consistency(today: today)
expect(c.scheduled >= c.shown && c.shown == 30, "extra check-ins never exceed denominator: \(c)")
expect(habit(doneBack: [0, 1], createdBack: 1).consistency(today: today) == (2, 2), "window starts at creation")
expect(habit(doneBack: Array(0..<14), createdBack: 60).consistency(today: today, window: 14) == (14, 14), "window size is configurable")

// time parsing
func t(_ s: String) -> String? { ReminderTime.parse(s).map { "\($0.hour):\($0.minute)" } }
expect(t("6:45pm") == "18:45", "6:45pm"); expect(t("7am") == "7:0", "7am"); expect(t("12am") == "0:0", "12am")
expect(t("12:30 PM") == "12:30", "12:30 PM"); expect(t("21:30") == "21:30", "21:30"); expect(t("930p") == "21:30", "930p")
expect(t("7") == "7:0", "bare hour"); expect(t("25:00") == nil, "rejects 25:00"); expect(t("13pm") == nil, "rejects 13pm")
expect(t("hello") == nil, "rejects text"); expect(t("7:61") == nil, "rejects bad minutes")

// pace
let paced = habit(doneBack: Array(stride(from: 27, through: 0, by: -2)))
expect(paced.pace(today: today) > 0.4 && paced.pace(today: today) < 0.6, "pace ≈ every other day: \(paced.pace(today: today))")
expect(paced.projectedFinish(today: today) != nil, "projection exists while not mastered")

// v1 file migration + lenient decoding
let json = #"{"habits":[{"name":"Old","done":["2026-01-01","2026-01-02"]}],"settings":{"skin":"paper"},"future":1}"#.data(using: .utf8)!
let decoded = try! Storage.decoder.decode(AppData.self, from: json)
let old = decoded.habits.first!
expect(old.name == "Old" && old.weekdays.count == 7 && old.totalReps == 2 && old.journeyLength == 60, "v1 done set migrates to log")
expect(decoded.settings.skin == "paper" && decoded.settings.holdSeconds == 0.85 && decoded.settings.dustDays == 7, "missing settings get defaults")
let round = try! Storage.decoder.decode(AppData.self, from: Storage.encoder.encode(decoded))
expect(round.habits.first?.log == old.log, "round-trip keeps the log")

// tasks: quick-add parsing
let sat = Day.date("2026-10-31")! // a Saturday
var q = TaskParser.parse("Send invoice tomorrow 4pm #work !1", today: sat)
expect(q.title == "Send invoice" && q.day == .on(Day.add(1, to: sat)) && q.time == ReminderTime(hour: 16, minute: 0) && q.labels == ["work"] && q.priority == 1, "full quick add: \(q)")
q = TaskParser.parse("Walk 10000 steps", today: sat)
expect(q.title == "Walk 10000 steps" && q.time == nil && q.day == .unset, "bare numbers stay in the title")
q = TaskParser.parse("Call the bank at 11:30 am mon #Bank !!", today: sat)
expect(q.title == "Call the bank" && q.time == ReminderTime(hour: 11, minute: 30) && q.day == .on(Day.add(2, to: sat)) && q.labels == ["bank"] && q.priority == 2, "at + spaced am, weekday, !!: \(q)")
q = TaskParser.parse("Plan trip sat no date", today: sat)
expect(q.title == "Plan trip" && q.day == .inbox, "last day word wins; same weekday means next week")
q = TaskParser.parse("Standup 17:30", today: sat)
expect(q.time == ReminderTime(hour: 17, minute: 30) && q.title == "Standup", "24h time")
expect(TaskParser.parse("Pay rent next week", today: sat).day == .on(Day.add(7, to: Day.startOfWeek(sat))), "next week = start of next week")

// tasks: lateness, done-today, ordering, decoding
var t = TaskItem(title: "Late", day: Day.key(Day.add(-2, to: today)))
expect(t.daysLate(today: today) == 2, "two days late")
t.doneAt = .now
expect(t.daysLate(today: today) == 0 && t.doneToday(today) && !t.doneToday(Day.add(1, to: today)), "done today only")
let ta = TaskItem(title: "a", priority: 0), tb = TaskItem(title: "b", priority: 2), tc = TaskItem(title: "c", remind: ReminderTime(hour: 9, minute: 0), priority: 2)
expect([ta, tb, tc].sorted(by: TaskItem.ordered).map(\.title) == ["c", "b", "a"], "priority then time, none last")
let tj = #"{"tasks":[{"title":"X","priority":7,"labels":["home"]}]}"#.data(using: .utf8)!
let td = try! Storage.decoder.decode(AppData.self, from: tj)
expect(td.tasks.first?.priority == 3 && td.tasks.first?.day == nil && td.habits.isEmpty, "lenient task decoding")

print(failures == 0 ? "✓ all logic checks passed" : "\(failures) failed"); exit(failures == 0 ? 0 : 1)
