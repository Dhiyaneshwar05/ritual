# Contributing to Ritual

Thanks for wanting to help. Ritual is a small, design-first project, so a short note before a big change saves everyone time.

## Before you start

- **Bugs:** open an issue with your macOS version, what you did, what you expected, and what happened. A screenshot helps.
- **Ideas:** open an issue first. Ritual stays local-only (no accounts, no network, no AI), and it puts how things look and feel first. Ideas that fit those two rules are the easiest to say yes to.
- **Small fixes** (typos, obvious bugs): send a pull request straight away.

## Working on the code

```sh
./build.sh --demo   # build and run with sample data, so your own data is untouched
./test.sh           # logic checks; please keep them passing
```

- No Xcode project. `build.sh` compiles everything with `swiftc` from the Command Line Tools.
- `Shared/` is compiled into both the app and the widget extension, so keep it free of app-only code.
- Match the code around you: SwiftUI, small views, skin colours from `Skin` (never hard-coded), fonts through `Font.display` / `.body` / `.mono`.
- UI changes: include a before-and-after screenshot in the pull request. The snapshot tool in the README makes these for every tab and skin.
- Writing in the app: plain, short and kind. Name things the way a person would.

## Pull requests

- One topic per pull request, branched from `main`.
- Explain what changed and why in a few lines.
- By contributing, you agree that your work is released under the [MIT License](LICENSE).
