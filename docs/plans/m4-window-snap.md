<!-- 修订v1: 创建——dev-planner 应 Lead 拍板（USER 已选定 Option B 第一版），落地六动作 native focused-window snap 的实现 plan -->
# M4 Window Snap Plan

## Context

Rectangle integration research (`docs/plans/rectangle-integration-research.md`) laid out four shapes (A do-nothing, B minimal native, C full parity, D detect-and-relay). USER picked **Option B, first version**: six native focused-window snap actions, off by default, no cross-display cycling, no Rectangle URL relay, no MASShortcut, no vendoring Rectangle wholesale. This plan is the implementation contract for that decision.

<!-- 修订v3: lead 拍板（应 Reviewer N-1）——删除 "AppActivator already takes intents off the main thread" 旧说法，统一为 EventTapController.enqueueShortcut 是主线程 handoff、AppActivator.runOnMain 是兜底 -->
M3 just shipped (`docs/plans/m3-menu-polish.md`); the menu, content model, settings, login item, and event tap are in their current polished shape. M4 extends them along the seams M3 left open — `ShortcutIntent` is already a discriminated enum, the tap-thread → main-thread handoff already lives in `EventTapController.enqueueShortcut(_:)` (`AppActivator.runOnMain` is a defensive fallback, not the primary hop), `RuleMatcher` already keys off a snapshot, and `MenuContentModel` already renders submenus. M4 should slot into those seams, not redesign them.

The trade-off USER accepted: window actions broaden the trust surface of the existing Accessibility grant from "observe input + activate apps" to "observe input + activate apps + write other apps' window frames." Default-off keeps the upgrade behavior-compatible; the menu toggle keeps the expansion deliberate.

## Locked scope

In scope:
- Six window actions on the focused window of the frontmost application:
  - `leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `maximize`, `center`.
- A single off-by-default setting `windowActionsEnabled` (persisted via `SettingsStore`).
- One menu toggle to flip that setting from the status menu, plus a `Window Snap` submenu listing the six bindings (read-only) for discoverability — mirrors the `Show Dock Mapping` submenu shape from M3.
- A native AX implementation: read frontmost app → focused window → its display's `visibleFrame` → compute target `CGRect` → write AX size then position. Single display only for the purposes of computing the target rect: the focused window stays on its current screen.
- Reuse of the existing `EventTapController` / `KeyEventDecider` / `RuleMatcher` / `ShortcutIntent` / per-shortcut log line pipeline. No new event source.
- Pure unit tests for the new matcher branch, the rect math, and the menu/settings additions. No XCTest coverage of live AX writes.
- README addendum documenting: the six actions, default-off, the editor-arrow-key trade-off, the "Rectangle does this better if you want the full suite" honest pointer.

Out of scope (do not add in M4):
- Cross-display cycling, `next-display` / `previous-display`, traverse-on-repeat.
- Drag-to-snap (would require a CGEvent mouse tap).
- Thirds, sixths, quarters, almost-maximize, restore, larger/smaller.
- Application layouts, snap zones, pinning, hide-behind-edge.
- Cycling: repeating a shortcut must produce the *same* result, not progress to a next size.
- Rectangle URL relay (`rectangle://execute-action?name=…`) and Rectangle install detection.
- Vendoring Rectangle's source wholesale; reimplement the small AX surface we need.
- MASShortcut, Carbon `RegisterEventHotKey`, or any second hotkey mechanism.
- A second `TriggerModifierPreset` dedicated to window actions; M4 shares the existing preset.
- Per-app overrides, blocklist, or "skip when an editor is focused" smart-mode.
- Notarization, Sparkle, installer, App Store packaging.
- Settings window / preferences UI; M4 sticks to the status menu.

## UX & shortcut mapping proposal

Same physical trigger preset that drives digits + backtick today drives the six new actions. The chosen key set must not collide with the existing `<preset>+1…0` digits or `<preset>+`` ` Finder shortcut, and should be physically intuitive for the action.

<!-- 修订v2: lead 拍板——锁 maximize=Return / center=Space，理由 减少 executor 前置 open question，USER 后续改可再修 -->
Locked binding (default, single-preset):

| Action     | Key                | Why                                                          |
|------------|--------------------|--------------------------------------------------------------|
| leftHalf   | `←` (left arrow)   | Spatial; matches Rectangle and Magnet defaults conceptually. |
| rightHalf  | `→` (right arrow)  | Same.                                                        |
| topHalf    | `↑` (up arrow)     | Same.                                                        |
| bottomHalf | `↓` (down arrow)   | Same.                                                        |
| maximize   | `Return`           | "Commit to full screen rectangle" reads as Return.           |
| center     | `Space`            | Large, unambiguous, doesn't collide with backtick.           |

Collision check against existing M3 bindings:
- Digit keys (18–29) and backtick (50) are disjoint from arrows (123–126), Return (36), and Space (49). Confirmed against `Sources/DockTap/KeyCodes.swift`.
- The matcher already requires the trigger preset to be the only physical modifier down, with shift rejected; arrow/Return/Space + a single modifier is a single physical-key chord and fits the same rule.

Caveat to call out in README and menu hint copy: when window actions are *enabled*, `<preset>+arrow` and `<preset>+Return`/`Space` are consumed by Dock Tap and will not reach text fields, editors, the focused app, **or system/global shortcut handlers**. Some users have heavy muscle memory for:
- **Editor / text-field shortcuts** — `Option+arrow` (word jump), `Command+arrow` (line / document jump), `Option+Return` (insert newline in some fields).
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——风险面扩展为 system/global shortcuts，理由 Command+Space (Spotlight) / Control+Space (IME 切换) 也被消费 -->
- **System / global shortcuts that share the trigger preset** — most notably `Command+Space` (Spotlight) and `Control+Space` (input source switch) when the user's trigger preset is Left/Right Command or Left/Right Control respectively. With the toggle on, those system shortcuts will be silently intercepted by Dock Tap's tap and replaced with the `center` action.

The interception is the expected trade-off, not a bug. Default-off is the mitigation; the toggle is the escape hatch; the chosen `TriggerModifierPreset` lets users sidestep specific overlaps (e.g. picking Left Option avoids the `Command+Space` Spotlight clash). Document this trio of caveats together in README so users can choose their preset accordingly.

<!-- 修订v4: lead 拍板——open questions 已清空，删除 cross-reference；alternatives 仅作为历史备忘，不在 M4 active -->
Alternative key sets (documented fallback only; **not active in M4** — the locked binding above is the implementation contract):
- Replace `Return` with `=` (key 24) and `Space` with `\` (key 42): keeps text-entry keys free, costs intuitiveness.
- Replace arrows with `h/j/k/l`: vim-style; introduces alpha-key consumption while typing, which is much worse than arrow consumption.

These alternatives are retained only so a future USER request to revise the bindings has a starting point; the executor must not implement them in M4.

## Architecture

The product split stays intent → execute:

- `EventTapController` produces raw key events on its dedicated tap run loop, snapshots inputs under a lock, and hands them to `KeyEventDecider`. Today its tuple is `(slotSnapshot, triggerModifierPreset)`. M4 extends that tuple with `windowActionsEnabled: Bool`. No new event source, no new tap.
- `KeyEventDecider` continues to be a one-line dispatcher into `RuleMatcher`. No structural change beyond passing the new flag through.
- `RuleMatcher` grows a third match branch. Order in `matchKeyDown`:
  1. Digit → `.dockSlot` (unchanged).
  2. Backtick → `.finder` (unchanged).
  3. If `windowActionsEnabled` and the key is in the window-action key set → `.windowAction(WindowAction, shortcutLabel:)`. If the flag is false, the branch is skipped entirely so the event is **not** consumed and passes through to the focused app normally.
- `ShortcutIntent` gains a `.windowAction(WindowAction, shortcutLabel:)` case. `label` keeps returning the shortcut label string for logging consistency.
- A new pure type `WindowAction` is the enum of six verbs. It owns the `targetRect(in visibleFrame: CGRect) -> CGRect` math — no AX calls, no AppKit imports beyond `CoreGraphics`. This is the single piece of geometry, and it is unit-tested in isolation.
- A new actor-like class `WindowActor` is the AX side, structurally parallel to `AppActivator`: takes a `LogStore`, exposes `perform(_ intent: ShortcutIntent)`, switches on the intent, looks up the frontmost app + focused window, computes the rect, writes AX. It is *not* tested under XCTest.
- `AppDelegate.handleShortcut(_:)` extends its switch (or just adds a sibling call) to route `.windowAction` intents to `WindowActor`; `.dockSlot` and `.finder` still go to `AppActivator`. AppDelegate also owns wiring the new settings toggle into `EventTapController.updateWindowActionsEnabled(_:)`.
- `MenuContentModel` learns one new section: a `Window Snap` submenu with six disabled rows (binding + action name) and a top-level toggle row. The toggle row is enabled regardless of Accessibility status; the submenu is shown regardless of toggle state so users can preview bindings before enabling.
- `AppText` adds the new strings (six action names, submenu title, toggle title, toggle-disabled hint).
- `SettingsStore` adds the `windowActionsEnabled` key with a default of `false`.

Hard invariants the executor must preserve:
- **Single shortcut owner.** A `<preset>+key` chord is owned by exactly one branch of `RuleMatcher`. The arrow/Return/Space keys are owned by the window-action branch *only when the toggle is on*; when it is off they belong to nobody and pass through. No double-fire, no fallback.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——精确化主队列跳转点：真正的脱离 tap thread 是 EventTapController.enqueueShortcut，AppActivator.runOnMain 是兜底 -->
- **No AX writes on the tap thread.** The real hand-off from the tap's dedicated run loop to the main queue happens in `EventTapController.enqueueShortcut(_:)` (it `DispatchQueue.main.async`-es the intent to `onShortcut`). `AppActivator.runOnMain` is a defensive fallback for callers that bypass that hand-off. `WindowActor` follows the same defensive pattern — it must be executed from the main queue, and the tap callback must never call into `WindowActor` (or any AX API) directly.
- **No event consumption without an intent.** If the matcher returns no intent, the decider returns `.passThrough`. This is already true and must stay true after the new branch is added.
<!-- 修订v2: lead 拍板（应 Reviewer C-4）——签名变化处显式传 windowActionsEnabled，理由 不要用默认值藏行为 -->
- **No default-value cover for the new matcher parameter.** `RuleMatcher.matchKeyDown` and `KeyEventDecider.decide` gain a required `windowActionsEnabled: Bool` argument with no default. Every production call site (`EventTapController.handle`) and every test call site (`RuleMatcherPresetTests`, `AppActivatorTests`) must pass it explicitly. The goal is that a future reader can grep one parameter and see who is enabling window actions and who is not.

## Files to change

New:
- `Sources/DockTap/WindowAction.swift` — pure enum + `targetRect(in visibleFrame: CGRect) -> CGRect` math (input is an AppKit `visibleFrame`; output is an AppKit-coordinate rect) + display name strings (probably delegated to `AppText`).
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——converter 彻底值类型化，新增 DisplayFrame 值类型；NSScreen 只能在 WindowActor 一层出现 -->
- `Sources/DockTap/DisplayFrame.swift` — pure value type. Fields:
  - `frame: CGRect` — display frame in AppKit coordinates.
  - `visibleFrame: CGRect` — visible (menu-bar / Dock excluded) frame in AppKit coordinates.
  - `isMain: Bool` — whether this display is the primary; exactly one entry in any valid `[DisplayFrame]` has `isMain == true` (or zero entries if the caller had no main display).
  - `identifier: String` (optional, log/test-readability only).
  - `scaleFactor: CGFloat` (optional, log/test-readability only — **must not** participate in any coordinate math; the converter does not scale).
- `Sources/DockTap/ScreenCoordinateConverter.swift` — pure helper. Operates entirely on `DisplayFrame` values and `CGRect` / `CGPoint`; **never references `NSScreen`**. Public API:
  - AX rect → AppKit rect, AppKit point → AX point, AX point → AppKit point (sizes never converted — `width` and `height` are coordinate-system invariant).
  - `selectDisplay(for axRect: CGRect, in displays: [DisplayFrame]) -> DisplayFrame?` — convert `axRect` to AppKit internally, then pick the display with maximum frame intersection; on a tie or zero intersection, pick the display containing the converted rect's center; if still none, fall back to the display in `displays` with `isMain == true`; if no display has `isMain == true`, return `nil` (caller decides what to do — `WindowActor` will log and no-op).
  - The "primary display top-left = (0, 0)" anchor that the AX↔AppKit translation relies on is computed from the `isMain == true` entry's `frame` and `frame.height`. If no main exists, AX↔AppKit conversions return `nil`/throw a logged failure (`WindowActor` log + no-op).
- `Sources/DockTap/WindowActor.swift` — AX side, sibling of `AppActivator`. **This is the only file in M4 that may read `NSScreen.screens`, `NSScreen.main`, `NSScreen.frame`, `NSScreen.visibleFrame`, or `NSScreen.backingScaleFactor`.** It maps `NSScreen.screens` to `[DisplayFrame]` (each entry's `isMain` is set by `screen == NSScreen.main`), passes the resulting array to `ScreenCoordinateConverter`, and never calls `NSScreen.frame.contains` on a raw AX point.
- `Sources/DockTap/AccessibilityWindow.swift` (small AX wrapper) — thin shim over `AXUIElement` for `frontmostApplicationElement`, `focusedWindow`, `frame` (returned in AX coordinates), `setFrame(_:adjustSizeFirst:)` (accepts AX coordinates). Keep it minimal; do not mirror Rectangle's full surface area. If `WindowActor` is short enough to inline the AX dance, this file can be skipped — Lead call during code review.
- `Tests/DockTapTests/WindowActionTests.swift` — pure tests for `targetRect(in:)` (AppKit-coordinate math only) and the action name strings.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——独立 ScreenCoordinateConverterTests，理由 坐标换算回归不能藏在 WindowActionTests 里 -->
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——tests 只构造 DisplayFrame 值，禁止构造 NSScreen；fallback 走 isMain，不再提 NSScreen.main -->
- `Tests/DockTapTests/ScreenCoordinateConverterTests.swift` — **constructs only `DisplayFrame` values; never instantiates `NSScreen`.** Fixtures: (a) single primary `DisplayFrame` at AppKit origin `(0,0)` with `isMain: true`; (b) primary + secondary **below** primary in AppKit (`secondary.frame.origin.y < 0`); (c) primary + secondary **above** primary (`secondary.frame.origin.y > primary.frame.height`); (d) primary + secondary **to the right** of primary at non-zero X; (e) primary + secondary with a different `scaleFactor` value — assert the converter outputs are identical to fixture (a)/(d) sizes (scaleFactor is metadata only, must not participate in math). For each, assert AX→AppKit and AppKit→AX round-trip identity on representative points, and assert `selectDisplay(for:in:)` returns the correct `DisplayFrame` for a window that straddles the boundary (max-intersection wins). Additional cases:
  - Straddle tie or zero intersection → falls back to the `DisplayFrame` containing the converted rect's center.
  - Window fully off-screen → falls back to the `isMain: true` entry.
  - `[DisplayFrame]` with **no** `isMain: true` entry → `selectDisplay` returns `nil`; AX↔AppKit conversion APIs also surface the missing-main case as `nil` / logged failure.
  - Empty `[DisplayFrame]` → `selectDisplay` returns `nil`.
- `Tests/DockTapTests/RuleMatcherWindowActionTests.swift` — branch tests, especially the off-by-default behavior.
- `Tests/DockTapTests/MenuContentModelWindowSnapTests.swift` — or extend existing `MenuContentModelTests.swift` with a focused fixture.

Modified:
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——ShortcutIntent 新增 case 会让 AppActivator.route(for:) 的穷尽 switch 编译失败，必须改 -->
- `Sources/DockTap/ShortcutIntent.swift` — add `.windowAction(WindowAction, shortcutLabel: String)`; update `label`. **All exhaustive switches on `ShortcutIntent` in the codebase become incomplete and must be addressed in the same change** — search for `switch intent` / `switch route` / `switch self` over `ShortcutIntent` and `AppActivationRoute` before declaring the change done.
- `Sources/DockTap/KeyCodes.swift` — add `leftArrow=123`, `rightArrow=124`, `downArrow=125`, `upArrow=126`, `returnKey=36`, `space=49`; extend `label(for:)` for log readability.
- `Sources/DockTap/RuleMatcher.swift` — add the third branch; matcher signature grows a required (no-default) `windowActionsEnabled: Bool` parameter.
- `Sources/DockTap/KeyEventDecider.swift` — pass the new (no-default) flag through to `RuleMatcher`.
- `Sources/DockTap/EventTapController.swift` — store `windowActionsEnabled` under `inputLock`; add `updateWindowActionsEnabled(_:)`; extend `currentInputSnapshot()` return tuple; pass flag into `decider.decide(…)`.
- `Sources/DockTap/SettingsStore.swift` — add `var windowActionsEnabled: Bool` with key `windowActionsEnabled`, default `false`.
- `Sources/DockTap/AppDelegate.swift` — instantiate `WindowActor`; pass initial `windowActionsEnabled` into `EventTapController` next to the existing trigger preset wiring; add a `@objc toggleWindowActionsEnabled` action; **split intents at `handleShortcut(_:)` — `.windowAction` goes to `WindowActor`, `.dockSlot` / `.finder` go to `AppActivator`. `.windowAction` must never reach `AppActivator.perform(_:)`.** Trigger `rebuildMenu()` on toggle.
- `Sources/DockTap/MenuContentModel.swift` — add `windowSnapToggleTitle`, `windowSnapToggleIsOn`, `windowSnapSubmenuTitle`, `windowSnapRows: [WindowSnapRow]` (binding string + display name); render the new submenu in the toggle/operations group.
- `Sources/DockTap/AppText.swift` — six action display names, the submenu title, the toggle title (e.g. `Window Snap`), an optional disabled hint.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——AppActivator.route(for:) 穷尽 switch 必须处理 .windowAction case；AppDelegate 已分流，这里只是编译保险 -->
- `Sources/DockTap/AppActivator.swift` — `AppActivationRoute` gains an `ignoredNonActivationIntent(shortcutLabel: String)` (or equivalent name) case; `route(for:)` returns it for any non-activation intent (today: `.windowAction`); `execute(_:)` logs `action skipped non-activation intent shortcut=<label>` for that route and returns. This is a **defensive compile-keeper, not the production path** — `AppDelegate.handleShortcut(_:)` must already have routed `.windowAction` to `WindowActor`, so `AppActivator` should not receive `.windowAction` in normal operation. Keep the diff to that single new case plus the corresponding switch arms; do not refactor the activate / launch helpers.
- `Tests/DockTapTests/RuleMatcherPresetTests.swift` — update existing `decider.decide(…)` call sites at lines 151, 164, 208 to explicitly pass `windowActionsEnabled: false` (M3 regression coverage stays with the flag off); add fixtures confirming digits and backtick still match when the flag is *true*; confirm arrows do **not** match when the flag is false.
<!-- 修订v2: lead 拍板（应 Reviewer B-1, C-4）——AppActivatorTests 同时受 ShortcutIntent 新 case 与 KeyEventDecider 新参数影响，必须列入 -->
- `Tests/DockTapTests/AppActivatorTests.swift` — update the `KeyEventDecider().decide(…)` call site at line 39 to explicitly pass `windowActionsEnabled: false`; add a test that `AppActivator.route(for: .windowAction(...))` returns the new `ignoredNonActivationIntent(...)` case (defensive-route assertion); existing `.dockSlot` / `.finder` routing tests must continue to pass unchanged.
- `Tests/DockTapTests/SettingsStoreTests.swift` — round-trip the new key, default value, last-write-wins.
- `Tests/DockTapTests/MenuContentModelTests.swift` — extend if the windowSnap rows are added inline rather than in a separate file.
- `Tests/DockTapTests/AppTextTests.swift` — if branching logic is added.
- `README.md` — new "Window Snap" section after "Trigger Presets": six bindings table, default-off note, enable steps, **the editor + system/global shortcut conflict trade-offs** (Option/Command/Ctrl + arrow text navigation, `Command+Space` Spotlight when the preset is Command, `Control+Space` IME switch when the preset is Control), preset-choice guidance for sidestepping specific overlaps, and the "for cycling/thirds/layouts use Rectangle" pointer.
- `docs/plans/m4-window-snap.md` — this plan.

Unchanged (must not regress):
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——AppActivator.swift 从 do-not-touch 移到 modified/touch-with-care -->
- `Sources/DockTap/DockSlotStore.swift`, `DockPreferencesReader.swift`, `LoginItemController.swift`, `LoginItemMenuModel.swift`, `PermissionGate.swift`, `ActiveAppProvider.swift`, `ModifierState.swift`, `TriggerModifierPreset.swift`, `LogStore.swift`, `LogWindowController.swift`.

## Data model & settings

`WindowAction`:
```
enum WindowAction: String, CaseIterable, Equatable {
    case leftHalf, rightHalf, topHalf, bottomHalf, maximize, center
}
```
- Raw values double as `UserDefaults`-stable identifiers and log strings.
- `targetRect(in visibleFrame: CGRect) -> CGRect` is the only behavior; signatures are pure-functional.

`SettingsStore` key:
- Key string: `windowActionsEnabled`. Type: `Bool`. Default: `false`.
- Read at app launch and pushed into `EventTapController` next to the existing preset push.
- Written by the menu toggle. After write, push into `EventTapController` and call `rebuildMenu()`.

No per-action settings, no custom key bindings, no per-app overrides. The six bindings are hard-coded in `RuleMatcher` for v1.

`MenuContentModel` additions:
- `windowSnapToggleTitle: String` — e.g. `"Window Snap"`.
- `windowSnapToggleIsOn: Bool` — drives `NSMenuItem.state`.
- `windowSnapSubmenuTitle: String` — e.g. `"Show Window Snap Bindings"`.
- `windowSnapRows: [WindowSnapRow]` — `{ title: "<preset>+←  Left Half", action: .leftHalf }`. Always populated regardless of toggle state, so users can preview before enabling.

No new `LoginItemMenuModel`-style helper; the toggle is a single-line item.

## AX implementation notes

`WindowActor.perform(_:)` routes only `.windowAction` intents; `.dockSlot` and `.finder` go through `AppActivator`. The actor hops to the main queue using the existing `runOnMain` pattern in `AppActivator`.

<!-- 修订v2: lead 拍板（应 Reviewer B-2）——屏幕选择和坐标换算必须显式同坐标系；不可对 raw AX point 调 NSScreen.frame.contains -->
Coordinate-system contract (this is the section to read most carefully):
- **AX coordinates**: top-left origin, primary display top-left = `(0, 0)`, Y grows downward. All `AXValueCreate(.cgPoint, …)` and `AXValueGetValue(.cgPoint, …)` traffic in this space. Same for `.cgRect` if used.
- **AppKit coordinates**: bottom-left origin, primary display bottom-left = `(0, 0)`, Y grows upward. `NSScreen.frame` / `NSScreen.visibleFrame` live here.
- **Sizes** (`width`, `height`) are coordinate-system invariant; only origins flip. Never apply the Y-flip to a size.
- All coordinate decisions inside `WindowActor` are made in AppKit space. AX values are converted at the boundary (just after read, just before write) via `ScreenCoordinateConverter`. Raw AX points never participate in `NSScreen.frame.contains` or any AppKit geometry.

Per-call sequence:
1. Log `action start windowAction=<rawValue>`.
2. `NSWorkspace.shared.frontmostApplication` → if `nil`, log `action failed windowAction=<rawValue> no frontmost app` and return.
3. Build `AXUIElementCreateApplication(pid)` for that app's `processIdentifier`.
4. `AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, &value)` → if not `.success` or value is nil, log `action failed windowAction=<rawValue> no focused window axError=<code>` and return.
5. Read the window's current AX position and size (`kAXPositionAttribute`, `kAXSizeAttribute`). Build an AX-coordinate `CGRect` from them.
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——WindowActor 把 NSScreen.screens 映射成 [DisplayFrame] 后传给 converter；converter 决不见 NSScreen；fallback 走 isMain，不在 converter 内提 NSScreen.main -->
6. **Map `NSScreen.screens` to `[DisplayFrame]`**, marking the entry equal to `NSScreen.main` as `isMain: true`. This mapping is the *only* place in M4 that reads `NSScreen` — `DisplayFrame` is a pure value type and is the only display-geometry type that crosses into `ScreenCoordinateConverter` and from there into tests.
7. **Convert the AX-coordinate rect to an AppKit-coordinate rect** via `ScreenCoordinateConverter`, passing in the `[DisplayFrame]` from step 6.
8. **Pick the target display** with `ScreenCoordinateConverter.selectDisplay(for: <converted AppKit rect>, in: <displays>)`. The converter's policy is: maximum frame intersection → containing-center on tie/zero → `isMain: true` fallback → `nil`. If the converter returns `nil`, `WindowActor` logs `action failed windowAction=<rawValue> no selectable display` and returns. The window stays on its current display — pick-display is "where is this window now," not "where should it go."
9. Compute the target rect in AppKit coordinates: `let targetAppKit = action.targetRect(in: chosenDisplay.visibleFrame)`. `targetRect` is pure AppKit math and knows nothing about AX or `DisplayFrame`.
10. **Convert the target rect's origin back to AX coordinates** via `ScreenCoordinateConverter` (size stays unchanged). The result is an AX-coordinate `CGPoint` + an unchanged `CGSize`. If the converter cannot translate (e.g. the `[DisplayFrame]` had no `isMain: true` entry — a degenerate runtime state), log and return.
11. Write order — size first, then position. This matches Rectangle's `adjustSizeFirst` pattern and is the safe default for the six v1 actions (all stay on the current display).
12. `AXUIElementSetAttributeValue(window, kAXSizeAttribute, AXValueCreate(.cgSize, &size))`; check return code.
13. `AXUIElementSetAttributeValue(window, kAXPositionAttribute, AXValueCreate(.cgPoint, &positionAX))`; check return code.
14. Log `action applied windowAction=<rawValue> rectAppKit=<x,y,w,h> originAX=<x,y> axSizeResult=<code> axPositionResult=<code>`. Logging both rect spaces makes coordinate-bug forensics trivial.

Failure modes and how `WindowActor` handles each:
- **No frontmost app** (rare; happens momentarily during app launch/quit): log + no-op. No alert, no error sound.
- **Frontmost app has no focused window** (Finder with no window, browser with all windows closed): log + no-op.
- **Window is fullscreen** (`kAXFullscreenAttribute` is true): AX writes will typically fail or be silently ignored. Read `kAXFullscreenAttribute` *before* writing; if true, log `action skipped windowAction=<rawValue> fullscreen` and return. Do not try to exit fullscreen.
- **Window is non-resizable** (`kAXResizableAttribute` false, or sentinel windows like dialogs): writes will partially succeed. Do not pre-check; let AX return its error code and log it. Users can see the no-op in logs.
- **App rejects AX writes** (Electron with custom frame, some Java apps): AX returns success but window does not move, or returns `.cannotComplete`. Log the AX code. Document in README: known incompatibilities exist; this is inherent to the AX API, not a Dock Tap bug.
- **AX call blocks** (target app is hung): the main queue may stall briefly. Document as a known risk in §Risks; mitigation deferred to a future plan if it becomes a real problem.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——撤权处理写实：只 log + no-op；不声称 PermissionGate 自动恢复菜单状态，源码当前不是这样 -->
- **Permission missing or revoked mid-session**: AX write calls return `.apiDisabled` (or `.notImplemented` for some windows). `WindowActor` logs the code and no-ops. M4 does **not** promise that the menu's Accessibility/permission state will automatically re-flip after a revoke — `PermissionGate` + the existing recheck timer in `AppDelegate.schedulePermissionRecheck` only run while the tap is still being installed; once installed, there is no live revoke→re-prompt loop. Re-extending that lifecycle (continuous re-check after revoke, menu downgrade on revoke, tap re-install on re-grant) is **out of scope for M4** and is captured below as a future-hardening note, not a blocker.

The actor must **not**:
- Activate the app it is snapping (no `NSRunningApplication.activate` here — snapping is intentional, activating is the user's `AppActivator` job).
- Iterate or enumerate windows beyond the focused one.
- Walk Spaces or move windows across Spaces.
- Read or write any AX attribute other than the four named above (`kAXFocusedWindow`, `kAXPosition`, `kAXSize`, `kAXFullscreen`).

## Testing plan

Pure unit tests (XCTest, no AX):

- **`WindowActionTests`** (AppKit-coordinate math only — coordinate-system conversion is a separate file's job)
  - `targetRect(in:)` for each of the six actions against a representative `visibleFrame` (e.g. `origin = (0, 0)`, `size = (1440, 900)`): expected rects match the documented halves / maximize / center math.
  - Same six against a non-zero-origin frame (e.g. `origin = (1440, 28)` simulating a secondary display offset to the right of the primary with a menu-bar inset): asserts that `targetRect` is computed in the input frame's coordinate space and does not assume `(0, 0)` origin.
<!-- 修订v2: lead 拍板——center 尺寸锁 75% × 75% visibleFrame，居中；test 直接断言 -->
  - `center` produces a rect whose size equals `visibleFrame.size × 0.75` (locked default; document the constant in `WindowAction` as a single named property) and whose origin centers the rect inside `visibleFrame`.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——独立 ScreenCoordinateConverterTests，理由 坐标换算不能塞进 WindowActionTests 蹭车 -->
- **`ScreenCoordinateConverterTests`** (the dedicated coordinate-system regression net)
  - Fixture A — single primary display at AppKit origin `(0, 0)`, size `(1440, 900)`: AX→AppKit and AppKit→AX round-trip identity on a grid of points; converted top-left and bottom-right of the primary frame match the AX expectation.
  - Fixture B — primary `(0,0)–(1440,900)` + secondary **below** primary `(0,-900)–(1440,0)` in AppKit (which is AX rows 900–1800): a window centered on the secondary screen converts to AX Y in the 900–1800 band, not 0–900.
  - Fixture C — primary + secondary **above** primary at AppKit `(0,900)–(1440,1800)`: AX Y must be negative for the secondary, since AX origin sits at the primary top-left.
  - Fixture D — primary + secondary **to the right** of primary at AppKit `(1440,0)–(2880,900)`: pure X offset, Y unchanged.
  - Fixture E — primary + secondary with a different scale factor (e.g. 2× retina + 1× external): assert size is **not** scaled by the converter (sizes are coordinate-system invariant); only origin is translated.
<!-- 修订v4: lead 拍板（应 Reviewer B-1 残留）——screen-pick 描述只走 DisplayFrame.isMain，禁止再出现 NSScreen.main / fixture supplies / main = nil -->
  - Screen-pick function (`selectDisplay(for:in:)`, all inputs are `DisplayFrame` values — no `NSScreen` ever constructed): a window straddling two displays picks the `DisplayFrame` with maximum frame intersection; a window fully on one display picks that `DisplayFrame`; a window outside any display falls back to the `DisplayFrame` whose `isMain == true`; a `[DisplayFrame]` with **no** entry where `isMain == true` (or an empty array) returns `nil`, and the caller (`WindowActor`) logs and no-ops.
- **`RuleMatcherWindowActionTests`**
  - Arrow / Return / Space key under the matching trigger preset with `windowActionsEnabled: true` → returns `.windowAction(...)` with the expected `WindowAction`.
  - Same keys with `windowActionsEnabled: false` → returns `nil` (event passes through; no consumption).
  - Arrow keys with a non-matching modifier (e.g. preset is leftOption but rightCommand is down) → returns `nil` regardless of flag state.
  - Digit keys and backtick continue to match identically regardless of the new flag (regression guard for M3 behavior).
  - Shift + trigger + arrow → rejected (existing shift-rejection rule still wins).
<!-- 修订v2: lead 拍板（应 Reviewer B-1, C-4）——所有现有 decider.decide 调用点必须显式传 windowActionsEnabled: false -->
- **`RuleMatcherPresetTests`** (updates to existing file)
  - The three existing `decider.decide(…)` call sites at lines 151, 164, 208 must be edited to explicitly pass `windowActionsEnabled: false` — no default-value reliance. The existing assertions stay; only the new argument is added.
- **`AppActivatorTests`** (updates to existing file)
  - The existing `KeyEventDecider().decide(…)` call site at line 39 gets the same explicit `windowActionsEnabled: false` argument.
  - New: `AppActivator.route(for: .windowAction(...), context: ...)` returns `ignoredNonActivationIntent(shortcutLabel: <expected>)` — the defensive-route assertion that locks the compile-keeper behavior described in §Files to change.
  - Existing `.dockSlot` / `.finder` routing tests stay green unchanged.
- **`SettingsStoreTests`**
  - `windowActionsEnabled` defaults to `false` for a fresh `UserDefaults`.
  - Round-trips both `true` and `false`.
  - Last write wins.
- **`MenuContentModelTests`** (or new `MenuContentModelWindowSnapTests`)
  - Toggle title and `isOn` state reflect the input flag.
  - `windowSnapRows.count == 6` and rows are stable-ordered: leftHalf, rightHalf, topHalf, bottomHalf, maximize, center.
  - Row titles include the current trigger preset prefix (e.g. `"Left Option+←  Left Half"`), matching M3's preset-prefixed shortcut label convention.
- **`AppTextTests`** — only if `AppText` gains branching logic; six static strings need no test.

Not unit-tested (manual only — these depend on a live AX hierarchy):
- `WindowActor.perform(_:)` end-to-end.
- `EventTapController` consumption / pass-through of arrow keys.
- Actual cross-app window movement.

## Manual verification

Run with `DOCK_TAP_CODESIGN_IDENTITY="<local signing identity>" scripts/run-app.sh` and grant Accessibility to the signed bundle (`ai.resopod.docktap`).

Toggle-off baseline (regression guard for existing users):
- `Window Snap` toggle is off by default on first launch with a fresh `UserDefaults`.
- With the toggle off, press `<preset>+←` in a text field — the cursor jumps as macOS normally does. Dock Tap does not consume the event. Log shows no `action start windowAction=…` line.
- With the toggle off, all M3 behavior (digits 1–0 activate Dock apps, backtick activates Finder, trigger preset switch, Launch at Login, mapping submenu) works unchanged.

Toggle-on basic checks:
- Flip `Window Snap` on from the menu. The menu rebuilds; the submenu shows six rows; the toggle row is checked.
- Focus a resizable app (Safari, Notes, TextEdit). `<preset>+←` snaps it to the left half of the current screen. `<preset>+→` to the right half. `<preset>+↑` top half. `<preset>+↓` bottom half. `<preset>+Return` maximize. `<preset>+Space` center.
- Logs show one `action start` and one `action applied` line per shortcut with the expected `rect=` payload.
- Window stays on its current display; it does not jump to the main display.
- Snapping a window twice in a row with the same shortcut yields the same final rect (no cycling).

<!-- 修订v2: lead 拍板（应 Reviewer C-1）——manual verification 增加 system/global shortcut 冲突检查 -->
System / global shortcut conflict checks (only relevant when the trigger preset overlaps a system shortcut):
- With trigger preset = **Left Command** or **Right Command** and the toggle **on**, press `<preset>+Space` — Dock Tap performs the `center` action; macOS **Spotlight does not open**. Confirm this is the documented trade-off; the mitigation is either toggle off, or switch the trigger preset to something other than Command.
- With trigger preset = **Left Control** or **Right Control** and the toggle **on**, press `<preset>+Space` — Dock Tap performs `center`; the **input-source switcher does not appear**. Same mitigation.
- With trigger preset = **Left Option** and the toggle **on**, press `<preset>+←` / `<preset>+→` inside a text field — Dock Tap performs the half-snap; the cursor's **word-jump behavior is intercepted**. Same mitigation.
- With trigger preset = **Left Option** and the toggle **off**, repeat all of the above — every system / editor shortcut works as macOS normally delivers it. This is the regression guard that protects existing users on default settings.

Edge cases:
- Focus is in a text editor (Xcode, VS Code, a Notes note): with the toggle on, arrow shortcuts are intercepted and the cursor does **not** move. Confirm this is the documented trade-off and not a regression.
- Focus is on Finder with no open window: `<preset>+←` logs `no focused window` and is a no-op.
- A fullscreen Safari window: `<preset>+←` logs `fullscreen` and is a no-op; Safari stays fullscreen.
- An Electron app (e.g. VS Code, Slack): snap may visually succeed, succeed partially, or no-op depending on the app's window frame handling. Log the AX result code. Do not file a Dock Tap bug for known Electron quirks.
- An app whose process is hung: snap call may briefly stall. Verify the menu can still be opened afterwards.
- Stage Manager enabled: snap a window inside the active Stage Manager strip; clamping may occur. Document observed behavior; do not attempt to special-case it in v1.
- Multi-display: snap a window on the secondary display; it must stay on that display and resize to that display's `visibleFrame` halves.
- After grant: with Accessibility just freshly granted (was missing on launch, granted at runtime), `Window Snap` works on the first attempt without restart — same recovery path the existing tap install uses.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——撤权后菜单不保证自动恢复，M4 只承诺 log + no-op -->
- After revoke: with Accessibility revoked mid-session, snap logs an `apiDisabled` AX code and no-ops. The menu's permission status row is **not** guaranteed to flip back to "Missing Accessibility Permission" automatically — that recovery would need a new live recheck path which is explicitly out of scope for M4 (see §Risks). The user-visible signal of revocation in M4 is the `apiDisabled` line in the log and the silent no-op.
- Switching trigger preset while window actions are on: row titles in the submenu update to the new preset prefix; bindings still fire under the new preset.

README sanity:
- `Window Snap` section accurately describes the six bindings, default-off, the editor-arrow-key trade-off, and points to Rectangle for the verbs we deliberately do not ship.

## Risks & mitigations

<!-- 修订v2: lead 拍板（应 Reviewer C-1）——风险面扩展为系统/全局快捷键，不只 text editor -->
- **Arrow / Return / Space consumption breaks text-editing AND system / global shortcut flows when the toggle is on.** Editor flows: `Option+arrow` (word jump), `Command+arrow` (line/document jump). System flows: `Command+Space` (Spotlight) when the preset is Command; `Control+Space` (input-source switch) when the preset is Control. Mitigation: default-off; toggle is a one-click revert; README spells out the trade-offs together with per-preset guidance ("if you rely on Spotlight, don't pick Command as your trigger preset"); submenu binding list lets users preview before enabling.
- **Trust scope semantically expands without a new TCC prompt.** Mitigation: README addendum names the expansion explicitly; toggle is the user-controlled opt-in.
- **AX writes block the main queue when the target app is hung.** Mitigation deferred — v1 accepts the rare stall. Re-evaluate if a real user hits it.
- **Coordinate-system confusion between AppKit `visibleFrame` (bottom-left origin) and AX (top-left origin).** Mitigation: explicit conversion in `WindowActor`; a non-zero-origin fixture in `WindowActionTests` guards the rect math; document the conversion site with a one-line comment because the *why* (cross-coordinate-system glue) is non-obvious.
- **App-specific AX rejections (Electron, Java, certain dialogs).** Mitigation: log AX result codes; README sets the expectation that these are inherent.
- **Stage Manager / Mission Control / Spaces interactions are unpredictable.** Mitigation: manual verification covers Stage Manager; no automated mitigation in v1.
- **Double-firing if the executor wires the new branch into both the matcher and a parallel hook.** Mitigation: the matcher is the single owner — restated as a hard invariant in §Architecture; executor must not add a sibling tap or callback for window actions.
- **Settings flag drift between `EventTapController` and `AppDelegate`.** Mitigation: `EventTapController` is the single source of truth at the tap layer; `AppDelegate` writes to `SettingsStore` and pushes via `updateWindowActionsEnabled(_:)`. Do not read settings from inside the tap callback.
- **MenuContentModel scope creep.** Mitigation: `windowSnapRows` is purely presentational; no Accessibility checks, no AX queries, no `SettingsStore` reads inside the model — same boundary M3 enforced.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——撤权恢复明列 future hardening，不进 M4 -->
- **Permission lifecycle does not handle live revoke after the tap is installed (future hardening, not M4 scope).** `PermissionGate` + `AppDelegate.schedulePermissionRecheck` only run on the path from "not trusted" → "trusted + tap installed." Once the tap is installed, a subsequent revoke in System Settings is **not** observed; the menu status, the tap, and the new `Window Snap` toggle continue to display "Ready" while AX writes silently no-op with `apiDisabled`. M4 explicitly declines to fix this; a future plan can add a live-recheck loop, a menu downgrade on revoke, and tap re-install on re-grant.

<!-- 修订v2: lead 拍板（应 Reviewer N-2）——清理 open questions：锁定 Return/Space + 75%；移除 notarization 和 top-level examples 让 executor 可直接开工 -->
## Open questions needing USER decision

Cleaned for v2 — only items that actually block the executor remain. Locked items are noted inline so future readers can see what moved.

<!-- 修订v3: lead 拍板（应 Reviewer C-1）——菜单 toggle 文案锁为 "Window Snap"，从 open questions 移到 locked -->
*(v3 update: no remaining items require a decision before the executor begins. The single remaining v2 item — menu toggle label — has been locked to `Window Snap` and moved to the Locked list below.)*

Locked in v2 + v3 (no longer open):
- Key set: `←/→/↑/↓` for halves, `Return` for `maximize`, `Space` for `center`. Lead-locked; USER can revise post-ship via a follow-up.
- `center` size: `0.75 × visibleFrame.width × 0.75 × visibleFrame.height`, centered inside `visibleFrame`. Named constant in `WindowAction`, asserted in `WindowActionTests`.
- AX result-code surfacing: logs only in M4. Any menu/status surfacing is M5 scope.
- **Menu toggle label: `Window Snap` (locked in v3).** Submenu title remains `Show Window Snap Bindings`. Pin both in `AppText` exactly as spelled here so README, menu copy, and tests agree.

Deferred to future notes (not executor-blocking, captured for §Risks / follow-up planning):
- Notarization timing — independent of M4; raise when distribution shape is the topic. Not a M4 ship-block.
- Top-level examples row for Window Snap — plan default stays "no top-level example, submenu only." Revisit only if USER asks for top-level discoverability after dogfooding.
- Live permission revoke handling — captured in §Risks as out-of-scope future hardening.

## Execution zones

For the executor that picks this up:

- **Allowed to touch** (modify with intent; obey the §Files to change list):
  - All files listed under §Files to change.
  - `README.md` — only the new `Window Snap` section and the existing surrounding section ordering if needed for flow.
- **Touch with care** (small, contained edits only; do not refactor):
  - `Sources/DockTap/EventTapController.swift` — extending the input tuple and adding one `updateWindowActionsEnabled(_:)` method is the entire scope. Do not refactor the tap install / run-loop / recovery code.
  - `Sources/DockTap/AppDelegate.swift` — add `WindowActor`, the toggle action, and the switch arm. Do not re-shape `rebuildMenu` beyond inserting the new toggle row and submenu in the existing operations section.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——AppActivator.swift 从 do-not-touch 提升为 touch-with-care，理由 ShortcutIntent 新 case 会击穿穷尽 switch -->
  - `Sources/DockTap/AppActivator.swift` — only the `AppActivationRoute` enum gains `ignoredNonActivationIntent(shortcutLabel:)`, only `route(for:)` gains the new switch arm, and only `execute(_:)` gains the matching log-and-return arm. **This is a defensive compile-keeper, not the production path** — `AppDelegate.handleShortcut(_:)` splits intents first and `.windowAction` never reaches here in normal operation. Do not refactor activate / launch helpers, do not touch the `AppActivationContext` shape.
- **Do not touch**:
  - `Sources/DockTap/DockPreferencesReader.swift`, `DockSlotStore.swift`, `ActiveAppProvider.swift` (Dock-side state, irrelevant to window actions).
  - `Sources/DockTap/PermissionGate.swift` (existing Accessibility check covers AX writes; no change needed).
  - `Sources/DockTap/LoginItemController.swift`, `LoginItemMenuModel.swift`.
  - `Sources/DockTap/ModifierState.swift`, `TriggerModifierPreset.swift` (the rule layer; M4 reuses, does not extend).
  - Test fixtures under `Tests/DockTapTests/Fixtures/`.
  - `scripts/run-app.sh`, `Package.swift`, packaging / signing scripts.
- **Hard "do not"**:
  - Do not add MASShortcut, Carbon hotkeys, or any second input source.
  - Do not vendor Rectangle source files; reimplement the small AX surface inline.
  - Do not introduce per-app overrides, cycling, snap zones, or any verb beyond the six.
  - Do not change the default of `windowActionsEnabled` to `true`.
  - Do not consume any key chord under the trigger preset that the matcher does not own; pass-through is the default.
  - Do not call AX from the tap thread; hop to the main queue.
