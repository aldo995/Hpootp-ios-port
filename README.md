# Phoenix GBA (iOS)

Native SwiftUI GBA player built on [mGBA](https://github.com/mgba-emu/mgba) (MPL-2.0). Everything is free.
The game is **not bundled**: import your own legally obtained `.gba` dump from inside the app (or via Files / Finder file sharing).
It lives in the app's Documents folder with saves (`.sav`) and save states (`.ss0`).

## Features
- **Touch:** multitouch D-pad (slide for 8-way), A/B cluster (slide between A and B, or touch the middle for both) or separate A and B, L, R, Start, Select.
  Pause menu → *Edit touch controls* to drag and resize each button (separate portrait/landscape layouts). Opacity, size, haptics, dead zone in Settings.
- **Controllers:** Xbox, PlayStation, MFi and Backbone-style pads. Every face/shoulder/trigger/menu/stick-click is remappable to any GBA key or hotkey.
  Touch controls can auto-hide when a pad is connected. Defaults: R2 fast-forward (hold), L2 rewind (hold), L3 quick load, R3 pause menu.
- **Keyboard:** every GBA key and hotkey remappable (defaults: arrows, X=A, Z=B, A/S=L/R, Return=Start, Right Shift=Select, Tab=fast-forward,
  Backspace=rewind, F5/F7=save/load, Esc=menu).
- **Display:** Metal renderer; filters: pixel-perfect, bilinear, sharp bilinear, LCD grid, scanlines; optional GBA LCD colour correction.
- **Rewind** (5–20 s), **cheats** (enter your own GameShark / Action Replay codes per game; none are bundled),
  **per-game control profiles** (pause menu), **save states**, **fast-forward** (2–8×).
- **iCloud save sync** (optional): `.sav` and `.ss0`, newest wins, replaced local copy kept as `.bak`. Needs the iCloud capability, i.e. a paid
  Apple Developer account: in Xcode add *iCloud → iCloud Documents* to the target with container `iCloud.<your bundle id>`. Without it the
  setting simply reports that iCloud isn't available, and everything else works (including free-account sideloading).

## Build (on a Mac)
1. `brew install cmake xcodegen`
2. `./scripts/build_mgba_ios.sh`     # clones mGBA, builds libmgba.a for arm64 iOS
3. `xcodegen && open PhoenixGBA.xcodeproj`
4. Set your signing team, run on device. (A free Apple ID works for 7-day sideloads.)

## Status
Written without access to Xcode, so it has NOT been compiled. Expect small fixes (mGBA header paths, the libmgba.a output location,
the mGBA cheat calls, Metal/GBAKey Swift names).

## Hardening notes
Buttons can't stick when a touch is cancelled; the game pauses in the background; audio restarts after interruptions; audio uses a small
ring buffer so the real-time thread never waits on emulation; save states are written atomically; ROM imports are validated and copied
atomically; stored settings are clamped on load; cheat codes are validated before reaching the core.

## Licensing notes
- mGBA is MPL-2.0: include its licence text and keep its source available if you distribute the app. Your own code is separate.
- Never bundle a ROM, and keep Harry Potter names/art out of the app name, icon and any listing.
