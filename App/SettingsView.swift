import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

/// ⌘, — everything except skins, which stay behind the palette button.
struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    @State var page: Page = Storage.isDemo ? (UserDefaults.standard.string(forKey: "ritual.debug.settingsPage").flatMap(Page.init(rawValue:)) ?? .general) : .general
    /// In its own window there's no Done button; the window's close button does it.
    var inWindow = true

    enum Page: String, CaseIterable, Identifiable {
        case general = "General", checkIn = "Check-in", journey = "Journey", reminders = "Reminders"
        case manage = "Groups & habits", tasks = "Tasks & labels", menuBar = "Menu bar & widgets", data = "Data"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .checkIn: return "circle.circle"
            case .journey: return "triangle"
            case .reminders: return "bell"
            case .manage: return "list.bullet.indent"
            case .tasks: return "checklist"
            case .menuBar: return "menubar.rectangle"
            case .data: return "externaldrive"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(.display(20)).foregroundStyle(skin.fg).padding(.horizontal, 10).padding(.bottom, 12)
                ForEach(Page.allCases) { p in
                    Button { page = p } label: {
                        HStack(spacing: 10) {
                            Image(systemName: p.icon).frame(width: 18)
                            Text(p.rawValue).font(.body(13, .semibold))
                            Spacer()
                        }
                        .foregroundStyle(page == p ? skin.fg : skin.fgDim)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(page == p ? skin.fg.opacity(0.09) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if !inWindow {
                    Button("Done") { dismiss() }.buttonStyle(PillButtonStyle(filled: true)).keyboardShortcut(.defaultAction).padding(10)
                }
            }
            .padding(.top, inWindow ? 34 : 18).padding(.bottom, 18).padding(.horizontal, 8)
            .frame(width: 210)
            .background(skin.sidebar)
            Rectangle().fill(skin.line).frame(width: 1)
            // An AppKit scroll view with a clear background. SwiftUI's ScrollView/List painted this pane white
            // inside the hidden-title-bar window.
            ClearScroll {
                SettingsContent(page: page)
                    .padding(24)
                    .padding(.top, inWindow ? 14 : 0)
                    .frame(width: 600, alignment: .leading)
                    .environment(store)
                    .environment(\.skin, skin)
            }
            .id(page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SkinBackground())
        }
        .frame(minWidth: 820, minHeight: 560)
        .background(SkinBackground())
        .preferredColorScheme(skin.dark ? .dark : .light)
    }
}

/// One settings page, without its scroll container (so it can also be rendered offscreen).
struct SettingsContent: View {
    @Environment(\.skin) private var skin
    let page: SettingsView.Page
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.rawValue).font(.display(24)).foregroundStyle(skin.fg).padding(.bottom, 8)
            switch page {
            case .general: GeneralPage()
            case .checkIn: CheckInPage()
            case .journey: JourneyPage()
            case .reminders: RemindersPage()
            case .manage: ManagePage()
            case .tasks: TasksPage()
            case .menuBar: MenuBarPage()
            case .data: DataPage()
            }
        }
    }
}

/// NSScrollView hosting SwiftUI content, transparent so the skin shows through.
struct ClearScroll<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSScrollView()
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        let host = NSHostingView(rootView: AnyView(content))
        host.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(host)
        sv.documentView = doc
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            host.topAnchor.constraint(equalTo: doc.topAnchor),
            host.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: sv.contentView.widthAnchor),
            doc.topAnchor.constraint(equalTo: sv.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: sv.contentView.leadingAnchor),
        ])
        context.coordinator.host = host
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        context.coordinator.host?.rootView = AnyView(content)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var host: NSHostingView<AnyView>? }
    final class FlippedView: NSView { override var isFlipped: Bool { true } }
}

// MARK: - Building blocks

struct SettingRow<C: View>: View {
    @Environment(\.skin) private var skin
    let title: String
    var note = ""
    @ViewBuilder var control: C
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body(13.5, .semibold)).foregroundStyle(skin.fg)
                if !note.isEmpty { Text(note).font(.body(12)).foregroundStyle(skin.fgDim).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(skin.line).frame(height: 1) }
    }
}

struct Segmented<T: Hashable>: View {
    @Environment(\.skin) private var skin
    let options: [(String, T)]
    @Binding var value: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let on = options[i].1 == value
                Button { value = options[i].1 } label: {
                    Text(options[i].0).font(.body(12, .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(on ? skin.bgBottom : skin.fgDim)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? skin.fg : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 9).fill(skin.fg.opacity(0.07)))
    }
}

struct Stepper2: View {
    @Environment(\.skin) private var skin
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var body: some View {
        HStack(spacing: 8) {
            Button { value = max(range.lowerBound, (value - step).rounded(to: step)) } label: { Image(systemName: "minus").frame(width: 24, height: 24) }
                .buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 6).fill(skin.fg.opacity(0.08)))
            Text(format(value)).font(.mono(13, .bold)).foregroundStyle(skin.fg).frame(minWidth: 52)
            Button { value = min(range.upperBound, (value + step).rounded(to: step)) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }
                .buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 6).fill(skin.fg.opacity(0.08)))
        }
        .foregroundStyle(skin.fg)
    }
}

private extension Double {
    func rounded(to step: Double) -> Double { (self / step).rounded() * step }
}

/// A binding into one settings field that saves on every change.
@MainActor
func setting<T>(_ store: Store, _ kp: WritableKeyPath<AppSettings, T>) -> Binding<T> {
    Binding(get: { store.settings[keyPath: kp] }, set: { v in store.updateSettings { $0[keyPath: kp] = v } })
}

struct Switch: View {
    @Environment(\.skin) private var skin
    @Binding var on: Bool
    var body: some View { Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch).tint(skin.accent) }
}

// MARK: - Pages

private struct GeneralPage: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @State private var loginItem = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Week starts on", note: "Week row, month widget and weekly stats") {
                Segmented(options: [("System", 0), ("Sun", 1), ("Mon", 2)], value: setting(store, \.weekStart))
            }
            SettingRow(title: "Open at login", note: "Start Ritual quietly with your Mac") {
                Switch(on: $loginItem)
                    .onChange(of: loginItem) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }; loginError = nil }
                        catch { loginError = "Couldn't change the login item: \(error.localizedDescription)"; loginItem = !on }
                    }
            }
            if let loginError { Text(loginError).font(.body(12)).foregroundStyle(skin.accent).padding(.vertical, 6) }
            SettingRow(title: "Default tab", note: "What the window shows when it opens") {
                Segmented(options: [("Today", StartTab.today), ("Journey", .journey), ("Stats", .stats), ("All", .all), ("Tasks", .tasks)], value: setting(store, \.startTab))
            }
            SettingRow(title: "Day pane", note: "Right-hand summary of the whole day. Auto shows it on wide windows. ⌥⌘0 toggles it.") {
                Segmented(options: [("Auto", PaneMode.auto), ("Always", .always), ("Never", .never)], value: setting(store, \.pane))
            }
            SettingRow(title: "Time format", note: "Reminder times and labels") {
                Segmented(options: [("System", TimeFormat.system), ("12h", .h12), ("24h", .h24)], value: setting(store, \.timeFormat))
            }
        }
    }
}

private struct CheckInPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Hold to check", note: "How long you hold the orb or Space") {
                Stepper2(value: setting(store, \.holdSeconds), range: 0.3...2.0, step: 0.05) { String(format: "%.2fs", $0) }
            }
            SettingRow(title: "Hold again to uncheck", note: "Off means right-click or the Undo toast only") {
                Switch(on: setting(store, \.holdToUncheck))
            }
            SettingRow(title: "Sounds") { Switch(on: setting(store, \.sound)) }
            SettingRow(title: "Volume", note: "Ticks, chord and fanfare") {
                Slider(value: setting(store, \.volume), in: 0...1).frame(width: 180).disabled(!store.settings.sound)
            }
            SettingRow(title: "Trackpad haptics", note: "On Force Touch trackpads") { Switch(on: setting(store, \.haptics)) }
            SettingRow(title: "Celebration", note: "Shards and shockwave when you complete a day") {
                Segmented(options: [("Full", Celebration.full), ("Calm", .calm), ("Off", .off)], value: setting(store, \.celebration))
            }
        }
    }
}

private struct JourneyPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Default journey length", note: "New habits start with this. Each habit can change it.") {
                Segmented(options: [("30", 30), ("60", 60), ("90", 90)], value: setting(store, \.defaultJourneyLength))
            }
            SettingRow(title: "Dust after", note: "Days away before dust settles. 0 turns dust off.") {
                Stepper2(value: Binding(get: { Double(store.settings.dustDays) }, set: { v in store.updateSettings { $0.dustDays = Int(v) } }),
                         range: 0...30, step: 1) { $0 == 0 ? "Off" : "\(Int($0)) days" }
            }
            SettingRow(title: "Consistency window", note: "\"Showed up X of the last N days\"") {
                Segmented(options: [("14", 14), ("30", 30), ("60", 60)], value: setting(store, \.consistencyWindow))
            }
            SettingRow(title: "When a journey ends", note: "What happens when you place the gem") {
                Segmented(options: [("Ask", MasteryDefault.ask), ("Keep going", .keepGoing), ("Retire", .retire)], value: setting(store, \.mastery))
            }
            SettingRow(title: "Show projected pace", note: "Lighter segment and gem date on the journey bar") { Switch(on: setting(store, \.showPace)) }
        }
    }
}

private struct RemindersPage: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    private var use24h: Bool { store.settings.timeFormat == .h24 }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Default reminder", note: "Pre-filled for new habits") {
                TimePicker(time: setting(store, \.defaultReminder), use24h: use24h)
            }
            SettingRow(title: "Snooze length", note: "\"Remind me in…\" on the banner") {
                Segmented(options: [("10m", 10), ("30m", 30), ("1h", 60)], value: setting(store, \.snoozeMinutes))
            }
            SettingRow(title: "Evening catch-up", note: "One gentle nudge if anything is still open") {
                HStack(spacing: 12) {
                    TimePicker(time: setting(store, \.catchUpTime), use24h: use24h).opacity(store.settings.catchUpOn ? 1 : 0.4)
                    Switch(on: setting(store, \.catchUpOn))
                }
            }
            SettingRow(title: "Quiet hours", note: "No banners in this window") {
                HStack(spacing: 8) {
                    TimePicker(time: setting(store, \.quietStart), use24h: use24h)
                    Text("to").foregroundStyle(skin.fgDim)
                    TimePicker(time: setting(store, \.quietEnd), use24h: use24h)
                    Switch(on: setting(store, \.quietOn))
                }
                .opacity(store.settings.quietOn ? 1 : 0.7)
            }
            Text("Reminders already skip habits you've finished that day. If no banners appear at all, allow Ritual in System Settings → Notifications.")
                .font(.body(12)).foregroundStyle(skin.fgDim).padding(.top, 12)
        }
    }
}

private struct ManagePage: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var confirm: String?
    @State private var newGroup = ""
    @State private var newExample = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.groups) { g in
                groupRow(g)
                ForEach(store.habits(in: g.id).filter { $0.state != .retired }) { h in habitRow(h) }
            }
            let loose = store.habits(in: nil).filter { $0.state != .retired }
            if !loose.isEmpty {
                MonoCaps("No group", size: 10).padding(.top, 6)
                ForEach(loose) { h in habitRow(h) }
            }
            HStack(spacing: 8) {
                TextField("New group name", text: $newGroup)
                    .textFieldStyle(.plain).font(.body(13, .semibold)).foregroundStyle(skin.fg)
                    .padding(9).frame(width: 200)
                    .background(RoundedRectangle(cornerRadius: 9).fill(skin.fg.opacity(0.07)))
                    .onSubmit(addGroup)
                Button("+ Add group", action: addGroup).buttonStyle(PillButtonStyle())
                Button("+ New habit") { NotificationCenter.default.post(name: .ritualNewHabit, object: nil) }.buttonStyle(PillButtonStyle())
            }
            .padding(.top, 8)

            if !store.retiredHabits.isEmpty {
                MonoCaps("Trophy shelf", size: 10).padding(.top, 18)
                ForEach(store.retiredHabits) { h in
                    row {
                        Image(systemName: h.isMastered ? "diamond.fill" : "archivebox").foregroundStyle(skin.pieceA)
                        Text(h.name).foregroundStyle(skin.fg)
                        Spacer()
                        small("Bring back") { store.restore(h.id) }
                        deleteControl(key: "h\(h.id)", label: "Delete", prompt: "Delete \(h.name) and its history?") { store.delete(h.id) }
                    }
                }
            }

            MonoCaps("Example habits in the New habit sheet", size: 10).padding(.top, 18)
            FlowLayout(spacing: 6) {
                ForEach(store.settings.examples, id: \.self) { ex in
                    Button { store.updateSettings { $0.examples.removeAll { $0 == ex } } } label: {
                        HStack(spacing: 6) { Text(ex); Image(systemName: "xmark").font(.system(size: 8, weight: .heavy)) }
                    }
                    .buttonStyle(PillButtonStyle())
                    .help("Remove \(ex)")
                }
                TextField("Add example", text: $newExample)
                    .textFieldStyle(.plain).font(.body(13, .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(width: 140)
                    .background(Capsule().strokeBorder(skin.line))
                    .onSubmit {
                        let v = newExample.trimmingCharacters(in: .whitespaces)
                        if !v.isEmpty && !store.settings.examples.contains(v) { store.updateSettings { $0.examples.append(v) } }
                        newExample = ""
                    }
            }
        }
    }

    private func addGroup() {
        let n = newGroup.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        store.addGroup(n)
        newGroup = ""
    }

    private func groupRow(_ g: HabitGroup) -> some View {
        row {
            VStack(spacing: 0) {
                Button { store.nudgeGroup(g.id, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                Button { store.nudgeGroup(g.id, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
            .foregroundStyle(skin.fgDim)
            if renaming == g.id {
                TextField("Group", text: $renameText).textFieldStyle(.plain).font(.body(13.5, .bold))
                    .onSubmit { store.renameGroup(g.id, renameText); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                Text(g.name).font(.body(13.5, .bold)).foregroundStyle(skin.fg)
            }
            Spacer()
            small(renaming == g.id ? "Save" : "Rename") {
                if renaming == g.id { store.renameGroup(g.id, renameText); renaming = nil } else { renaming = g.id; renameText = g.name }
            }
            deleteControl(key: "g\(g.id)", label: "Delete group", prompt: "Delete \"\(g.name)\"? Its habits move to No group.") { store.deleteGroup(g.id) }
        }
    }

    private func habitRow(_ h: Habit) -> some View {
        row {
            VStack(spacing: 0) {
                Button { store.nudge(h.id, by: -1) } label: { Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                Button { store.nudge(h.id, by: 1) } label: { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
            .foregroundStyle(skin.fgDim)
            Text(h.name).foregroundStyle(skin.fg)
            Text("\(h.journeyReps)/\(h.journeyLength)").font(.mono(10.5)).foregroundStyle(skin.fgDim)
            Spacer()
            Menu("Move") {
                Button("No group") { store.move(h.id, to: nil) }
                ForEach(store.groups) { g in Button(g.name) { store.move(h.id, to: g.id) } }
            }
            .menuStyle(.button).fixedSize()
            small("Archive") { store.archive(h.id) }
            deleteControl(key: "h\(h.id)", label: "Delete", prompt: "Delete \(h.name) and its history?") { store.delete(h.id) }
        }
        .padding(.leading, 22)
    }

    @ViewBuilder private func deleteControl(key: String, label: String, prompt: String, action: @escaping () -> Void) -> some View {
        if confirm == key {
            Text(prompt).font(.body(12)).foregroundStyle(skin.fgDim).lineLimit(1)
            small("Delete", danger: true) { action(); confirm = nil }
            small("Keep") { confirm = nil }
        } else {
            small(label, danger: true) { confirm = key }
        }
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 10) { c() }
            .font(.body(13))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(skin.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(skin.line))
    }

    private func small(_ label: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.plain)
            .font(.body(11.5, .semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(danger ? Color(hex: 0xEF6A5E) : skin.fg)
            .background(RoundedRectangle(cornerRadius: 7).fill(skin.fg.opacity(0.07)))
    }
}

private struct TasksPage: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @State private var renaming: String?
    @State private var renameText = ""
    @State private var confirm: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let open = store.tasks.filter { !$0.isDone }.count
            SettingRow(title: "Tasks", note: "\(open) open · \(store.tasks.count - open) finished") {
                if !store.tasksDone.isEmpty {
                    Button("Clear finished") { store.clearDoneTasks() }.buttonStyle(PillButtonStyle())
                }
            }
            Text("Labels").font(.display(18)).foregroundStyle(skin.fg).padding(.top, 18).padding(.bottom, 4)
            Text("Pick a colour, rename, or remove a label from every task. New labels come from typing #name when you add a task.")
                .font(.body(12.5)).foregroundStyle(skin.fgDim).padding(.bottom, 10)
            if store.labels.isEmpty {
                Text("No labels yet.").font(.body(13)).foregroundStyle(skin.fgDim)
            }
            VStack(spacing: 6) {
                ForEach(store.labels, id: \.self) { l in labelRow(l) }
            }
        }
    }

    private func labelRow(_ l: String) -> some View {
        let current = store.labelColorIndex(l) % LabelPalette.names.count
        return HStack(spacing: 10) {
            if renaming == l {
                TextField("Label", text: $renameText).textFieldStyle(.plain).font(.body(13, .semibold)).foregroundStyle(skin.fg)
                    .frame(width: 140)
                    .onSubmit { store.renameLabel(l, to: renameText); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                LabelChip(name: l)
            }
            Text("\(store.tasks.filter { $0.labels.contains(l) }.count) tasks").font(.mono(10.5)).foregroundStyle(skin.fgDim)
            Spacer()
            HStack(spacing: 4) {
                ForEach(LabelPalette.names.indices, id: \.self) { i in
                    Button { store.setLabelColor(l, i) } label: {
                        Circle().fill(LabelPalette.color(i, dark: skin.dark)).frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(skin.fg, lineWidth: i == current ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain).help(LabelPalette.names[i])
                }
            }
            if confirm == l {
                Button("Remove") { store.deleteLabel(l); confirm = nil }.buttonStyle(.plain).font(.body(11.5, .bold)).foregroundStyle(Color(hex: 0xEF6A5E))
                Button("Keep") { confirm = nil }.buttonStyle(.plain).font(.body(11.5)).foregroundStyle(skin.fgDim)
            } else {
                Button("Rename") { renaming = l; renameText = l }.buttonStyle(.plain).font(.body(11.5, .semibold)).foregroundStyle(skin.fg)
                Button("Remove") { confirm = l }.buttonStyle(.plain).font(.body(11.5, .semibold)).foregroundStyle(Color(hex: 0xEF6A5E))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(skin.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(skin.line))
    }
}

private struct MenuBarPage: View {
    @Environment(Store.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Show in menu bar") { Switch(on: setting(store, \.menuBar)) }
            SettingRow(title: "Menu bar label", note: "What sits next to the icon") {
                Segmented(options: [("2/5", MenuBarLabel.count), ("Icon only", .icon), ("Next habit", .next)], value: setting(store, \.menuBarLabel))
            }
            SettingRow(title: "Tasks in menu bar", note: "Adds \"· 3 tasks\" to the label and today's tasks to the menu") { Switch(on: setting(store, \.menuBarTasks)) }
            SettingRow(title: "Widgets follow skin", note: "Off keeps widgets in Carbon") { Switch(on: setting(store, \.widgetsFollowSkin)) }
        }
    }
}

private struct DataPage: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow(title: "Export", note: "Everything as JSON, or one row per day as CSV") {
                HStack(spacing: 8) {
                    Button("JSON") { save(type: .json, name: "ritual-export.json") { try store.exportJSON(to: $0) } }.buttonStyle(PillButtonStyle())
                    Button("CSV") { save(type: .commaSeparatedText, name: "ritual-export.csv") { try store.exportCSV(to: $0) } }.buttonStyle(PillButtonStyle())
                }
            }
            SettingRow(title: "Import", note: "Replace everything with a Ritual JSON export. You can undo right after.") {
                Button("Choose file…") { importFile() }.buttonStyle(PillButtonStyle())
            }
            SettingRow(title: "Automatic backups", note: "One copy a day, the last 14 kept in Backups") { Switch(on: setting(store, \.backups)) }
            SettingRow(title: "Data file", note: Storage.file.path) {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Storage.file]) }.buttonStyle(PillButtonStyle())
            }
            SettingRow(title: "Reset", note: confirmReset ? "What should go? Settings stay either way, and you can undo right after." : "Delete habits, tasks, or both. Settings stay.") {
                if confirmReset {
                    HStack(spacing: 8) {
                        Button("Keep everything") { confirmReset = false }.buttonStyle(PillButtonStyle())
                        Button("Habits") { store.resetAll(habits: true, tasks: false); confirmReset = false }.buttonStyle(PillButtonStyle(destructive: true))
                        Button("Tasks") { store.resetAll(habits: false, tasks: true); confirmReset = false }.buttonStyle(PillButtonStyle(destructive: true))
                        Button("Both") { store.resetAll(habits: true, tasks: true); confirmReset = false }.buttonStyle(PillButtonStyle(destructive: true))
                    }
                } else {
                    Button("Reset…") { confirmReset = true }.buttonStyle(PillButtonStyle(destructive: true))
                }
            }
            if let message { Text(message).font(.body(12)).foregroundStyle(skin.accent).padding(.top, 10) }
        }
    }

    private func save(type: UTType, name: String, _ write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try write(url); message = "Saved \(url.lastPathComponent)" } catch { message = "Couldn't save: \(error.localizedDescription)" }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.importJSON(from: url); message = "Imported \(url.lastPathComponent)" }
        catch { message = "That file isn't a Ritual export (\(error.localizedDescription))." }
    }
}
