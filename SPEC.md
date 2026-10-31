# Ritual: design spec and decisions

Ritual is a habit builder for macOS. It's local-only, has no accounts and no AI, and puts design first.

## 1. Principles
- **Reps that add up.** Small daily steps. Progress counts *reps*, not consecutive days.
- **Missed days cost nothing.** Progress never resets; you pick up where you left off.
- **60 reps to finish a journey** (30 or 90 can be chosen), because a habit takes roughly two months to become automatic.
- **One thing per screen.** The orb is the hero.
- **Physical, toy-like materials:** glass, clay, metal and iridescence, rather than flat UI chrome.
- **Mono-caps micro-type** as the only "UI text" look.
- **Overdone feedback.** Checking a habit should feel like an event.
- **Kind copy.** No red and no "you broke your streak" for habits.
- **Everything stays on this Mac.** No ads, no tracking, no network.

---

## 2. Mac interactions

| Idea | On the Mac |
|---|---|
| Hold to check | **Click-and-hold** the orb (progress ring fills over 0.8s), **or hold Space**. Release early to cancel. |
| Haptics | `NSHapticFeedbackManager` on Force Touch trackpads (`.levelChange` at completion, `.alignment` ticks while holding). Limited on Mac, so **sound and visuals carry more of the weight**. |
| One focused screen | A **resizable window** (min 420×640, hidden title bar, full-bleed skin background) plus a **sidebar of habits** that appears when the window is wide (>760pt). |
| Widgets | **Desktop and Notification Center widgets** (WidgetKit, macOS 14+), **interactive**: check off directly from the widget via App Intents. |
| — (Mac-only) | **Menu bar extra:** today's habits as mini orbs. Click to check. Shows a rep counter in the menu bar. |
| — (Mac-only) | **Global hotkey** (e.g. ⌥⌘H) opens a quick-check popover. |
| — (Mac-only) | **Shortcuts / Spotlight** via App Intents ("Check Meditate"). |
| — (Mac-only, macOS 26) | **Control Center control:** toggle today's habit. |
| Pan the 3D trophy | Drag to orbit, scroll or pinch to zoom, two-finger rotate on the trackpad. |
| Notifications | `UserNotifications` with a **"Done" action button** right in the banner. |

---

## 3. Feature spec

### 3.1 Habit model
- Name, emoji/icon, **type**: `once` | `count(n per day)` | `amount(goal, unit)`.
- Schedule: every day, or chosen weekdays (unscheduled days don't count as "missed").
- Reminder time(s), optional.
- Journey: `reps` (0…60), `currentLevel` (1…8), `completedAt`.
- Archive or restart after completion ("Habit mastered 🎉, keep tracking or retire it").

### 3.2 Journey
- **60 reps → 8 levels**, uneven so the early levels go fast and feel rewarding: `[3, 5, 6, 7, 8, 9, 10, 12]` = 60.
- Each level is a **world** with a 3D diorama that **builds one piece per rep** (a block, tree, stair or crystal appears with a pop).
- Original level themes, one stage of habit formation each:
  1. *Spark* (excitement) 2. *Foothills* (first friction) 3. *Fog* (motivation dips) 4. *The Long Field* (boredom/plateau) 5. *Storm* (life gets in the way) 6. *Ridge* (identity shift) 7. *Ascent* (it's getting automatic) 8. *Peak* (mastery, gem ceremony).
- Each level shows a short supportive message on entry and exit.
- **Missed days:** never lose reps. After 3+ days away, the copy says "Welcome back — pick up right where you left off."

### 3.3 Screens
1. **Today** (main): skin background, `TODAY` label, habit name, the **Orb**, a level/rep caption (`LEVEL 3 · REP 12 / 60`), and the week row. Multi-habit: swipe or arrow keys between habits, page dots.
2. **Journey:** full-window 3D diorama of the current world plus a level strip (8 nodes) to revisit finished worlds.
3. **Stats:** Grid heatmap (year), Climb chart, recaps (week/month/year), totals.
4. **Achievements:** badge wall, with locked badges shown as silhouettes.
5. **Skins:** a carousel of live orb previews.
6. **Settings:** reminders, sounds, haptics, launch at login, menu bar, hotkey, data export/import (JSON).
7. **Onboarding:** 3 steps (pick habit → set reminder → first check tutorial).

### 3.4 Visualizations, in detail
| Viz | Spec |
|---|---|
| **Orb + check** | RealityKit sphere with a PBR/glass material per skin. The extruded check mesh sits inside, tilted 30°. Idle: slow float (±2pt, 4s) and a light sweep. **Hold:** the orb squashes 0.94, a radial progress ring traces the rim, ticking sound and trackpad haptic every 25%. **Complete:** check pops to 1.15, then particles burst (skin-colored facets), shockwave ring, bloom flash, chord sound, haptic, and the week-row chip fills in sequence. **Undo:** right-click → "Uncheck". |
| **Week row** | 7 circles of 22pt with mono-caps weekday labels below. A 2pt underline in the accent color sits under TODAY. Filled, partial (an arc for count habits) and empty states. |
| **Grid heatmap** | 53×7 rounded squares of 10pt with a 3pt gap. Opacity steps go from 0 to 4 for count/amount habits. Uses the skin's ink color, never red. Hover tooltip shows the date and value. Month labels in mono caps. |
| **Climb chart** | Side-view low-poly mountain silhouette. The path zig-zags up and a marker shows the rep position. 8 level flags with the summit gem. Faceted spectral gradient fills (teal/navy/green/ochre). |
| **Recap cards** | Big number (reps this week), a mini week row and one kind sentence. Yearly recap is a shareable image (export PNG). |
| **Level diorama** | Low-poly faceted scene built **procedurally in code**: one piece added per rep, so no artist pipeline is needed. Flat shading with spectral facet colors on matte black, plus white clay clouds. |

### 3.5 Widgets (WidgetKit, macOS)
| Widget | Sizes | Content | Interactive |
|---|---|---|---|
| **Orb** | small | The habit's orb (static render) + `REP 12/60` | ✓ Tap = check (AppIntent) |
| **Today list** | medium | Up to 4 habits with mini orbs and a status | ✓ check each |
| **Week** | medium | Week row for 1–3 habits | ✓ today chip |
| **Grid** | medium / large | Heatmap (last 16 or 26 weeks) | — opens app |
| **Climb** | small / medium | Mountain + position marker + level name | — |
| **Streak-free counter** | small | "47 reps" big number + level | — |

Rules: widgets are **configurable** (pick a habit via `AppIntentConfiguration`). They follow the app's skin, or the system's tinted/glass rendering mode on macOS 26. A timeline reload runs at midnight and after each check. SwiftUI can't render 3D in widgets, so the orb is a **pre-rendered snapshot** that the app writes to the App Group container whenever the skin or state changes.

### 3.6 Sound & haptics
- 4 sounds: hold-tick, complete-chord, level-up fanfare, undo. Short, synthesized (we generate them, so no licensing issues).
- Toggle in settings. Respects Reduce Motion (particles off, crossfade only).

---

## 4. Technical architecture

| Layer | Choice | Why |
|---|---|---|
| Language/UI | **Swift 6 + SwiftUI**, macOS **15+** target (you're on 26.6) | Native, widget-compatible |
| 3D | **RealityKit** (`RealityView`) with procedural meshes (`MeshResource`) and custom materials. SceneKit was soft-deprecated in 2025. | Modern, Metal-backed, future-proof |
| Effects | SwiftUI `Canvas` + Metal shaders (`.layerEffect`) for iridescent rims, gradients, bloom and the 2D charts | Cheap, crisp |
| Data | **SwiftData** in an **App Group** container (shared with the widget extension) | Widgets read the same store |
| Intents | **App Intents**: `CheckHabitIntent`, `HabitEntity`. Shared by widgets, Shortcuts, Spotlight and Control Center | One code path |
| Notifications | `UserNotifications` + "Done" action | |
| Menu bar | `MenuBarExtra(.window)` | |
| Login item | `SMAppService.mainApp` | |
| Project gen | **XcodeGen** (`project.yml`), so the project file stays readable and diffable | |
| Distribution | Local: run from Xcode or archive a signed `.app`. Notarize later if you share it. | |

```
Ritual/
  project.yml
  Shared/            # model, journey logic, skins, intents, snapshot renderer (app + widget)
    Model/  Journey/  Skins/  Intents/
  App/
    Views/Today  Views/Journey  Views/Stats  Views/Achievements  Views/Skins  Views/Settings
    Scene3D/         # Orb entity, check mesh, particle FX, diorama builders
    Audio/  MenuBar/
  Widgets/           # WidgetKit extension
  Tests/             # journey math, date/schedule logic, intent tests
```

### Build without Xcode (decided 2026-10-24, verified with a spike)
- Compile with `swiftc` against `MacOSX26.5.sdk`. The default 27.0 SDK doesn't match the Swift 6.3.3 compiler, and `swift build` is broken in this CLT install, so don't use SwiftPM.
- A `build.sh` assembles `Ritual.app` + `PlugIns/RitualWidgets.appex` by hand: Info.plists, ad-hoc `codesign -s -` with entitlements, then copies the app to `~/Applications`.
- **Verified:** macOS registers the ad-hoc-signed widget extension (`pluginkit` lists it).
- **Data sharing:** no App Groups without a team ID. The app and the widget share one JSON store in `~/Library/Application Support/Ritual/` instead. The widget (sandboxed) reaches it through a `temporary-exception.files.home-relative-path` entitlement, and the app runs unsandboxed. Use a JSON store (`Codable`), not SwiftData. It's simpler and has no macro/plugin dependency.
- **Risk:** CLT has no `appintentsmetadataprocessor`. `Button(intent:)` in widgets may not fire without that metadata. **Fallback:** a widget tap deep-links via `widgetURL(ritual://check/<id>)`, and the app checks the habit and reloads timelines. We test this in M4.
- **Orb 3D:** SceneKit `SCNView` with procedural geometry (sphere + extruded check via `SCNShape`), PBR/glass materials and bloom. It's fast to build and still gives real 3D looks. Widgets get a pre-rendered PNG snapshot.

### Decisions (2026-10-24)
- No Xcode. Local only. No AI. Multiple habits from day one, with **groups** (Morning / Body / Evening…, shown as sidebar sections).
- Top priority is visual quality: skins, orb, particles, charts. Design board: `design/ritual-mockup.html`.
- Starter skins : **Carbon, Marigold, Paper, Aurora, Coral**. **Carbon is the default and Paper is second**: polish these two first.
- Level names and copy are approved. The hold-to-check feel was tested and approved.
- After 60 reps the app **asks**: keep going (endless), start a new journey (begins tomorrow), or retire it to the trophy shelf.
- Consistency is **B+C**: a neutral "showed up X of the last N scheduled days" line, plus dust on the orb and monument after 7+ days away. One check clears the dust, and no reps are ever lost.
- Reminders: per-habit times × scheduled weekdays, with a Done action in the banner. They're skipped if the habit is already done.
- v0.1 built 2026-10-24: see README.md. Widgets use the URL fallback (`ritual://check/<id>`). Interactive `Button(intent:)` isn't attempted yet.

---

### Feedback round 1 (approved 2026-10-25, built as v0.2)

- Fixes: a time picker you can type into, a ⋯ habit menu, click-to-toggle everywhere with Undo, hold the orb to uncheck, delete or rename groups and habits, sidebar ring ticks, sculpted monuments per level.
- New: the YouTube-style journey bar with level chapters and projected pace, the day pane, the All habits tab, a full Settings page (General, Check-in, Journey, Reminders, Groups & habits, Menu bar & widgets, Data), goal kinds (once, several times, amount), journey length 30/60/90/custom, per-time reminder days, snooze, quiet hours, an evening catch-up, export/import and daily backups.
- Widgets: chronod drops ad-hoc-signed extensions. `build.sh` uses an Apple Development certificate when one exists and generates App Intents metadata with Xcode's processor for the habit picker.

### Feedback round 2 (2026-10-26, built as v0.3)
- Fonts are bundled (OFL): Bricolage Grotesque (display), Hanken Grotesk (body), JetBrains Mono (labels). They register at launch, and the widgets register them too.
- New skin "Ember", the design-board desk: violet ink with an ember glow at the top left and a violet glow at the bottom right. Skins now support glows.
- Settings is its own window (⌘, or the gear button), reachable even while a sheet is open. Its content sits in a transparent NSScrollView; SwiftUI ScrollView and List painted that pane white in a hidden-title-bar window.
- AM/PM buttons are fixed. The day pane shows "Coming up": the next 3 reminders across all habits, with quiet hours and days respected.
- Stats: the two charts sit at equal height, with 6 uniform cards below. All habits: uniform tiles and balanced columns.
- The editor is two columns at 940×660. The trophy shelf is lit wooden shelves with 2D cups (mastered) or stone markers (archived) and brass plaques.
- New "How Ritual works" guide: 10 cards with live mini-illustrations. It opens on first launch, and later from ? or ⌘/.


### Tasks (2026-10-31, built as v0.4)
- A fifth **Tasks** tab holds a plain to-do list: Today, Inbox (no day), Upcoming and Done. It has labels, an optional reminder, and an optional priority shown as a coloured checkbox plus `!!!`/`!!`/`!`.
- Done tasks stay crossed out until midnight. Open tasks from earlier days show under "From earlier".
- The day pane and the menu bar show habits and tasks together. Reset asks whether to clear habits, tasks or both.
