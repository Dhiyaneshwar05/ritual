import SwiftUI

enum Tab: String, CaseIterable {
    case today = "Today", journey = "Journey", stats = "Stats", all = "All habits", tasks = "Tasks"
    init(_ s: StartTab) {
        switch s { case .today: self = .today; case .journey: self = .journey; case .stats: self = .stats; case .all: self = .all; case .tasks: self = .tasks }
    }
}

struct MainWindow: View {
    @Environment(Store.self) private var store
    @State private var tab: Tab?
    @State private var editing: Habit?
    @State private var creating = false
    @State private var showSkins = false
    @Environment(\.openWindow) private var openWindow
    @State private var showShelf = false
    @State private var showGuide = false
    @State private var confirmDelete: Habit?
    @State private var paneOverride: Bool?

    var body: some View {
        let skin = store.skin
        GeometryReader { geo in
            let wide = geo.size.width > 1100
            let showPane: Bool = paneOverride ?? {
                switch store.settings.pane { case .always: return true; case .never: return false; case .auto: return wide }
            }()
            HStack(spacing: 0) {
                Sidebar(creating: $creating, editing: $editing, showShelf: $showShelf, confirmDelete: $confirmDelete, onTasks: tab == .tasks)
                    .frame(width: 236)
                Rectangle().fill(skin.line).frame(width: 1)
                ZStack {
                    SkinBackground()
                    content
                    overlays
                }
                if showPane && (store.selected != nil || tab == .tasks) {
                    Rectangle().fill(skin.line).frame(width: 1)
                    DayPane().frame(width: 252)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showPane)
            .onReceive(NotificationCenter.default.publisher(for: .ritualTogglePane)) { _ in paneOverride = !showPane }
        }
        .environment(\.skin, skin)
        .preferredColorScheme(skin.dark ? .dark : .light)
        .frame(minWidth: 820, minHeight: 640)
        .background(skin.bgBottom)
        .ignoresSafeArea()
        .sheet(item: $editing) { h in HabitEditor(habit: h, isNew: false).environment(\.skin, skin) }
        .sheet(isPresented: $creating) { HabitEditor(habit: newHabit(), isNew: true).environment(\.skin, skin) }
        .sheet(isPresented: $showSkins) { SkinsSheet().environment(\.skin, skin) }
        .sheet(isPresented: $showShelf) { ShelfView().environment(\.skin, skin) }
        .sheet(isPresented: $showGuide) { GuideView().environment(\.skin, skin) }
        .confirmationDialog("Delete \(confirmDelete?.name ?? "")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete habit and its history", role: .destructive) { if let h = confirmDelete { store.delete(h.id) }; confirmDelete = nil }
            Button("Archive instead") { if let h = confirmDelete { store.archive(h.id) }; confirmDelete = nil }
        } message: { Text("You can undo this right after.") }
        .animation(.easeInOut(duration: 0.25), value: store.masteryPrompt)
        .animation(.easeInOut(duration: 0.3), value: skin.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.toast)
        .onAppear {
            if tab == nil { tab = Tab(store.settings.startTab) }
            if !store.settings.seenGuide && !Storage.isDemo { showGuide = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ritualGuide)) { _ in showGuide = true }
        .onReceive(NotificationCenter.default.publisher(for: .ritualDismissSheets)) { _ in
            editing = nil; creating = false; showSkins = false; showShelf = false; showGuide = false
            NotificationCenter.default.post(name: .ritualCloseTaskEditor, object: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ritualShelf)) { _ in showShelf = true }
        .onReceive(NotificationCenter.default.publisher(for: .ritualNewHabit)) { _ in creating = true }
        .onReceive(NotificationCenter.default.publisher(for: .ritualShowTab)) { n in if let t = n.object as? Tab { tab = t } }
        .onReceive(NotificationCenter.default.publisher(for: .ritualSettings)) { _ in openWindow(id: "settings") }
        .onReceive(NotificationCenter.default.publisher(for: .ritualSkins)) { _ in showSkins = true }
        .onReceive(NotificationCenter.default.publisher(for: .ritualEdit)) { _ in
            if tab == .tasks { NotificationCenter.default.post(name: .ritualEditTask, object: nil) } else { editing = store.selected }
        }
    }

    private func newHabit() -> Habit {
        var h = Habit(name: "", groupID: store.selected?.groupID, reminders: [store.settings.defaultReminder])
        h.journeyLength = store.settings.defaultJourneyLength
        return h
    }

    @ViewBuilder private var content: some View {
        let current = tab ?? .today
        if current == .tasks {
            VStack(spacing: 0) {
                topBar(nil)
                TasksView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if current == .all {
            VStack(spacing: 0) {
                topBar(nil)
                OverviewView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let h = store.selected {
            VStack(spacing: 0) {
                topBar(h)
                Group {
                    switch current {
                    case .today: TodayView(habit: h) { tab = .journey }
                    case .journey: JourneyView(habit: h)
                    case .stats: StatsView(habit: h)
                    case .all, .tasks: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if current != .stats {
                    JourneyBar(habit: h).padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 6)
                }
            }
        } else {
            EmptyState { creating = true }
        }
    }

    @ViewBuilder private var overlays: some View {
        if let id = store.masteryPrompt, let h = store.habit(id) {
            MasterySheet(habit: h).transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
        VStack {
            Spacer()
            if let err = store.saveError {
                Text(err).font(.body(12)).padding(10).background(Capsule().fill(Color(hex: 0xB6423E))).foregroundStyle(.white)
            }
            if let t = store.toast {
                ToastView(toast: t).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 74)
    }

    private func topBar(_ h: Habit?) -> some View {
        let skin = store.skin
        return HStack {
            Button { if tab == .tasks { NotificationCenter.default.post(name: .ritualNewTask, object: nil) } else { creating = true } } label: { Image(systemName: "plus") }
                .buttonStyle(IconButtonStyle()).help(tab == .tasks ? "New task (⌥⌘N)" : "New habit (⌘N)")
            Spacer()
            HStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { t in
                    let on = (tab ?? .today) == t
                    Button { tab = t } label: {
                        MonoCaps(t.rawValue, size: 11, color: on ? skin.fg : skin.fgDim, weight: on ? .bold : .medium)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(on ? skin.fg.opacity(0.09) : .clear))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            if let h {
                Menu {
                    HabitMenuItems(habit: h, edit: { editing = h }, confirmDelete: $confirmDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(skin.fg)
                        .frame(width: 32, height: 32).contentShape(Circle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Habit menu: edit, move, archive, delete")
            }
            Button { showSkins = true } label: { Image(systemName: "paintpalette") }
                .buttonStyle(IconButtonStyle()).help("Skins (⇧⌘,)")
            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                .buttonStyle(IconButtonStyle()).help("Settings (⌘,)")
            Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(IconButtonStyle()).help("How Ritual works")
            Button { NotificationCenter.default.post(name: .ritualTogglePane, object: nil) } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(IconButtonStyle()).help("Day pane (⌥⌘0)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Binding var creating: Bool
    @Binding var editing: Habit?
    @Binding var showShelf: Bool
    @Binding var confirmDelete: Habit?
    var onTasks = false
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var hovered: UUID?
    @State private var confirmGroup: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 40) // traffic lights
            HStack(alignment: .firstTextBaseline) {
                Text("Ritual").font(.display(20)).foregroundStyle(skin.fg)
                Spacer()
                MonoCaps("\(store.todayDone)/\(store.visibleHabits.count) today", size: 10)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(store.sections) { s in section(s) }
                    SidebarTasks(active: onTasks).padding(.top, 4)
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Button { showShelf = true } label: {
                    Label(store.retiredHabits.isEmpty ? "Trophy shelf" : "Trophy shelf · \(store.retiredHabits.count)", systemImage: "trophy").font(.body(12, .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(skin.fg)
                Button { creating = true } label: { Label("New habit", systemImage: "plus").font(.body(12, .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(skin.fg)
                Text("Ring = tick · Name = open").font(.body(11)).foregroundStyle(skin.fgDim)
                HStack(spacing: 6) { kbd("Space"); Text("hold to check / uncheck").font(.body(11)).foregroundStyle(skin.fgDim) }
            }
            .padding(16)
        }
        .background(skin.sidebar)
    }

    private func section(_ s: Store.Section) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let gid = s.groupID, renaming == gid {
                    TextField("Group", text: $renameText).textFieldStyle(.plain).font(.mono(10, .bold))
                        .onSubmit { store.renameGroup(gid, renameText); renaming = nil }
                        .onExitCommand { renaming = nil }
                } else if let gid = s.groupID, confirmGroup == gid {
                    Text("Delete group?").font(.body(11, .semibold)).foregroundStyle(skin.fg)
                    Spacer()
                    Button("Delete") { store.deleteGroup(gid); confirmGroup = nil }.buttonStyle(.plain)
                        .font(.body(11, .bold)).foregroundStyle(Color(hex: 0xEF6A5E))
                    Button("Keep") { confirmGroup = nil }.buttonStyle(.plain).font(.body(11)).foregroundStyle(skin.fgDim)
                } else {
                    MonoCaps(s.title, size: 10)
                }
                if confirmGroup != s.groupID || s.groupID == nil {
                    Spacer()
                    MonoCaps("\(s.habits.filter { $0.isDone(on: store.today) }.count)/\(s.habits.count)", size: 10)
                    if let gid = s.groupID {
                        Menu {
                            Button("Rename group") { renaming = gid; renameText = s.title }
                            Button("Move group up") { store.nudgeGroup(gid, by: -1) }
                            Button("Move group down") { store.nudgeGroup(gid, by: 1) }
                            Divider()
                            Button("Delete group (keeps its habits)", role: .destructive) { confirmGroup = gid }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold)).foregroundStyle(skin.fgDim)
                                .frame(width: 18, height: 16).contentShape(Rectangle())
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .help("Group menu")
                    }
                }
            }
            .padding(.horizontal, 8).padding(.bottom, 4)
            ForEach(s.habits) { h in row(h) }
        }
    }

    private func row(_ h: Habit) -> some View {
        let selected = store.selected?.id == h.id && !onTasks
        let done = h.isDone(on: store.today)
        let partial = h.progress(on: store.today)
        let hovering = hovered == h.id
        return HStack(spacing: 10) {
            Button { store.toggle(h.id) } label: {
                ZStack {
                    Circle().stroke(skin.fg.opacity(0.14), lineWidth: 3)
                    Circle().trim(from: 0, to: Double(h.journeyReps) / Double(h.journeyLength))
                        .stroke(skin.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                    if done {
                        Circle().fill(skin.accent).frame(width: 15, height: 15)
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(skin.onAccent)
                    } else if partial > 0 {
                        Circle().trim(from: 0, to: partial).stroke(skin.accent.opacity(0.7), lineWidth: 5).rotationEffect(.degrees(-90)).frame(width: 9, height: 9)
                    } else if hovering {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(skin.fg.opacity(0.45))
                    }
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(done ? "Untick \(h.name)" : h.goalKind == .count ? "Add one (\(h.progressText(on: store.today)))" : "Tick \(h.name)")

            Button {
                store.selectedID = h.id
                if onTasks { NotificationCenter.default.post(name: .ritualShowTab, object: Tab.today) }
            } label: {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.name).font(.body(13.5, .semibold)).foregroundStyle(skin.fg).lineLimit(1)
                        if h.dust(today: store.today, after: store.settings.dustDays) > 0 {
                            Text("dusty · \(h.daysAway(today: store.today))d away").font(.body(10.5)).foregroundStyle(skin.fgDim)
                        } else if h.goalKind != .once && !done && partial > 0 {
                            Text(h.progressText(on: store.today)).font(.body(10.5)).foregroundStyle(skin.fgDim)
                        }
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // rep count, swapped for the ⋯ menu on hover so long names keep their width
            ZStack(alignment: .trailing) {
                Text(h.state == .endless ? "\(h.reps)" : "\(h.journeyReps)/\(h.journeyLength)")
                    .font(.mono(10.5)).foregroundStyle(skin.fgDim).monospacedDigit()
                    .opacity(hovering ? 0 : 1)
                Menu {
                    HabitMenuItems(habit: h, edit: { editing = h }, confirmDelete: $confirmDelete)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .bold)).foregroundStyle(skin.fg)
                        .frame(width: 26, height: 22).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
                .help("Habit menu")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? skin.fg.opacity(0.09) : hovering ? skin.fg.opacity(0.04) : .clear))
        .onHover { hovered = $0 ? h.id : (hovered == h.id ? nil : hovered) }
        .contextMenu { HabitMenuItems(habit: h, edit: { editing = h }, confirmDelete: $confirmDelete) }
    }

    private func kbd(_ s: String) -> some View {
        Text(s).font(.mono(9.5)).foregroundStyle(skin.fgDim).padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(skin.line))
    }
}

struct EmptyState: View {
    @Environment(\.skin) private var skin
    var add: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            MiniOrb(skin: skin, done: false, size: 160)
            Text("Start with something small").font(.display(28)).foregroundStyle(skin.fg)
            Text("Pick one habit. Every check-in moves you forward, and missed days never take anything away.")
                .font(.body(14)).foregroundStyle(skin.fgDim).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("Add your first habit", action: add).buttonStyle(PillButtonStyle(filled: true))
        }
    }
}

struct MasterySheet: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    let habit: Habit

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.55)).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "diamond.fill").font(.system(size: 54)).foregroundStyle(skin.pieceA)
                    .shadow(color: skin.pieceA.opacity(0.7), radius: 24)
                MonoCaps("\(habit.journeyLength) reps · Habit mastered", color: skin.accent)
                Text(habit.name).font(.display(40)).foregroundStyle(skin.fg)
                Text("You placed the gem. This habit is part of who you are now. What would you like to do next?")
                    .font(.body(14)).foregroundStyle(skin.fgDim).multilineTextAlignment(.center).frame(maxWidth: 380)
                VStack(spacing: 10) {
                    choice("Keep going", "Stay in today's list and keep counting reps.", "infinity", .keepGoing, filled: true)
                    choice("Start a new journey", "Begin another \(habit.journeyLength) reps tomorrow. Your history stays.", "arrow.clockwise", .newJourney)
                    choice("Retire to the trophy shelf", "Leave today's list. You can bring it back anytime.", "trophy", .retire)
                }
                .frame(width: 380)
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(LinearGradient(colors: [skin.bgTop, skin.bgBottom], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(skin.line))
            .shadow(color: .black.opacity(0.5), radius: 40, y: 20)
        }
    }

    private func choice(_ title: String, _ note: String, _ icon: String, _ c: Store.MasteryChoice, filled: Bool = false) -> some View {
        Button { withAnimation { store.resolveMastery(habit.id, c) } } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body(14, .bold))
                    Text(note).font(.body(12)).opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(filled ? skin.onAccent : skin.fg)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(filled ? skin.accent : skin.fg.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}


/// Skins keep their own sheet behind the palette button.
struct SkinsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.skin) private var skin
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Skins").font(.display(24)).foregroundStyle(skin.fg)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PillButtonStyle(filled: true)).keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 12) {
                ForEach(Skin.all) { s in
                    Button { store.updateSettings { $0.skin = s.id } } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack {
                                LinearGradient(colors: [s.bgTop, s.bgBottom], startPoint: .top, endPoint: .bottom)
                                MiniOrb(skin: s, done: true, size: 58)
                            }
                            .frame(height: 96)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.body(13, .bold)).foregroundStyle(skin.fg)
                                Text(s.tagline).font(.body(10.5)).foregroundStyle(skin.fgDim).lineLimit(2)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 118)
                        .background(skin.fg.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(store.settings.skin == s.id ? skin.fg : skin.line, lineWidth: store.settings.skin == s.id ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(width: 680)
        .background(SkinBackground())
    }
}

extension Notification.Name {
    static let ritualNewHabit = Notification.Name("ritual.newHabit")
    static let ritualShowTab = Notification.Name("ritual.showTab")
    static let ritualSettings = Notification.Name("ritual.settings")
    static let ritualSkins = Notification.Name("ritual.skins")
    static let ritualEdit = Notification.Name("ritual.edit")
    static let ritualTogglePane = Notification.Name("ritual.togglePane")
    static let ritualGuide = Notification.Name("ritual.guide")
    static let ritualShelf = Notification.Name("ritual.shelf")
    static let ritualDismissSheets = Notification.Name("ritual.dismissSheets")
}
