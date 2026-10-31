import Foundation
import UserNotifications

/// Local reminders. One repeating notification per habit × reminder time × weekday, and one dated
/// notification per task, with "Done" and "Remind me later" actions on the banner.
final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()
    static let category = "ritual.reminder"
    static let doneAction = "ritual.done"
    static let snoozeAction = "ritual.snooze"
    static let taskCategory = "ritual.task"
    static let tomorrowAction = "ritual.tomorrow"

    /// Set by the app; called on the main actor when someone taps "Done" or the banner.
    @MainActor var onDone: ((UUID) -> Void)?
    @MainActor var onOpen: ((UUID) -> Void)?
    @MainActor var onTaskDone: ((UUID) -> Void)?
    @MainActor var onTaskTomorrow: ((UUID) -> Void)?
    @MainActor var onTaskOpen: ((UUID) -> Void)?
    private(set) var authorized = false
    private var snoozeMinutes = 30

    private var center: UNUserNotificationCenter { .current() }

    func setUp() {
        if Storage.isDemo { return }
        center.delegate = self
        registerCategories()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, error in
            self.authorized = ok
            if let error { NSLog("Ritual: notification permission error: \(error)") }
        }
    }

    private func registerCategories() {
        let done = UNNotificationAction(identifier: Self.doneAction, title: "Done ✓", options: [])
        let later = UNNotificationAction(identifier: Self.snoozeAction, title: "Remind me in \(Self.label(snoozeMinutes))", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [done, later], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.taskCategory, actions: [
                done,
                UNNotificationAction(identifier: Self.snoozeAction, title: "In \(Self.label(snoozeMinutes))", options: []),
                UNNotificationAction(identifier: Self.tomorrowAction, title: "Tomorrow", options: []),
            ], intentIdentifiers: [], options: []),
        ])
    }

    private static func label(_ m: Int) -> String { m >= 60 ? "\(m / 60)h" : "\(m) min" }

    private var rebuildTask: Task<Void, Never>?
    private var generation = 0
    private var clearedOnLaunch = false

    /// Rebuilds every reminder from the current habits. Rebuilds run one after another, and a
    /// rebuild that's been superseded is skipped, so an older one can't land last and bring back
    /// reminders for habits that were deleted in between.
    @MainActor func reschedule(_ habits: [Habit], tasks: [TaskItem], settings: AppSettings) {
        // Demo runs share this app's notification center; they must never touch the real reminders.
        if Storage.isDemo { return }
        if settings.snoozeMinutes != snoozeMinutes { snoozeMinutes = settings.snoozeMinutes; registerCategories() }
        generation += 1
        let gen = generation, previous = rebuildTask
        rebuildTask = Task { @MainActor in
            await previous?.value
            guard gen == self.generation else { return }
            await self.rebuild(habits, tasks, settings)
        }
    }

    private func rebuild(_ habits: [Habit], _ tasks: [TaskItem], _ settings: AppSettings) async {
        let center = self.center
        let live = habits.filter { $0.state != .retired && $0.remindersOn }
        let openTasks = tasks.filter { !$0.isDone }
        let liveIDs = Set(live.map(\.id.uuidString) + openTasks.map(\.id.uuidString))

        // macOS ties each queued reminder to the exact build that scheduled it, and every rebuild of this
        // ad-hoc signed app counts as a new build. Asking for "our" reminders only returns this build's,
        // so reminders from older builds (or deleted habits) used to be invisible and kept firing.
        // removeAll is the one call that reaches all of them, so every rebuild starts from nothing.
        // A snooze for a habit that still exists is put back.
        let snooze = "ritual.snooze."
        let keep = await center.pendingNotificationRequests().filter {
            $0.identifier.hasPrefix(snooze) && liveIDs.contains(String($0.identifier.dropFirst(snooze.count)))
        }
        center.removeAllPendingNotificationRequests()
        for r in keep {
            guard let at = (r.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(), at > .now else { continue }
            try? await center.add(UNNotificationRequest(identifier: r.identifier, content: r.content,
                                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: at.timeIntervalSinceNow, repeats: false)))
        }

        // Banners already in Notification Center: on launch clear them all (old builds' ones can't be
        // picked out); after that only drop the ones whose habit is gone.
        if !clearedOnLaunch {
            clearedOnLaunch = true
            center.removeAllDeliveredNotifications()
        } else {
            let delivered = await center.deliveredNotifications()
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter { n in
                let info = n.request.content.userInfo
                if info["catchup"] != nil { return !settings.catchUpOn }
                guard let id = (info["habit"] ?? info["task"]) as? String else { return false }
                return !liveIDs.contains(id)
            }.map(\.request.identifier))
        }

        // Tasks first: one dated reminder each, soonest first (macOS keeps at most 64 queued per app).
        // A high-priority task still open gets one follow-up an hour later.
        let dated = openTasks.compactMap { t in t.remindAt.map { (t, $0) } }.filter { $0.1 > .now }.sorted { $0.1 < $1.1 }
        for (t, at) in dated.prefix(24) {
            guard let r = t.remind, !Self.isQuiet(r, settings) else { continue }
            try? await center.add(Self.taskRequest(id: "ritual.task.\(t.id.uuidString)", task: t, at: at, again: false))
            if t.priority == 1 {
                try? await center.add(Self.taskRequest(id: "ritual.task.\(t.id.uuidString).again", task: t, at: at.addingTimeInterval(3600), again: true))
            }
        }

        for h in live {
            for time in h.reminders {
                let days = time.weekdays.isEmpty ? h.weekdays : time.weekdays.intersection(h.weekdays)
                for weekday in days where !Self.isQuiet(time, settings) {
                    let id = "ritual.\(h.id.uuidString).\(weekday).\(time.id)"
                    try? await center.add(Self.request(id: id, habit: h, weekday: weekday, time: time))
                }
            }
        }
        if settings.catchUpOn && !Self.isQuiet(settings.catchUpTime, settings) {
            for weekday in 1...7 {
                let content = UNMutableNotificationContent()
                content.title = "Anything left today?"
                content.body = "A gentle check-in. Open Ritual to see what's still waiting."
                content.sound = .default
                content.userInfo = ["catchup": true]
                var when = DateComponents(); when.weekday = weekday; when.hour = settings.catchUpTime.hour; when.minute = settings.catchUpTime.minute
                try? await center.add(UNNotificationRequest(identifier: "ritual.catchup.\(weekday)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: true)))
            }
        }
        await writeLog(kept: keep.count)
    }

    /// What's queued after each rebuild, in Application Support/Ritual/reminders.log, so a stray reminder can be traced.
    private func writeLog(kept: Int) async {
        let now = await center.pendingNotificationRequests()
        let shown = await center.deliveredNotifications()
        let auth = await center.notificationSettings().authorizationStatus.rawValue
        var lines = ["Rebuilt \(Date()) · \(Bundle.main.bundlePath) · auth \(auth) · cleared everything, kept \(kept) snooze(s) · queued \(now.count) · in Notification Center \(shown.count)"]
        lines += now.map { "queued  \($0.identifier)  \($0.content.title) · \($0.content.body)" }.sorted()
        lines += shown.map { "shown   \($0.request.identifier)  \($0.request.content.title) · \($0.request.content.body)" }
        try? lines.joined(separator: "\n").write(to: Storage.folder.appendingPathComponent("reminders.log"), atomically: true, encoding: .utf8)
    }

    private static func taskRequest(id: String, task t: TaskItem, at: Date, again: Bool, after: TimeInterval? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = t.title
        var bits = [again ? "Still open" : "Due \(Day.between(.now, at) == 0 ? "today" : at.formatted(.dateTime.weekday(.wide)))"]
        bits += t.labels
        if t.priority > 0 { bits.append("\(TaskItem.priorityNames[t.priority].lowercased()) priority") }
        content.body = t.note.isEmpty ? bits.joined(separator: " · ") : bits.joined(separator: " · ") + "\n" + t.note
        content.sound = .default
        content.categoryIdentifier = taskCategory
        content.threadIdentifier = t.id.uuidString
        content.userInfo = ["task": t.id.uuidString]
        let trigger: UNNotificationTrigger
        if let after {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: at), repeats: false)
        }
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private static func request(id: String, habit h: Habit, weekday: Int?, time: ReminderTime, after: TimeInterval? = nil) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = h.name
        content.body = body(for: h)
        content.sound = .default
        content.categoryIdentifier = category
        content.threadIdentifier = h.id.uuidString
        content.userInfo = ["habit": h.id.uuidString]
        let trigger: UNNotificationTrigger
        if let after {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: after, repeats: false)
        } else {
            var when = DateComponents()
            when.weekday = weekday
            when.hour = time.hour
            when.minute = time.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        }
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func isQuiet(_ t: ReminderTime, _ s: AppSettings) -> Bool {
        guard s.quietOn else { return false }
        let m = t.hour * 60 + t.minute, a = s.quietStart.hour * 60 + s.quietStart.minute, b = s.quietEnd.hour * 60 + s.quietEnd.minute
        return a <= b ? (m >= a && m < b) : (m >= a || m < b)
    }

    private static func body(for h: Habit) -> String {
        if !h.reminderNote.isEmpty { return h.reminderNote }
        let goal = h.goalText.isEmpty ? "" : "\(h.goalText). "
        if h.state == .endless { return "\(goal)Rep \(h.reps + 1) is waiting." }
        return "\(goal)Rep \(h.reps + 1) of \(h.journeyLength) · \(Journey.names[h.level])"
    }

    /// Remove delivered banners for a habit once it's been checked.
    func clearDelivered(for id: UUID) {
        let center = self.center
        center.getDeliveredNotifications { delivered in
            let ids = delivered.filter { $0.request.content.threadIdentifier == id.uuidString }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // Skip a reminder when the habit is already done.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        if let raw = info["task"] as? String {
            let open = Storage.load(readOnly: true)?.tasks.first { $0.id.uuidString == raw }.map { !$0.isDone } ?? false
            completion(open ? [.banner, .sound, .list] : [])
            return
        }
        if info["catchup"] != nil {
            let anyLeft = Storage.load(readOnly: true).map { d in
                d.settings.catchUpOn && d.habits.contains { $0.state != .retired && $0.isScheduled(.now) && !$0.isDone(on: .now) }
            } ?? true
            completion(anyLeft ? [.banner, .sound, .list] : [])
            return
        }
        // Last line of defence: only show a reminder for a habit that still exists, still wants
        // reminders and isn't done yet.
        let show: Bool = {
            guard let raw = info["habit"] as? String, let id = UUID(uuidString: raw),
                  let data = Storage.load(readOnly: true),
                  let h = data.habits.first(where: { $0.id == id }) else { return false }
            return h.state != .retired && h.remindersOn && !h.isDone(on: .now)
        }()
        completion(show ? [.banner, .sound, .list] : [])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completion: @escaping () -> Void) {
        let action = response.actionIdentifier
        if let raw = response.notification.request.content.userInfo["task"] as? String, let id = UUID(uuidString: raw) {
            if action == Self.snoozeAction {
                if let t = Storage.load(readOnly: true)?.tasks.first(where: { $0.id == id }) {
                    center.add(Self.taskRequest(id: "ritual.snooze.\(raw)", task: t, at: .now, again: true, after: TimeInterval(snoozeMinutes * 60)))
                }
                completion()
                return
            }
            Task { @MainActor in
                switch action {
                case Self.doneAction: self.onTaskDone?(id)
                case Self.tomorrowAction: self.onTaskTomorrow?(id)
                default: self.onTaskOpen?(id)
                }
                completion()
            }
            return
        }
        guard let raw = response.notification.request.content.userInfo["habit"] as? String,
              let id = UUID(uuidString: raw) else { completion(); return }
        if action == Self.snoozeAction {
            if let h = Storage.load(readOnly: true)?.habits.first(where: { $0.id == id }) {
                center.add(Self.request(id: "ritual.snooze.\(id.uuidString)", habit: h, weekday: nil,
                                        time: ReminderTime(hour: 0, minute: 0), after: TimeInterval(snoozeMinutes * 60)))
            }
            completion()
            return
        }
        Task { @MainActor in
            if action == Self.doneAction { self.onDone?(id) } else { self.onOpen?(id) }
            completion()
        }
    }
}
