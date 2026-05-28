# Dock Tap

Dock Tap is a macOS 13+ menu bar app that maps one physical modifier preset plus `1` through `0` to the first ten Dock apps. The same preset plus backtick activates Finder.

## Build and Run

Use a stable Apple Development signing identity for Accessibility/TCC validation:

```sh
DOCK_TAP_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" scripts/run-app.sh
```

The packaged app is written to `build/DockTap.app` with bundle id `ai.resopod.docktap`. Ad-hoc signing is available only for launch smoke tests via `DOCK_TAP_ALLOW_UNSTABLE_ADHOC=1`; it is not stable for Accessibility validation.

## Accessibility

Dock Tap needs Accessibility access for the packaged, signed `DockTap.app`. Because the bundle id is `ai.resopod.docktap`, macOS treats it as a separate TCC entry from older development builds such as `dev.local.DockTap`.

If the menu shows Accessibility as missing, choose `Check Accessibility` to prompt again or `Open Accessibility Settings` and enable the signed app entry manually.

## Menu

The main menu shows current readiness, the selected trigger preset, and how many Dock shortcuts are assigned. The `Dock Shortcuts` submenu shows the Finder shortcut plus the full ten-slot Dock list.

Dock shortcuts update automatically on launch and each time the main menu opens. Use `Update Dock Shortcuts` as a manual fallback after changing Dock contents.

## Trigger Presets

The trigger modifier is fixed to one of five physical presets:

- Left Option (default)
- Left Command
- Left Control
- Right Option
- Right Command

Only the selected physical key may be down. The opposite side or another Option, Command, or Control key rejects the shortcut; any Shift key also rejects it. Caps Lock and Fn do not reject shortcuts.

## Window Snap

Window Snap is off by default. Choose `Enable Window Snap` from the menu to let the same trigger preset resize the focused window:

| Shortcut | Action |
| --- | --- |
| `<preset>+←` | Left Half |
| `<preset>+→` | Right Half |
| `<preset>+↑` | Top Half |
| `<preset>+↓` | Bottom Half |
| `<preset>+Return` | Maximize |
| `<preset>+Space` | Center at 75% width and 75% height |

The `Window Snap Bindings` submenu shows the exact bindings for the current trigger preset. Window Snap uses the focused window on its current display and does not cycle sizes or move windows between displays.

When enabled, Window Snap uses the existing Accessibility trust to write other apps' window position and size, broadening Dock Tap's trust surface beyond app activation.

When Window Snap is enabled, Dock Tap consumes those chords before the focused app or macOS global shortcut handlers see them. This affects editor and text-field shortcuts such as `Option+←` / `Option+→` word jumps or `Command+←` / `Command+→` line/document jumps when that same preset is selected. It also affects system shortcuts such as `Command+Space` for Spotlight if your trigger preset is Command, and `Control+Space` for input-source switching if your trigger preset is Control.

Use the menu toggle as the quick escape hatch, or choose a trigger preset that does not overlap the shortcuts you rely on. If you want cycling, thirds, sixths, layouts, drag snapping, or cross-display window movement, Rectangle is the better tool for that full window-management suite.

## Launch at Login

Dock Tap uses `SMAppService.mainApp`; there is no helper target. macOS registers the currently running packaged app path. For daily use, keep that path stable before enabling Launch at Login. To use `/Applications`, first copy the built app to `/Applications/DockTap.app`, launch `/Applications/DockTap.app`, then enable Launch at Login from that running copy. Do not enable Launch at Login from `build/DockTap.app` and move the app afterward.

The menu reads Launch at Login state from `SMAppService.mainApp.status`. If macOS reports approval required, approve Dock Tap in System Settings > General > Login Items. If register or unregister fails, the menu remains based on the actual service status rather than the requested action.

## Known Limits

Dock Tap reads Dock preferences on launch/menu open and does not mutate Dock contents. It does not cycle windows, remap slots, support Custom triggers, notarize releases, or install an updater.

## License

Dock Tap is released under the MIT License. See [LICENSE](LICENSE).
