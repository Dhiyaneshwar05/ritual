# Ritual

A design-first habit builder and to-do list for macOS: 60 reps, 8 levels, no streaks, everything local. Built without Xcode.

```sh
./build.sh          # build, install to ~/Applications/Ritual.app, launch
./build.sh --demo   # launch with sample history (kept in demo.json, separate from your data)
./test.sh           # journey / dust / consistency logic checks
```

- **Data:** `~/Library/Application Support/Ritual/data.json` (plain JSON, safe to back up).
- **Widgets (11):** Orb, Week, Month, Orbs, Today, Grid, Grid · all, Climb, Quest, Reps, Showed up. Clicking toggles through `ritual://toggle/<id>[?day=yyyy-MM-dd]`. **macOS only shows widgets from certificate-signed apps.** Add a free Apple ID in Xcode → Settings → Accounts → Manage Certificates → + Apple Development, then rerun `./build.sh`; it picks the certificate up automatically (or set `RITUAL_SIGN_ID`).
- **Reminders:** set per habit in the habit editor. The banner has a **Done ✓** button. If no banner shows up, allow Ritual in System Settings → Notifications.
- **Keys:** hold Space to check (hold again to uncheck) · ⌘↩ tick/untick · ⌘↑/⌘↓ switch habit · ⌘1–4 tabs · ⌘E edit · ⌘N new habit · ⌘, settings · ⇧⌘, skins · ⌥⌘0 day pane · ⌘Z undo (while the toast shows).
- **Backups:** one copy a day in `Backups/`, the newest 14 kept. Export/import JSON or CSV from Settings → Data.
- **Dev:** `open --env RITUAL_SNAPSHOT=/tmp/snaps ~/Applications/Ritual.app --args --demo` writes PNGs of every tab, then quits. Launch through `open`; running the binary directly doesn't open the window.

Layout: `Shared/` (model, skins, charts, used by app + widgets) · `App/` · `Widgets/` · `tools/MakeIcon.swift` · `design/ritual-mockup.html`.

## Tasks (v0.4)

The **Tasks** tab (⌘5) is a plain to-do list next to the habits, with Today, Inbox (no day), Upcoming and Done lists.
Its reminders use the same notifications, quiet hours and snooze as habits.

- **Quick add:** ⌥⌘N or the + button on the Tasks tab. Type `Call the bank tomorrow 11:30am #bank !2`.
  It understands `#label`, `!1`/`!2`/`!3` (or `!!!`/`!!`/`!`), today / tomorrow / mon…sun / next week / no date,
  and times written with am/pm or a colon. The calendar, bell, tag and flag buttons set the same things with pickers.
- **Priority is optional.** High, medium and low colour the checkbox red, orange and blue, and show `!!!`/`!!`/`!`.
  Tasks sort by priority, then by time. A high-priority task that's still open gets one more reminder an hour later.
- **Day handling:** done tasks stay crossed out until midnight, then move to Done. Unfinished tasks show under "From earlier", with how many days late.
- **Editing:** double-click a task, use its ⋯ menu or right-click it, or drag it onto Today, Inbox or Upcoming in the sidebar.
- **Settings:** the Tasks & labels page sets label colours and renames or removes labels. Reset asks whether to clear habits, tasks or both.
  "Tasks in menu bar" adds the open count to the menu bar.

## License

MIT. See [LICENSE](LICENSE). The bundled fonts are under the SIL Open Font License (see `Resources/Fonts/OFL-*.txt`).
