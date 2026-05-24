<!-- 修订v1: 创建——dev-planner 应 Lead 指派，调研 Rectangle 集成可行性，结论与推荐落在 §Recommended scope -->
# Rectangle Integration Research

## Context

The user (via Lead) asked whether the macOS window manager they referred to as "Rectagle" should be integrated into Dock Tap. The spelling is almost certainly a typo for **Rectangle** ([rectangleapp.com](https://rectangleapp.com), [github.com/rxhanson/Rectangle](https://github.com/rxhanson/Rectangle)) — the well-known free, MIT-licensed Spectacle successor by Ryan Hanson. No other actively maintained macOS utility uses the "Rectagle" or close spelling. This plan proceeds on that assumption; if the user actually meant a different tool (e.g. an internal prototype, a fork like `Rectangle-Ultrawide`, or a commercial product like Rectangle Pro / Magnet / Moom), most of the analysis still holds because they share the same underlying mechanism, but the recommended scope would need to be re-pitched.

Dock Tap is currently a Swift Package macOS 13+ menu bar app whose only job is mapping `<physical modifier preset>+1…0/`` ` to *activating* the first ten Dock apps or Finder. It does not manipulate windows, does not read window geometry, and does not write to any other app's UI state. Adding Rectangle-style features would be a meaningful expansion of the product's surface and of the trust users must extend.

The Lead's research brief is: read-only investigation, no source changes, no implementation commands. Output is this plan plus the conclusion that follows from it.

## What Rectangle does

Rectangle is a keyboard-driven window manager. Its core verbs operate on the **frontmost focused window of any app** and move/resize it to a predefined screen region:

- **Halves** — left, right, top, bottom, center.
- **Thirds / two-thirds** — first, center, last, first-two, last-two.
- **Quarters** — top-left, top-right, bottom-left, bottom-right.
- **Sixths** — six-cell grid positions.
- **Sizing** — maximize, almost-maximize, maximize-height, larger/smaller, restore, center.
- **Display movement** — next display, previous display, traverse-on-repeat option.
- **Snap areas** — dragging a window to a screen edge triggers an automatic resize.
- **Cycling** — repeating the same shortcut cycles a window through related sizes (e.g. left-half → left-third → left-two-thirds).

Sources: [Rectangle README](https://github.com/rxhanson/Rectangle), [comparison page](https://rectangleapp.com/comparison).

Rectangle Pro ($9.99 one-time, closed source) adds cursor gestures, custom snap zones, application layouts, pinning, hide-behind-edge, and display-connect automation. Out of scope for this research — the relevant comparison for Dock Tap is the free, open-source Rectangle.

## How Rectangle likely implements it

Verified from the public repository:

- **Language / target:** 100% Swift, macOS 10.15+. ([Rectangle README](https://github.com/rxhanson/Rectangle))
- **License:** MIT, "Copyright (c) 2019-2025 Ryan Hanson … Based on the Spectacle app, Copyright (c) 2017 Eric Czarny". ([LICENSE](https://raw.githubusercontent.com/rxhanson/Rectangle/main/LICENSE))
- **Window manipulation:** `AccessibilityElement` is a thin Swift wrapper over the C-level Accessibility API (`AXUIElement`, `AXUIElementCreateApplication`, `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue` with `kAXPositionAttribute` and `kAXSizeAttribute`, packing/unpacking `CGPoint`/`CGSize` through `AXValueCreate`/`AXValueGetValue`). Key entry points exposed: `getFrontApplicationElement()`, `getFrontWindowElement()` (frontmost app → focused window), `getWindowElementUnderCursor()`, `setFrame(_:adjustSizeFirst:)` (size-then-position vs position-then-size dance for multi-display). ([AccessibilityElement.swift](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityElement.swift))
- **Global hotkeys:** [MASShortcut](https://github.com/shpakovski/MASShortcut) (Rectangle maintains a fork, since upstream is archived). MASShortcut registers Carbon-event-based hotkeys (`RegisterEventHotKey`), which **do not** require an Accessibility-trusted CGEvent tap; the only Accessibility trust required is for *writing* window position/size.
- **Permissions:** Accessibility trust (same TCC bucket Dock Tap already uses for its CGEvent tap). Rectangle's auth flow lives in [`AccessibilityAuthorization/AccessibilityAuthorization.swift`](https://github.com/rxhanson/Rectangle/blob/main/Rectangle/AccessibilityAuthorization/AccessibilityAuthorization.swift).
- **Updater:** Sparkle, integrated via Swift Package Manager.
- **Distribution:** Notarized DMG from [rectangleapp.com](https://rectangleapp.com) and from [GitHub Releases](https://github.com/rxhanson/Rectangle/releases); Homebrew Cask (`rectangle`); not on the Mac App Store (sandbox disallows the cross-app AX writes Rectangle needs).
- **Reset hint:** `tccutil reset All com.knollsoft.Rectangle` — the bundle id confirms the cross-app AX permission model.

Mechanism summary: Rectangle's window action = read frontmost app's focused window via AX, compute target `CGRect` from the screen Rectangle picks for that window, write `kAXPositionAttribute` then `kAXSizeAttribute` (order swapped on display boundary). Everything else (cycling, snap areas, layouts) is policy on top of that primitive.

## Dock Tap current architecture fit

Concrete touch points where Rectangle-style functionality would interact with what already exists:

- **Permission model:** Dock Tap already requires Accessibility trust for its `CGEvent` tap (`Sources/DockTap/PermissionGate.swift`, `EventTapController.swift`). Adding `AXUIElementSetAttributeValue` on the focused window would **not** require a new TCC entry — same trust unlocks both reads of keyboard events and writes to other apps' UI. The user's *trust grant*, however, is semantically broader once the app actually starts moving other windows.
- **Event pipeline:** `EventTapController` already sees every keyDown/keyUp/flagsChanged. `KeyEventDecider` + `RuleMatcher` (`Sources/DockTap/KeyEventDecider.swift`, `RuleMatcher.swift`) currently only handle digits + backtick under the active trigger preset and consume the event if matched. Adding window actions would mean extending `RuleMatcher`'s key set (likely arrow keys) and returning a new intent variant. This is a structurally clean extension — no rewiring needed — but arrow-key consumption is more risky than digit-key consumption (see §Risks).
- **Intent → side-effect split:** `ShortcutIntent` (`Sources/DockTap/ShortcutIntent.swift`) and `AppActivator` (`Sources/DockTap/AppActivator.swift`) cleanly separate "what the user asked for" from "how we execute it." A new `ShortcutIntent.windowAction(...)` variant fits the existing pattern; a sibling `WindowActor` (analogous to `AppActivator`) would own the AX writes.
- **Hotkey mechanism mismatch:** Rectangle uses MASShortcut (Carbon `RegisterEventHotKey`); Dock Tap uses a Quartz CGEvent tap on a dedicated run loop. Carbon hotkeys can't express the "single physical modifier only, no other modifiers, no shift" rule that Dock Tap was built around — so we would **not** want to vendor Rectangle's hotkey layer. We'd reuse Dock Tap's tap and extend `RuleMatcher`.
- **Single-trigger UX:** Dock Tap's product story is "one preset, one modifier, simple keys." Bolting on the Rectangle command vocabulary (halves/thirds/quarters/sixths/maximize/display-move/cycling) under the same single preset would balloon the key surface area beyond what one preset can carry without conflicts.
- **Login item, menu, settings:** `LoginItemController`, `MenuContentModel`, `SettingsStore`, `AppText` all already have the shape needed to expose an additional feature toggle and submenu without restructure.
- **Distribution gap:** Dock Tap is currently locally signed (`scripts/run-app.sh` + a stable Developer ID), not notarized, no updater (per README "Known Limits"). Rectangle ships notarized + Sparkle. Shipping window-manipulation features to outside testers under the current Dock Tap distribution story would be a bigger trust ask than the current "activate the app I clicked" story.

## Integration options

Four realistic shapes, smallest to largest:

### Option A — Do nothing; document the overlap
Stay app-activation-only. Add a one-line note in `README.md` ("Dock Tap activates apps; it does not move/resize windows — pair with [Rectangle](https://rectangleapp.com) or similar"). Zero code change, zero new trust surface, zero ongoing maintenance.

### Option B — Minimal "snap focused window" verbs, reusing the existing event tap
Add a small fixed vocabulary of window actions on a separate key family — e.g. `<preset>+←/→/↑/↓` for the four halves, plus `<preset>+Return` for maximize, `<preset>+\` for center. Six actions, no cycling, no thirds/quarters/sixths, no snap areas, no display moves, no layouts. Reuses Accessibility permission and the existing CGEvent tap; introduces a `WindowActor` analogous to `AppActivator`. This is the minimum that gives the user "I don't have to install Rectangle for the 80% case" without trying to replicate Rectangle.

### Option C — Full Rectangle parity
Vendor or reimplement the full halves/thirds/quarters/sixths/sizing/display/cycling/snap-areas vocabulary, settings UI, per-app overrides, and an updater. Effectively rebuilds Rectangle inside Dock Tap. Large scope, high ongoing maintenance, and Rectangle already exists and is free — almost certainly not worth it.

### Option D — Detect and interop
Detect whether Rectangle (or Magnet/Moom) is installed (look for the bundle id in `/Applications` or via `NSWorkspace.urlForApplication(withBundleIdentifier:)`); if present, surface a menu hint instead of duplicating; if absent, optionally enable Option B. Adds menu polish but does not by itself give the user any new window-manipulation capability.

These compose: A is the floor, D is an additive UX layer on top of A or B, C is the ceiling.

## File impact

For **Option A**: only `README.md` and this plan. No source changes.

For **Option B** (smallest functional integration), expected changes (descriptive, not prescriptive):
- `Sources/DockTap/ShortcutIntent.swift` — add a `windowAction(WindowAction, shortcutLabel:)` case; introduce a `WindowAction` enum (`leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `maximize`, `center` — keep the set small and named).
- `Sources/DockTap/KeyCodes.swift` — add arrow key codes (left=123, right=124, down=125, up=126), Return (36), and any other keys chosen. These are the only new physical-key constants needed.
- `Sources/DockTap/RuleMatcher.swift` — extend `matchKeyDown` so that when the trigger preset matches and the key is in the window-action key set, return a `.windowAction` intent. Keep the digit/backtick branches untouched; arrow-key matches should only fire when window actions are enabled in settings, so the matcher gains an `isWindowActionsEnabled` input.
- New `Sources/DockTap/WindowActor.swift` — owns the AX writes. Methods analogous to `AppActivator.perform`. Internally: get frontmost app via `NSWorkspace.shared.frontmostApplication`, build `AXUIElement` for the pid, copy `kAXFocusedWindowAttribute`, compute target `CGRect` from `NSScreen.main.visibleFrame` for the picked `WindowAction`, write `kAXSizeAttribute` and `kAXPositionAttribute` (size-first when crossing a display boundary, per Rectangle's pattern). Logs through `LogStore` like `AppActivator`.
- New `Sources/DockTap/AccessibilityElement.swift` (optional) — a thin Swift wrapper around `AXUIElement` for `position`, `size`, `frame`, `focusedWindow`, mirrored in shape from Rectangle's `AccessibilityElement.swift`. If we choose to mirror Rectangle's design, include a one-line MIT attribution comment naming Rectangle as the source of inspiration (vendoring vs. reimplementing is a Lead call — see Open questions).
- `Sources/DockTap/SettingsStore.swift` — add a `windowActionsEnabled` boolean key (default off in v1 so existing users see no behavior change on upgrade).
- `Sources/DockTap/AppDelegate.swift` — wire `WindowActor` into the `handleShortcut` switch; add a settings toggle menu item; pass `isWindowActionsEnabled` into the snapshot used by `KeyEventDecider`/`RuleMatcher` (parallels how `TriggerModifierPreset` is wired today).
- `Sources/DockTap/EventTapController.swift` — already passes a `slotSnapshot` + `triggerModifierPreset` into the decider. Either bundle `isWindowActionsEnabled` into a small new `InputSnapshot` struct or add it as a sibling field. Prefer the struct to keep `updateXxx` methods from sprawling.
- `Sources/DockTap/MenuContentModel.swift` and `Sources/DockTap/AppText.swift` — new submenu/text for the window actions section, mirroring the existing `Show Dock Mapping` + `Trigger Modifier` pattern.
- `Tests/DockTapTests/RuleMatcherWindowActionTests.swift` (new), updates to `RuleMatcherPresetTests.swift`, `SettingsStoreTests.swift`, `MenuContentModelTests.swift`, `AppTextTests.swift` — pure tests for the new matcher branch, the settings key, the menu rows, and the text helpers. `WindowActor` itself is intentionally not unit-tested under XCTest because it depends on a live AX hierarchy; treat it like `AppActivator`'s `execute` (manual verification only).
- `README.md` — document the new feature, the enable-it-yourself default, the arrow-key caveat (overlaps with macOS text navigation when an editor is focused — see §Risks), and an honest "Rectangle does this better if you want the full suite" link.
- `docs/plans/m4-window-snap.md` (new) — a separate implementation plan if Option B is adopted; this file would only carry the research + decision.

For **Option C**: roughly Option B × (number of additional verbs) plus snap-area drag detection (requires CGEvent mouse taps on top of the current keyboard tap), per-app overrides UI, conflict resolution with system shortcuts, and an updater. Not enumerated in detail because it is not recommended.

For **Option D**: small additions to `MenuContentModel.swift`, `AppText.swift`, `AppDelegate.swift`, and a tiny `RectangleDetector` helper (`NSWorkspace.urlForApplication(withBundleIdentifier: "com.knollsoft.Rectangle")` and friends).

## Permissions & distribution risks

- **Trust scope creep on the same TCC bucket.** Accessibility trust is binary in macOS: once granted, the app can both observe input events *and* write to other apps' UI. Dock Tap's current scope is "we see your keys but we only activate apps." Adding `AXUIElementSetAttributeValue` calls on other apps' windows is technically allowed by the same grant but semantically expands what users have consented to. Worth surfacing in README/menu copy if Option B ships.
- **App compatibility.** Many apps respond to AX position/size writes correctly. Some don't, in well-documented ways: Electron windows occasionally clamp to minimum sizes; some Java/AWT apps ignore writes; certain fullscreen-style apps refuse to be repositioned; MAS-sandboxed apps may not advertise their windows in AX. Rectangle has accumulated workarounds over years; a small reimplementation will not. Set expectations honestly.
- **Stage Manager / Spaces / Mission Control.** Writing window frames while Stage Manager is on, or while a window is on a non-active Space, has surprising results (window jumps to active Space; frame is clamped by Stage Manager's strip). Not blockers, but worth a manual smoke test in Verification.
- **Arrow-key consumption clash.** Dock Tap's tap consumes matched keys. Many users have `<modifier>+arrow` muscle memory (Option+arrow = word jump in text; Control+arrow = Mission Control; Command+arrow = line jump). If the chosen trigger preset is one of those, window-action shortcuts will silently steal text-navigation behavior. Mitigation: keep window actions off by default; document the trade-off; consider rejecting window-action matches when a known editor-class app is focused (adds complexity — probably not worth in v1).
- **Notarization gap.** Dock Tap is locally signed (per README). Once Dock Tap moves other apps' windows, users have more incentive to scrutinize trust. Recommend notarization land before, or together with, Option B if it ships to anyone beyond the author. (Notarization is independent of Rectangle integration but becomes more load-bearing once we add cross-app writes.)
- **License compatibility.** Rectangle is MIT. Dock Tap can legally vendor `AccessibilityElement.swift` (or any other file) with a preserved copyright header. No license blocker.
- **Brand / name collision.** Calling the feature "Rectangle integration" in user-facing copy is misleading — Dock Tap would *reimplement a subset*, not integrate with Rectangle. Use neutral wording like "Window snap" in menu/README copy.
- **Maintenance debt.** Every additional AX-using app in the macOS ecosystem competes for the same trust grant and the same compatibility surface. Adding even Option B's six verbs adds an ongoing tail of "this app doesn't snap right" issues. Worth knowing before committing.

## Recommended scope

**Recommend Option A as the v1 stance, with Option B as a deliberate follow-on if and when the user wants it.**

Reasoning:

1. Dock Tap's current product is sharply focused: "one modifier + digit → activate app." That focus is its strongest asset right now. Adding window manipulation broadens the trust scope, broadens the key surface, and pulls Dock Tap into a category (window managers) where a free, MIT-licensed, well-maintained incumbent (Rectangle) already exists.
2. Most Dock Tap users who care about window snapping will already have Rectangle, Magnet, Moom, or AeroSpace installed. Pairing is the natural workflow; competing is not.
3. The trust ceiling matters: cross-app AX writes deserve a more deliberate distribution story (notarization, clearer copy) than current Dock Tap has.
4. If we later want to give users *something* in this space without becoming a window manager, Option B's six-verb minimum is well-bounded and reuses the existing event tap cleanly — the integration cost is modest and reversible.

Concretely:
- **v1 (now):** Option A. Add one line to `README.md` clarifying that Dock Tap is app-activation only and pointing users to Rectangle for window management. No code change.
- **v1.x (optional, if user opts in):** Option B behind a default-off setting. Land it after Dock Tap is notarized. Document the editor-overlap caveat. Keep the verb set to six. Do not attempt cycling, snap areas, layouts, thirds/sixths, or display moves in the first cut.
- **Never:** Option C. Rectangle exists; don't rebuild it.
- **Option D:** worth considering as a polish item alongside either A or B (e.g. menu hint "Tip: install Rectangle for window snapping" if not present, or "Rectangle detected — window snap disabled in Dock Tap to avoid conflicts" if both are installed and Option B is enabled).

## Open questions

These need a Lead/user decision before any implementation plan is drafted:

1. **Did the user actually mean Rectangle?** If they meant something else (a fork, Pro, Magnet, an internal tool), the recommendation may shift. Cheapest way to resolve: ask.
2. **Does the user want Dock Tap to grow into a window manager at all?** If the goal is "Dock Tap stays small and sharp," Option A is the whole answer. If the goal is "Dock Tap becomes my one keyboard launcher + snap utility," Option B is the path. The answer here decides everything downstream.
3. **Single preset for both?** If Option B is chosen: should window actions live under the same `TriggerModifierPreset` as the digit shortcuts (sharing keys is fine — arrows vs. digits don't collide), or should they have an independent preset (more flexible, but doubles the configuration surface)?
4. **Default-on or default-off?** Default-off avoids breaking existing users and avoids surprising arrow-key consumption; default-on makes the feature discoverable. v1 leaning is default-off.
5. **Vendor `AccessibilityElement.swift` from Rectangle, or write a thin original wrapper?** Vendoring is faster, MIT-compatible, and battle-tested; writing original is smaller and avoids inheriting Rectangle's complexity. Lead call.
6. **Notarization timing.** Should notarization be a prerequisite for Option B shipping, or can the in-house signed build carry it for early dogfooding?
7. **Distribution channel.** If Option B ships, do we publish to Homebrew Cask / GitHub Releases like Rectangle does, or keep the local-signed model? Affects the trust story above.

## Verification plan

This is a research deliverable, not an implementation. "Verification" here means:

- **For this plan:** dev-reviewer sanity-checks the claims about Rectangle's mechanism (AXUIElement / kAXPositionAttribute / kAXSizeAttribute), license (MIT), dependency list (MASShortcut + Sparkle), and the Dock Tap architecture mapping (event tap, decider, intent, activator, AX trust). Lead picks among Options A–D and (if A) approves the README addendum, or (if B/D) commissions a separate `docs/plans/m4-*.md` implementation plan.
- **For Option A, if adopted:** verification is a README copy review; nothing to run.
- **For Option B, if eventually adopted (out of scope for this plan):** a follow-up implementation plan must define its own automated tests (pure `RuleMatcher` branch tests for arrow keys; `SettingsStore` round-trip for the new key; `MenuContentModel` shape) and manual checks (snap a Safari window left/right; snap an Electron app; snap with Stage Manager on; verify arrow-key navigation in a text editor is unaffected when window actions are disabled, and **is** intercepted when they are enabled — the latter is the expected trade-off, not a bug).
- **No source changes, no shell commands, no `swift build` / `swift test` runs are expected from this plan itself.**
