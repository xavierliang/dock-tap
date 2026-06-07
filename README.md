# Dock Tap

Dock Tap is a macOS 13+ menu bar app that maps one physical modifier preset plus `1` through `0` to the first ten Dock apps. The same preset plus backtick activates Finder.

## Install

Download the latest notarized `DockTap-<version>-universal.dmg` from GitHub Releases, open it, and drag `DockTap.app` to `/Applications`. Keeping Dock Tap in `/Applications` is also the supported path for the privileged Closed-Lid helper.

On first launch, grant Dock Tap Accessibility access in System Settings. Dock Tap uses that permission to activate Dock apps and, when enabled, resize the focused window.

## Usage

Launch Dock Tap from `/Applications`. Choose `Shortcut Modifier` from the menu bar item, then hold that physical modifier and press `1` through `0` to activate the matching Dock app. Press the same modifier plus backtick to activate Finder.

Use the menu to enable or disable Dock Shortcuts and Window Snap, refresh Dock shortcuts, control Closed-Lid Keep Awake, and configure Launch at Login.

Use `Check for Updates…` to open the Sparkle updater. Dock Tap also lets Sparkle handle scheduled background update prompts when a signed update is available.

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

The main menu starts with current readiness, followed by `Shortcut Modifier`. `Enable Dock Shortcuts` toggles Dock app and Finder shortcuts. `Dock Shortcut Bindings` shows the Finder shortcut plus the full ten-slot Dock list.

Dock shortcuts update automatically on launch and each time the main menu opens. Use `Refresh Dock Shortcuts` as a manual fallback after changing Dock contents.

## Shortcut Modifier

The shortcut modifier is fixed to one of five physical presets:

- Left Option (default)
- Left Command
- Left Control
- Right Option
- Right Command

Only the selected physical key may be down. The opposite side or another Option, Command, or Control key rejects the shortcut; any Shift key also rejects it. Caps Lock and Fn do not reject shortcuts.

## Window Snap

Window Snap is off by default. Choose `Enable Window Snap` from the menu to let the same shortcut modifier resize the focused window:

| Shortcut | Action |
| --- | --- |
| `<preset>+←` | Left Half |
| `<preset>+→` | Right Half |
| `<preset>+↑` | Top Half |
| `<preset>+↓` | Bottom Half |
| `<preset>+Return` | Maximize |
| `<preset>+Space` | Center at 75% width and 75% height |

The `Window Snap Bindings` submenu shows the exact bindings for the current shortcut modifier. Window Snap uses the focused window on its current display and does not cycle sizes or move windows between displays.

When enabled, Window Snap uses the existing Accessibility trust to write other apps' window position and size, broadening Dock Tap's trust surface beyond app activation.

When Window Snap is enabled, Dock Tap consumes those chords before the focused app or macOS global shortcut handlers see them. This affects editor and text-field shortcuts such as `Option+←` / `Option+→` word jumps or `Command+←` / `Command+→` line/document jumps when that same preset is selected. It also affects system shortcuts such as `Command+Space` for Spotlight if your shortcut modifier is Command, and `Control+Space` for input-source switching if your shortcut modifier is Control.

Use the menu toggle as the quick escape hatch, or choose a shortcut modifier that does not overlap the shortcuts you rely on. If you want cycling, thirds, sixths, layouts, drag snapping, or cross-display window movement, Rectangle is the better tool for that full window-management suite.

## Closed-Lid Keep Awake

The `Closed-Lid Keep Awake` submenu can keep the Mac awake with the lid closed by using the privileged helper to run the fixed system power setting `pmset -a disablesleep 1`.

Menu commands:

- `Enable for 1 Hour` starts a timed session. The helper owns the one-hour expiry and restores normal lid sleep when it ends.
- `Enable Indefinitely` starts a session with no wall-clock expiry, but Dock Tap must keep renewing its helper lease. If Dock Tap quits, crashes, or stops renewing, the helper restores normal lid sleep.
- `Stop Now` restores normal lid sleep immediately by running `pmset -a disablesleep 0`.

The first enable shows a warning because this changes normal lid-sleep behavior and can increase battery drain and heat. Use it only on a ventilated surface. After you continue once, Dock Tap remembers the acknowledgement.

The helper is registered lazily on first use, not at app launch. macOS may require approval in System Settings > General > Login Items & Extensions; when approval is pending, the submenu shows `Helper approval required` and offers `Open Login Items Settings...`.

While a closed-lid session is active, both enable commands are disabled. To switch between timed and indefinite modes, choose `Stop Now` first. Dock Tap does not automatically re-enable a previous session on launch.

Dock Tap blocks normal quit and Sparkle update installation until the helper confirms `pmset -a disablesleep 0`. If that confirmation fails, Dock Tap stays open and shows the manual recovery command:

```sh
sudo pmset -a disablesleep 0
```

## Launch at Login

Dock Tap uses `SMAppService.mainApp` for Launch at Login. macOS registers the currently running packaged app path. For daily use, keep that path stable before enabling Launch at Login. To use `/Applications`, first copy the built app to `/Applications/DockTap.app`, launch `/Applications/DockTap.app`, then enable Launch at Login from that running copy. Do not enable Launch at Login from `build/DockTap.app` and move the app afterward.

The menu reads Launch at Login state from `SMAppService.mainApp.status`. If macOS reports approval required, approve Dock Tap in System Settings > General > Login Items. If register or unregister fails, the menu remains based on the actual service status rather than the requested action.

## Known Limits

Dock Tap requires macOS 13 or newer and ships as a Universal app for Apple silicon and Intel Macs. It reads Dock preferences on launch/menu open and treats Dock slots as read-only; it does not mutate Dock contents, remap slots, or support a custom shortcut modifier. Window Snap covers only the listed fixed actions and is not a Rectangle replacement. Closed-Lid Keep Awake intentionally does not monitor battery level or thermals. Sparkle updates download the full DMG because delta updates are not currently published.

## License

Dock Tap is released under the MIT License. See [LICENSE](LICENSE).
