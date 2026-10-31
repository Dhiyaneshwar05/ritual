import WidgetKit
import SwiftUI
import AppIntents

// The widget extension is sandboxed. It reads the app's JSON file through a home-relative
// read-only entitlement, and a click opens ritual://toggle/<id> so the app does the write.

private final class BundleToken {}

// MARK: - Habit picker (each widget can show a chosen habit)

struct HabitChoice: AppEntity {
    let id: String
    let name: String
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Habit"
    static let defaultQuery = HabitQuery()
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct HabitQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [HabitChoice] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [HabitChoice] { all() }
    private func all() -> [HabitChoice] {
        (Storage.load(readOnly: true)?.habits ?? []).filter { $0.state != .retired }.map { HabitChoice(id: $0.id.uuidString, name: $0.name) }
    }
}

struct PickHabit: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose habit"
    static let description = IntentDescription("Pick which habit this widget shows. Leave empty for your next habit.")
    @Parameter(title: "Habit") var habit: HabitChoice?
    init() {}
}

// MARK: - Timeline

struct Entry: TimelineEntry {
    let date: Date
    let data: AppData
    var pickedID: String?

    var skin: Skin { Skin.named(data.settings.widgetSkin) }
    var habits: [Habit] {
        let groups = Dictionary(uniqueKeysWithValues: data.groups.map { ($0.id, $0.order) })
        return data.habits.filter { $0.state != .retired }
            .sorted { (groups[$0.groupID ?? UUID()] ?? 999, $0.order) < (groups[$1.groupID ?? UUID()] ?? 999, $1.order) }
    }
    var featured: Habit? {
        if let pickedID, let h = habits.first(where: { $0.id.uuidString == pickedID }) { return h }
        return habits.first { !$0.isDone(on: date) && $0.isScheduled(date) } ?? habits.first
    }
}

private func load() -> AppData {
    Fonts.register(in: Bundle(for: BundleToken.self))
    let d = Storage.load(readOnly: true) ?? PreviewData.make()
    Day.weekStartOverride = d.settings.weekStart == 0 ? nil : d.settings.weekStart
    return d
}

private func nextRefresh() -> Date {
    // just after midnight so "today" rolls over; the app also reloads after each change
    min(Day.add(1, to: Day.start()).addingTimeInterval(5), .now.addingTimeInterval(1800))
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, data: PreviewData.make()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now, data: load())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, data: load())], policy: .after(nextRefresh())))
    }
}

struct PickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, data: PreviewData.make()) }
    func snapshot(for configuration: PickHabit, in context: Context) async -> Entry {
        Entry(date: .now, data: load(), pickedID: configuration.habit?.id)
    }
    func timeline(for configuration: PickHabit, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [Entry(date: .now, data: load(), pickedID: configuration.habit?.id)], policy: .after(nextRefresh()))
    }
}

private func toggleURL(_ h: Habit, on date: Date? = nil) -> URL {
    var s = "ritual://toggle/\(h.id.uuidString)"
    if let date { s += "?day=\(Day.key(date))" }
    return URL(string: s)!
}
private func openURL(_ h: Habit?) -> URL { URL(string: "ritual://open/\(h?.id.uuidString ?? "")")! }

/// A Link in the real widget; a plain view in offscreen previews (ImageRenderer can't draw Link).
struct TapTarget<Content: View>: View {
    let url: URL
    @ViewBuilder var content: Content
    var body: some View {
        #if WIDGET_PREVIEW
        content
        #else
        Link(destination: url) { content }
        #endif
    }
}

private struct WidgetBG: View {
    let skin: Skin
    var body: some View {
        ZStack {
            LinearGradient(colors: [skin.bgTop, skin.bgBottom], startPoint: .top, endPoint: .bottom)
            SkinGlows(skin: skin)
        }
    }
}

/// Title row used by most widgets: habit name left, small count + bar right.
private struct WTitle: View {
    let title: String
    let count: String
    var fraction: Double? = nil
    let skin: Skin
    var body: some View {
        HStack(alignment: .top) {
            Text(title).font(.display(13)).foregroundStyle(skin.fg).lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(count).font(.mono(9.5)).foregroundStyle(skin.fgDim)
                if let fraction {
                    ZStack(alignment: .leading) {
                        Capsule().fill(skin.fg.opacity(0.2))
                        Capsule().fill(skin.fg).frame(width: 40 * min(1, fraction))
                    }
                    .frame(width: 40, height: 2)
                }
            }
        }
    }
}

private struct DayChip: View {
    let habit: Habit
    let day: Date
    let skin: Skin
    var size: CGFloat = 26
    var body: some View {
        let on = habit.isDone(on: day)
        let p = habit.progress(on: day)
        ZStack {
            if on {
                Circle().fill(skin.chip)
                Image(systemName: "checkmark").font(.system(size: size * 0.38, weight: .heavy)).foregroundStyle(skin.chipFg)
            } else {
                Circle().fill(skin.chip.opacity(0.5))
                if p > 0 { Circle().trim(from: 0, to: p).stroke(skin.fg, lineWidth: 2).rotationEffect(.degrees(-90)).padding(1) }
                Text("\(Calendar.current.component(.day, from: day))").font(.mono(size * 0.36)).foregroundStyle(skin.fgDim)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Views

struct OrbWidgetView: View {
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            let done = h.isDone(on: entry.date)
            TapTarget(url: toggleURL(h)) {
                VStack(spacing: 6) {
                    MonoCaps(h.name, size: 9, color: skin.fg, weight: .bold).lineLimit(1)
                    MiniOrb(skin: skin, done: done, size: 80)
                    MonoCaps(done ? "Done · rep \(h.reps)" : h.goalKind == .once ? "\(h.journeyReps)/\(h.journeyLength)" : h.progressText(on: entry.date), size: 8)
                }
            }
            .environment(\.skin, skin)
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct WeekWidgetView: View {
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            let start = Day.startOfWeek(entry.date)
            let doneThisWeek = (0..<7).filter { h.isDone(on: Day.add($0, to: start)) }.count
            VStack(alignment: .leading, spacing: 14) {
                WTitle(title: h.name, count: "\(doneThisWeek) / 7", fraction: Double(doneThisWeek) / 7, skin: skin)
                HStack(spacing: 0) {
                    ForEach((0..<7).reversed(), id: \.self) { back in
                        let d = Day.add(-back, to: entry.date)
                        TapTarget(url: toggleURL(h, on: d)) {
                            VStack(spacing: 5) {
                                DayChip(habit: h, day: d, skin: skin, size: 28)
                                Text(back == 0 ? "TODAY" : d.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                    .font(.mono(8)).foregroundStyle(skin.fg)
                                if back == 0 { Capsule().fill(skin.accent).frame(width: 22, height: 2) }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct MonthWidgetView: View {
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            let cal = Day.calendar
            let first = cal.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
            let days = cal.range(of: .day, in: .month, for: first)?.count ?? 30
            let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
            let done = (0..<days).filter { h.isDone(on: Day.add($0, to: first)) }.count
            VStack(alignment: .leading, spacing: 8) {
                WTitle(title: h.name, count: "\(done) / \(days)", fraction: Double(done) / Double(days), skin: skin)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                    ForEach(Day.orderedWeekdays, id: \.self) { w in
                        Text(cal.veryShortWeekdaySymbols[w - 1]).font(.mono(8.5)).foregroundStyle(skin.fgDim)
                    }
                    ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(0..<days, id: \.self) { i in
                        let d = Day.add(i, to: first)
                        let future = d > entry.date
                        TapTarget(url: toggleURL(h, on: d)) {
                            DayChip(habit: h, day: d, skin: skin, size: 30)
                                .overlay { if Day.key(d) == Day.key(entry.date) && !h.isDone(on: d) { Circle().strokeBorder(skin.accent, lineWidth: 1.5) } }
                                .opacity(future ? 0.35 : 1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct TrioWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        let list = Array(entry.habits.prefix(family == .systemLarge ? 6 : 3))
        if list.isEmpty { EmptyWidget(skin: skin) } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(list) { h in
                    let done = h.isDone(on: entry.date)
                    TapTarget(url: toggleURL(h)) {
                        VStack(spacing: 6) {
                            ZStack {
                                MiniOrb(skin: skin, done: done, size: 74)
                                if !done {
                                    Text(h.name.uppercased()).font(.mono(8, .semibold)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
                                        .multilineTextAlignment(.center).lineLimit(2).frame(width: 60)
                                }
                            }
                            if family == .systemLarge {
                                Text(h.name).font(.body(11, .semibold)).foregroundStyle(skin.fg).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        }
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        let list = Array(entry.habits.prefix(family == .systemLarge ? 8 : 4))
        let done = entry.habits.filter { $0.isDone(on: entry.date) }.count
        VStack(alignment: .leading, spacing: 10) {
            WTitle(title: "Today", count: "\(done) of \(entry.habits.count)", fraction: entry.habits.isEmpty ? 0 : Double(done) / Double(entry.habits.count), skin: skin)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: family == .systemLarge ? 14 : 8) {
                ForEach(list) { h in
                    let d = h.isDone(on: entry.date)
                    TapTarget(url: toggleURL(h)) {
                        HStack(spacing: 8) {
                            MiniOrb(skin: skin, done: d, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(h.name).font(.body(12, .semibold)).foregroundStyle(skin.fg).lineLimit(1)
                                Text(h.goalKind != .once && !d ? h.progressText(on: entry.date) : "\(h.journeyReps)/\(h.journeyLength)").font(.mono(9)).foregroundStyle(skin.fgDim)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .environment(\.skin, skin)
        .containerBackground(for: .widget) { WidgetBG(skin: skin) }
    }
}

/// Dot grid of recent days. With `all`, each dot is shaded by how many habits were done.
struct GridWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Entry
    var all = false
    var body: some View {
        let skin = entry.skin
        let habits = all ? entry.habits : entry.featured.map { [$0] } ?? []
        if habits.isEmpty { EmptyWidget(skin: skin) } else {
            let weeks = family == .systemLarge ? 26 : 20
            let todayRow = Day.orderedWeekdays.firstIndex(of: Day.weekday(entry.date)) ?? 6
            VStack(alignment: .leading, spacing: 8) {
                WTitle(title: all ? "All habits" : habits[0].name, count: all ? "\(habits.count) habits" : "\(habits[0].totalReps) reps", skin: skin)
                GeometryReader { g in
                    let gap: CGFloat = 3
                    let d = min((g.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks), (g.size.height - gap * 6) / 7)
                    HStack(spacing: gap) {
                        ForEach(0..<weeks, id: \.self) { c in
                            VStack(spacing: gap) {
                                ForEach(0..<7, id: \.self) { r in
                                    let back = (weeks - 1 - c) * 7 + (todayRow - r)
                                    let day = Day.add(-back, to: entry.date)
                                    let v = back < 0 ? -1 : Double(habits.filter { $0.isDone(on: day) }.count) / Double(habits.count)
                                    Circle()
                                        .fill(v < 0 ? Color.clear : v == 0 ? skin.fg.opacity(0.1) : skin.fg.opacity(0.3 + 0.7 * v))
                                        .frame(width: d, height: d)
                                }
                            }
                        }
                    }
                }
            }
            .widgetURL(openURL(all ? nil : habits.first))
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        }
    }
}

struct ClimbWidgetView: View {
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            let dates = h.journeyDates
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(h.name).font(.display(13)).foregroundStyle(skin.fg)
                    Spacer()
                    Text("\(h.journeyReps)").font(.mono(12, .bold)).foregroundStyle(skin.accent)
                }
                GeometryReader { g in
                    let w = g.size.width, ht = g.size.height - 12
                    let first = dates.first ?? entry.date
                    let span = max(1.0, Double(Day.between(first, entry.date)))
                    let pts = dates.enumerated().map { i, d in
                        CGPoint(x: w * Double(Day.between(first, d)) / span, y: ht - ht * Double(i + 1) / Double(h.journeyLength))
                    }
                    ZStack(alignment: .topLeading) {
                        ForEach([0.0, 1 / 3, 2 / 3, 1.0], id: \.self) { f in
                            Rectangle().fill(skin.fg.opacity(0.08)).frame(height: 1).offset(y: ht * f)
                        }
                        Text("\(h.journeyLength)").font(.mono(8)).foregroundStyle(skin.fgDim).offset(y: -1)
                        if pts.count > 1 {
                            Path { p in p.move(to: CGPoint(x: pts[0].x, y: ht)); pts.forEach { p.addLine(to: $0) }; p.addLine(to: CGPoint(x: pts.last!.x, y: ht)); p.closeSubpath() }
                                .fill(skin.accent.opacity(0.2))
                            Path { p in p.addLines(pts) }.stroke(skin.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        }
                        HStack {
                            Text(first.formatted(.dateTime.month(.abbreviated)).uppercased())
                            Spacer()
                            Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                        }
                        .font(.mono(8)).foregroundStyle(skin.fgDim).offset(y: ht + 2)
                    }
                }
            }
            .widgetURL(openURL(h))
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct QuestWidgetView: View {
    let entry: Entry
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            VStack(alignment: .leading, spacing: 18) {
                WTitle(title: h.name, count: "\(h.journeyReps) / \(h.journeyLength)", fraction: Double(h.journeyReps) / Double(h.journeyLength), skin: skin)
                HStack(spacing: 0) {
                    ForEach(0..<Journey.levelCount, id: \.self) { i in
                        VStack(spacing: 6) {
                            Image(systemName: Journey.symbols[i]).font(.system(size: 15, weight: .bold))
                                .foregroundStyle(i == h.level && !h.isMastered ? skin.accent : skin.fg)
                                .opacity(i <= h.level || h.isMastered ? 1 : 0.3)
                            Capsule().fill(i == h.level && !h.isMastered ? skin.accent : .clear).frame(width: 16, height: 2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(openURL(h))
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct NumberWidgetView: View {
    let entry: Entry
    var showedUp = false
    var body: some View {
        let skin = entry.skin
        if let h = entry.featured {
            let c = h.consistency(today: entry.date, window: entry.data.settings.consistencyWindow)
            VStack(spacing: 2) {
                MonoCaps(h.name, size: 8.5, color: skin.fgDim).lineLimit(1)
                Spacer(minLength: 0)
                if showedUp {
                    (Text("\(c.scheduled == 0 ? 0 : Int((Double(c.shown) / Double(c.scheduled) * 100).rounded()))") + Text("%").font(.display(22)))
                        .font(.display(54)).foregroundStyle(skin.fg).minimumScaleFactor(0.5)
                    MonoCaps("showed up · \(entry.data.settings.consistencyWindow)d", size: 8)
                } else {
                    Text("\(h.totalReps)").font(.display(64)).foregroundStyle(skin.fg).minimumScaleFactor(0.5)
                    MonoCaps("reps", size: 8)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(openURL(h))
            .containerBackground(for: .widget) { WidgetBG(skin: skin) }
        } else { EmptyWidget(skin: skin) }
    }
}

struct EmptyWidget: View {
    let skin: Skin
    var body: some View {
        VStack(spacing: 6) {
            MiniOrb(skin: skin, done: false, size: 44)
            MonoCaps("Open Ritual to add a habit", size: 8, color: skin.fg)
        }
        .environment(\.skin, skin)
        .containerBackground(for: .widget) { WidgetBG(skin: skin) }
    }
}

// MARK: - Widgets

struct OrbWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.orb", intent: PickHabit.self, provider: PickProvider()) { OrbWidgetView(entry: $0) }
            .configurationDisplayName("Orb").description("Click to tick or untick a habit.").supportedFamilies([.systemSmall])
    }
}
struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.week", intent: PickHabit.self, provider: PickProvider()) { WeekWidgetView(entry: $0) }
            .configurationDisplayName("Week").description("Tick any day this week.").supportedFamilies([.systemMedium])
    }
}
struct MonthWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.month", intent: PickHabit.self, provider: PickProvider()) { MonthWidgetView(entry: $0) }
            .configurationDisplayName("Month").description("The whole month at a glance.").supportedFamilies([.systemLarge])
    }
}
struct TrioWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ritual.trio", provider: Provider()) { TrioWidgetView(entry: $0) }
            .configurationDisplayName("Orbs").description("Several habits, one click each.").supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ritual.today", provider: Provider()) { TodayWidgetView(entry: $0) }
            .configurationDisplayName("Today").description("All of today's habits.").supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct GridWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.grid", intent: PickHabit.self, provider: PickProvider()) { GridWidgetView(entry: $0) }
            .configurationDisplayName("Grid").description("Recent months on one habit.").supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct GridAllWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ritual.gridall", provider: Provider()) { GridWidgetView(entry: $0, all: true) }
            .configurationDisplayName("Grid · all habits").description("Brighter means more habits done.").supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct ClimbWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.climb", intent: PickHabit.self, provider: PickProvider()) { ClimbWidgetView(entry: $0) }
            .configurationDisplayName("Climb").description("Reps over time.").supportedFamilies([.systemMedium])
    }
}
struct QuestWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.quest", intent: PickHabit.self, provider: PickProvider()) { QuestWidgetView(entry: $0) }
            .configurationDisplayName("Quest").description("Your level strip.").supportedFamilies([.systemMedium])
    }
}
struct RepsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.reps", intent: PickHabit.self, provider: PickProvider()) { NumberWidgetView(entry: $0) }
            .configurationDisplayName("Reps").description("Total reps on a habit.").supportedFamilies([.systemSmall])
    }
}
struct ShowedUpWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "ritual.showedup", intent: PickHabit.self, provider: PickProvider()) { NumberWidgetView(entry: $0, showedUp: true) }
            .configurationDisplayName("Showed up").description("Kind consistency. No streaks.").supportedFamilies([.systemSmall])
    }
}

#if !WIDGET_PREVIEW
@main
#endif
struct RitualWidgets: WidgetBundle {
    var body: some Widget {
        OrbWidget()
        WeekWidget()
        MonthWidget()
        TrioWidget()
        TodayWidget()
        GridWidget()
        GridAllWidget()
        ClimbWidget()
        QuestWidget()
        RepsWidget()
        ShowedUpWidget()
    }
}

enum PreviewData {
    /// Placeholder shown in the widget gallery before the app has saved anything.
    static func make() -> AppData {
        var d = AppData()
        var h = Habit(name: "Meditate", goal: "10 minutes")
        for back in 1...40 where back % 4 != 0 { h.log[Day.key(Day.add(-back, to: Day.start()))] = 1 }
        h.created = Day.add(-41, to: Day.start())
        d.habits = [h, Habit(name: "Read", goal: "10 pages"), Habit(name: "Stretch"), Habit(name: "Journal")]
        return d
    }
}
