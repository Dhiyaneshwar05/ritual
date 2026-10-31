import SwiftUI
import AppKit

@main
struct RitualApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var store: Store { delegate.store }

    init() { Fonts.register() }

    var body: some Scene {
        Window("Ritual", id: "main") {
            MainWindow()
                .environment(store)
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1040, height: 760)
        .commands {
            CommandGroup(replacing: .help) {
                Button("How Ritual works") { NotificationCenter.default.post(name: .ritualGuide, object: nil) }.keyboardShortcut("/", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Habit") { NotificationCenter.default.post(name: .ritualNewHabit, object: nil) }.keyboardShortcut("n")
                Button("New Task") {
                    NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NotificationCenter.default.post(name: .ritualNewTask, object: nil) }
                }.keyboardShortcut("n", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NotificationCenter.default.post(name: .ritualSettings, object: nil) }.keyboardShortcut(",")
                Button("Skins…") { NotificationCenter.default.post(name: .ritualSkins, object: nil) }.keyboardShortcut(",", modifiers: [.command, .shift])
            }
            CommandMenu("Habit") {
                Button("Next Habit") { store.select(offset: 1) }.keyboardShortcut(.downArrow, modifiers: .command)
                Button("Previous Habit") { store.select(offset: -1) }.keyboardShortcut(.upArrow, modifiers: .command)
                Divider()
                Button("Today") { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.today) }.keyboardShortcut("1")
                Button("Journey") { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.journey) }.keyboardShortcut("2")
                Button("Stats") { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.stats) }.keyboardShortcut("3")
                Button("All habits") { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.all) }.keyboardShortcut("4")
                Button("Tasks") { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks) }.keyboardShortcut("5")
                Button("Trophy shelf") { NotificationCenter.default.post(name: .ritualShelf, object: nil) }.keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("Tick / untick selected") { if let h = store.selected { store.toggle(h.id) } }.keyboardShortcut(.return, modifiers: .command)
                Button("Edit habit…") { NotificationCenter.default.post(name: .ritualEdit, object: nil) }.keyboardShortcut("e")
                Button("Toggle day pane") { NotificationCenter.default.post(name: .ritualTogglePane, object: nil) }.keyboardShortcut("0", modifiers: [.command, .option])
            }
        }

        Window("Ritual Settings", id: "settings") {
            SettingsView()
                .environment(store)
                .environment(\.skin, store.skin)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 860, height: 620)
        .restorationBehavior(.disabled)

        MenuBarExtra(isInserted: Binding(get: { store.settings.menuBar }, set: { on in
            guard on != store.settings.menuBar else { return }
            var s = store.settings; s.menuBar = on; store.setSettings(s)
        })) {
            MenuBarPanel().environment(store).environment(\.skin, store.skin)
        } label: {
            let done = store.todayDone, total = store.visibleHabits.count
            let icon = done >= total && total > 0 ? "checkmark.circle.fill" : "circle.dotted"
            let open = store.settings.menuBarTasks ? store.openTasksToday : 0
            let tasks = open > 0 ? " · \(open) task\(open == 1 ? "" : "s")" : ""
            switch store.settings.menuBarLabel {
            case .count: Label("\(done)/\(total)\(tasks)", systemImage: icon).labelStyle(.titleAndIcon)
            case .icon: Image(systemName: icon)
            case .next:
                let next = store.visibleHabits.first { !$0.isDone(on: store.today) && $0.isScheduled(store.today) }
                Label(next?.name ?? "All done", systemImage: icon).labelStyle(.titleAndIcon)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.setUp()
        attach(store)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in self.store.refreshDay() }
        }
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            Task { @MainActor in self.store.refreshDay() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.store.refreshDay() }
        }
    }

    private func attach(_ store: Store) {
        let apply = { [weak store] in
            guard let s = store?.settings else { return }
            Feedback.shared.soundOn = s.sound
            Feedback.shared.volume = s.volume
            Feedback.shared.hapticsOn = s.haptics
        }
        store.onChange = apply
        apply()
        Notifier.shared.reschedule(store.data.habits, tasks: store.data.tasks, settings: store.settings)
        DebugSnapshot.run(store: store, skins: ProcessInfo.processInfo.environment["RITUAL_SNAPSHOT_SKINS"].map { $0.split(separator: ",").map(String.init) } ?? ["carbon", "paper"], tabs: Tab.allCases)
        Notifier.shared.onDone = { [weak store] id in
            if store?.check(id) == true { Feedback.shared.play(.done) }
        }
        Notifier.shared.onOpen = { [weak store] id in
            store?.selectedID = id
            NSApp.activate(ignoringOtherApps: true)
        }
        Notifier.shared.onTaskDone = { [weak store] id in
            store?.completeTask(id); Feedback.shared.play(.done)
        }
        Notifier.shared.onTaskTomorrow = { [weak store] id in
            guard let store else { return }
            store.moveTask(id, to: Day.add(1, to: store.today))
        }
        Notifier.shared.onTaskOpen = { [weak store] id in
            guard let store, let t = store.task(id) else { return }
            store.taskView = t.day == nil ? .inbox : (t.date.map { $0 > store.today } ?? false) ? .upcoming : .today
            NotificationCenter.default.post(name: .ritualShowTab, object: Tab.tasks)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// ritual://check/<id> from a widget checks the habit; ritual://open/<id> selects it.
    func handle(_ url: URL) {
        guard url.scheme == "ritual" else { return }
        let id = UUID(uuidString: url.lastPathComponent)
        switch url.host {
        case "check", "toggle":
            // ?day=yyyy-MM-dd from week/month widgets; default today
            let day = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "day" }?.value.flatMap(Day.date)
            if let id { store.toggle(id, on: day); store.selectedID = id }
        case "open":
            if let id { store.selectedID = id }
        default: break
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(handle) }

    func applicationDidBecomeActive(_ notification: Notification) { store.refreshDay() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { for w in sender.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil) } }
        return true
    }
}

/// Quick check from the menu bar: click an orb to check, right-click to undo.
struct MenuBarPanel: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                MonoCaps("Today · \(store.todayDone) of \(store.visibleHabits.count)", size: 10)
                Spacer()
                Text(store.today.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.mono(10)).foregroundStyle(skin.fgDim)
            }
            .padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(store.visibleHabits) { h in
                let done = h.isDone(on: store.today)
                Button { store.toggle(h.id) } label: {
                    HStack(spacing: 10) {
                        MiniOrb(skin: skin, done: done, size: 26)
                        Text(h.name).font(.body(13, .semibold)).foregroundStyle(skin.fg)
                        Spacer()
                        Text(h.goalKind != .once && !done && h.value(on: store.today) > 0 ? h.progressText(on: store.today)
                             : h.state == .endless ? "\(h.reps)" : "\(h.journeyReps)/\(h.journeyLength)").font(.mono(10.5)).foregroundStyle(skin.fgDim)
                    }
                    .padding(6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(done ? "Click to untick" : "Click to tick")
            }
            let dueTasks = store.tasksEarlier + store.tasksToday.filter { !$0.isDone }
            if !dueTasks.isEmpty {
                Divider().padding(.vertical, 4)
                MonoCaps("Tasks · \(dueTasks.count) open", size: 10).padding(.horizontal, 8).padding(.vertical, 4)
                ForEach(dueTasks.prefix(6)) { t in
                    Button { store.toggleTask(t.id); Feedback.shared.play(.tick) } label: {
                        HStack(spacing: 10) {
                            TaskCheckbox(done: t.isDone, priority: t.priority, size: 18).frame(width: 26)
                            Text(t.title).font(.body(13, .semibold)).foregroundStyle(skin.fg).lineLimit(1)
                            Spacer()
                            if t.daysLate(today: store.today) > 0 { Text("late").font(.mono(10)).foregroundStyle(PriorityColor.color(1, dark: skin.dark)) }
                            else if let r = t.remind { Text(r.label(store.settings.timeFormat)).font(.mono(10)).foregroundStyle(skin.fgDim) }
                        }
                        .padding(6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Button("Open Ritual") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Settings") {
                    openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .ritualSettings, object: nil)
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain).font(.body(12, .medium)).foregroundStyle(skin.fgDim)
            .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 300)
        .background(LinearGradient(colors: [skin.bgTop, skin.bgBottom], startPoint: .top, endPoint: .bottom))
    }
}
