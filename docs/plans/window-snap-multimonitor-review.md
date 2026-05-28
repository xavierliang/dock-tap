<!-- 修订v1: 创建——dev-planner 应 Lead 指派，对 DockTap M4 已落地的 window snap 做 multi-monitor 重点 review，待两份 reviewer 报告回流后再修订 -->
<!-- 修订v2: lead 拍板——同根因确认 + 修复方向收敛：anchor display 与 current/selected display 概念分离；DisplayFrame.isMain 改名为 isCoordinateAnchor；anchor 从 NSScreen.screens.first（或 CGMainDisplayID）取而非 frame.origin==.zero；测试矩阵补 "selected ≠ anchor" 与 vertical layout 用例。 -->
<!-- 修订v3: 应 Reviewer Tests C-1/C-2/C-3/N-1——converter 测试补 left-of-anchor 负 X 与 side+vertical offset；manual matrix 加左/上下/offset/visibleFrame inset/fully-vs-straddling 及预期 AX 符号与 band；新增 RuleMatcherWindowActionTests 跨 trigger preset 用例；m4 plan §AX impl notes step 8 修正为 selectDisplay 接 AX rect。 -->
<!-- 修订v4: 应 Reviewer Multi B-1/C-1/C-2/C-3/C-4/N-1——B-1 跨 reviewer 二次确认；新增 C-6（action applied 无条件 log）/ C-7（minimized 窗口未定义，原 N-3 升级）/ C-8（M4 commit 误带 rectangle-integration-research.md，已 git 验证）；test gap 补 unstable-anchor 用例；新增 §Staged fix plan 按 blocker→correctness→test→hygiene 排序。Reviewer Multi C-3/N-1 与 v3 已记重叠，仅加交叉引用。 -->
<!-- 修订v2: lead 拍板（v2 final consolidation reset）——Lead 把多轮 inflight 版本（dev-planner 计数 v1→v2→v3→v4）正式折成 v2 final report。本轮所有新加 marker 使用 "修订v2"；上面 v2/v3/v4 marker 保留为 deliberation 历史断面。本轮决议见下方各 site 的 "修订v2: lead 拍板——..." 标记。 -->
<!-- 修订v2: lead 拍板——anchor 取法 final rule：优先 `screen.frame.origin == .zero`（AppKit 原点屏 / 菜单栏屏的几何判据），fallback `NSScreen.screens.first` 并 log warning；NSScreen.main 永远不用（Apple docs 明确它是键盘焦点屏）。这是对 dev-planner v1 (frame.origin) 与 dev-planner v2 (NSScreen.screens.first) 的合并：v1 是几何真理但应对 System Settings 拖动中态不健壮，v2 是文档化 API 但偶发偏差时无 fallback。final rule 用两层兜底覆盖两类失败。 -->
<!-- 修订v2: lead 拍板——DisplayFrame.isMain → isCoordinateAnchor 是 preferred rename；如 executor 选小 diff 路径不动 struct 字段，必须在 isMain 上方加注释明确 "this is the AX coordinate anchor (AppKit origin / menu-bar display), NOT NSScreen.main / focused screen"。两条路径都 acceptable，差异是 ergonomics vs diff size。 -->
<!-- 修订v2: lead 拍板（应 Reviewer Multi C-2 + Lead 最终细化）——minimized window policy final: 不写 AX size/position（防止 un-minimize 触发或改动 stored frame）；fullscreen 短路旁加 minimized 短路，log `action skipped windowAction=<x> minimized` 后 return。 -->
<!-- 修订v2: lead 拍板（应 Reviewer Multi C-4）——75d4f49 hygiene final: Lead 倾向 bless（如果 rectangle-integration-research.md 是 M4 立项先导文档，bless 合理），但 bless 必须靠下一次 commit message 显式 acknowledge "M4 implementation commit bundled the prior research doc; explanation: <…>"；否则走 split 路径单加 "research handoff" commit。executor 任选其一，但不能默不作声留着 75d4f49 不解释。 -->
<!-- 修订v3: lead 拍板（v3 final consolidation）——v2 方向对但 ship 前还差 7 点：(1)-(5) reviewer 报告 5 项 Lead 再次确认（已落字，本轮仅补强表述）；(6) context/findings/rollout 残留 "v1 / waiting reviewers" 措辞改为 final report；(7) "What not to change" 把 RuleMatcher 说成 "orthogonal/works correctly" 与 §Fix plan #6a 跨 preset 测试补丁矛盾，重写；额外补 minimized window manual matrix 行（Lead 第 2 点 "加入 manual/test notes" 的落字）。本轮 marker 全部 "修订v3"。 -->
# Window Snap Multi-Monitor Review

## Context

**Repo identity caveat.** The hosting Hive channel is named "Windows App Review R". The repo at `/Users/xavier/AI-projects/dock-tap` is a **macOS** menu-bar app written in Swift (`Package.swift`, AppKit / ApplicationServices / CoreGraphics), not a Windows-OS application. The word "window" in this report always means a macOS UI window (`NSWindow` / `AXUIElement` of role `AXWindow`), never Win32. If the channel name was meant to scope the review to Windows-OS behavior, this review is misaddressed and Lead should redirect; otherwise the macOS focus below is the correct read.

DockTap M4 (`docs/plans/m4-window-snap.md`) shipped six native window-snap actions on the focused window of the frontmost app: `leftHalf`, `rightHalf`, `topHalf`, `bottomHalf`, `maximize`, `center`, all behind a default-off `windowActionsEnabled` setting and bound to `<trigger preset>+arrow/Return/Space`. The execution path is:

- `EventTapController` → `KeyEventDecider` → `RuleMatcher.matchKeyDown(...)` returns `.windowAction(WindowAction, shortcutLabel:)` when the flag is on and the key is in the window-action set.
- `AppDelegate.handleShortcut(_:)` routes `.windowAction` intents to `WindowActor`; `.dockSlot` / `.finder` stay on `AppActivator`.
- `WindowActor.perform(_:)` reads the frontmost app's focused window via AX, picks a display, computes a target rect, writes `kAXSizeAttribute` then `kAXPositionAttribute`.

The review brief from Lead is multi-display correctness, with the existing unit tests and live manual matrix as the verification surfaces.

<!-- 修订v3: lead 拍板——Context 收尾改为 final report 措辞，不再写 "v1 / waiting reviewers"；reviewer 报告已全部回流并折入 -->
This file is the **v3 final review report and fix plan**, now refreshed with post-fix current behavior/status. Both reviewer audits (`dev-reviewer-multi` for implementation, `dev-reviewer-tests` for test coverage) have reported and their findings are folded into the Findings, Fix plan, Test matrix, and Staged fix plan sections below with marker attribution. The Findings remain a historical diagnosis of the pre-fix implementation; the Current behavior and Staged fix plan sections describe the workspace after the executor changes. The in-file `<!-- 修订vN: -->` markers preserve the deliberation history so future readers can trace any specific decision back to its source.

## Current behavior

The implementation surface in scope:

- `Sources/DockTap/WindowAction.swift` — pure enum; `targetRect(in visibleFrame: CGRect)` computes the six rects in AppKit coordinates relative to the input `visibleFrame`. No AX, no AppKit beyond CoreGraphics. Locked center scale = 0.75.
- `Sources/DockTap/DisplayFrame.swift` — value type holding `frame`, `visibleFrame`, `isCoordinateAnchor`, `identifier`, `scaleFactor`. Plain CoreGraphics. `isCoordinateAnchor` means the AX/AppKit coordinate anchor, not `NSScreen.main`.
- `Sources/DockTap/ScreenCoordinateConverter.swift` — pure helper:
  - `axRectToAppKit(_:in:)`, `appKitPointToAX(_:in:)`, `axPointToAppKit(_:in:)` all anchor on `displays.first(where: \.isCoordinateAnchor)?.frame.maxY` (`anchorTopY`).
  - `selectDisplay(for axRect:in:)` accepts the current AX rect, converts it to AppKit internally, picks max-frame-intersection display, tie-breaks by the AppKit center, and falls back to `displays.first(where: \.isCoordinateAnchor)`.
- `Sources/DockTap/WindowActor.swift` — AX side:
  - Reads frontmost app, focused window, `AXFullScreen`, `kAXMinimizedAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`.
  - Builds screen snapshots from `NSScreen.screens`, then maps them through the pure `DisplayFrameMapper`. The mapper marks the screen at `frame.origin == .zero` as the coordinate anchor; if none exists, it falls back to the first snapshot and `WindowActor` logs a warning. `NSScreen.main` is not used for coordinate anchoring.
  - Calls `ScreenCoordinateConverter.selectDisplay(for: currentAXRect, in: displays)`, computes `targetAppKitRect = action.targetRect(in: display.visibleFrame)`, converts target top-left back to AX, writes size then position.
  - Result logging names the chosen display and uses `action applied` only when both AX writes succeed, `action partial` when one succeeds, and `action failed` when both fail. Fullscreen and minimized windows are skipped before writes.
- Wiring: `AppDelegate.windowActionsEnabled`, `SettingsStore.windowActionsEnabled` (default `false`), `EventTapController.updateWindowActionsEnabled(_:)`, `MenuContentModel.windowSnapToggleIsOn` / `windowSnapRows`.
- Tests: `WindowActionTests` (rect math including odd widths), `ScreenCoordinateConverterTests` (coordinate translation + point round-trips + display picking on synthetic `DisplayFrame` fixtures), `DisplayFrameMapperTests` (pure runtime display mapping seam), `RuleMatcherWindowActionTests` (matcher branching across trigger presets), `MenuContentModelTests` (menu shape), `SettingsStoreTests` (round-trip).

Observable behavior on a single display remains unchanged: arrow / Return / Space snap the focused window to halves / maximize / center of the current display's visible frame, with the dock and menu bar excluded (`visibleFrame`). Multi-display conversion now uses the coordinate anchor independently from the selected display, so vertical, negative-X, and offset layouts are covered by tests.

## Findings

<!-- 修订v3: lead 拍板——Findings 开头摘掉 "pre-reviewer findings" 措辞，改为 final 全量整合的口径；reviewer 编号已就地折入 -->
Severity tags match this team's reviewer convention (`B-N` blocker, `C-N` concern, `N-N` nit). In v3 final, all `B-N` / `C-N` / `N-N` items below represent the integrated diagnosis after both reviewer reports landed; each item's marker line attributes it to dev-planner (initial audit), dev-reviewer-multi (implementation audit), dev-reviewer-tests (test audit), or Lead (final ruling), as applicable. The Staged fix plan downstream sequences them for the executor.

<!-- 修订v2: lead 拍板——精确化 file:line（WindowActor.swift:83-90 + ScreenCoordinateConverter.swift:56-62），并把触发条件从 "different height" 收紧为 "vertical layout 必触发 / horizontal-same-height 偶然不触发"；横屏等高这一巧合就是 reviewer 复现不到的原因 -->
### B-1 — `WindowActor` misuses `NSScreen.main` as the AX origin display

**Symptom.** When the focused window is on a non-anchor display in a multi-display setup, the snapped position is off vertically by `(NSScreen.main.frame.maxY - anchorDisplay.frame.maxY)`. Three layout classes:

- **Vertical layout (secondary above or below primary) — always triggers.** Secondary's `frame.maxY` differs from primary's `frame.maxY` by construction (different y origin), so `mainTopY` is always wrong when focus is on the secondary. This is the canonical break case Lead identified.
- **Horizontal layout with different heights** (e.g., MBP 16" 1080 + external 1440 next to it) — triggers whenever focus is on the shorter/taller display.
- **Horizontal layout with same heights, both at AppKit y=0** — accidentally OK, because `secondary.frame.maxY == primary.frame.maxY` makes the wrong-anchor coincide with the correct one. This is the most common dev/test setup and is exactly why the bug shipped past M4's reviewer pass.

**Where.** `Sources/DockTap/WindowActor.swift:83-90` (`displayFrames()`):

```
isMain: screen == mainScreen   // mainScreen = NSScreen.main
```

…feeds `Sources/DockTap/ScreenCoordinateConverter.swift:56-62` (`mainTopY`):

```
guard let mainDisplay = displays.first(where: \.isMain) else { return nil }
return mainDisplay.frame.maxY
```

**Why this is wrong.** `NSScreen.main` returns "the screen containing the window with the keyboard focus" ([Apple docs](https://developer.apple.com/documentation/appkit/nsscreen/main)), not the menu-bar / coordinate-anchor display. The AX (Accessibility / Quartz `CGWindowList`) coordinate system uses a fixed origin: **the top-left of the menu-bar display**, exposed by AppKit as `NSScreen.screens.first` and by Core Graphics as `CGMainDisplayID()`. The converter's `mainTopY` is the AppKit-space y of "AX y = 0," which is always `anchorDisplay.frame.maxY`, not `focusedScreen.frame.maxY`.

When focus moves to a screen whose `frame.maxY` differs from the anchor's (any vertical layout, plus horizontal layouts with mixed heights), both directions of the translation (AX→AppKit and AppKit→AX) shift by the delta, and the snap lands at the wrong Y on that screen.

**Concrete reproducer (mental — vertical layout, Lead's canonical case).** Primary `(0, 0, 1920, 1080)` at AppKit origin, secondary `(0, 1080, 1440, 900)` directly above primary. User has Notes focused on the secondary screen.

- True `mainTopY` (anchor = primary) = `1080`.
- Implementation `mainTopY` (NSScreen.main = secondary) = `1080 + 900 = 1980`.
- Snap left-half on secondary: target AppKit rect `(0, 1080, 720, 875)` (assuming separate-spaces menu bar on secondary). AppKit top-left `(0, 1955)`.
- Correct AX y = `1080 - 1955 = -875`. AX top-left `(0, -875)` — negative because secondary is above primary in AX coords. Correct.
- Implementation AX y = `1980 - 1955 = 25`. AX top-left `(0, 25)` — lands near the **top of the primary screen**, ~1080pt below where the user expects.
- Net: snap on the upper screen warps the window down to the lower screen.

**Second reproducer (horizontal mixed-height — my original B-1 framing).** Primary `(0, 0, 1920, 1080)`, secondary `(1920, 0, 1440, 900)` to the right and shorter. User has Notes focused on the secondary.

- True `mainTopY` (anchor = primary) = 1080.
- Implementation `mainTopY` (NSScreen.main = secondary) = 900.
- Target left-half rect (AppKit, on secondary `visibleFrame` ~ `(1920, 0, 1440, 875)`): `(1920, 0, 720, 875)`.
- AppKit top-left for write: `(1920, 875)`.
- Correct AX y = `1080 - 875 = 205`. AX top-left = `(1920, 205)`.
- Implementation AX y = `900 - 875 = 25`. AX top-left = `(1920, 25)`.
- Net: window snaps **180pt higher on the secondary screen than intended** — pushed up and off the screen by ~180pt, or in the menu-bar region depending on geometry.

The same class of mis-anchor also affects the `selectDisplay` intersection check, because `selectDisplay` internally converts the input AX rect via the same `mainTopY` and then intersects with each `display.frame` (which is AppKit-space). With the wrong anchor, intersections are computed in a shifted AppKit frame and may pick the wrong display when the window straddles a boundary, or miss every display and fall back to the `isMain` entry (which is also the wrong screen).

**Severity.** Blocker for multi-display correctness. Single-display users and horizontal-same-height multi-display users see no symptom; everyone with a vertical arrangement or mixed-height horizontal arrangement is affected on any non-anchor screen.

<!-- 修订v4: 应 Reviewer Multi B-1——dev-reviewer-multi 独立 audit 后达成与 dev-planner v1 + Lead v2 完全一致的结论，三方共识 -->
**Cross-reviewer confirmation.** `dev-reviewer-multi` independently audited the same surface and reached the same conclusion: `NSScreen.main` (key-window screen) is not a valid coordinate anchor; the menu-bar / origin display must be used instead. Three-way consensus (dev-planner v1, Lead v2, dev-reviewer-multi v4) on the diagnosis and on the fix direction (split anchor vs. selected, `NSScreen.screens.first` with `CGMainDisplayID()` cross-check, rename `isMain` → `isCoordinateAnchor`). No further architecture decisions outstanding for this blocker.

### B-2 — `isMain` collapses to "none" when `NSScreen.main` is `nil`

**Symptom.** Every snap attempt fails with `action failed windowAction=<x> no selectable display`. No window movement, no AX writes.

**Where.** Same site as B-1: `Sources/DockTap/WindowActor.swift:83-94`. `NSScreen.main` documents that it can return `nil` (e.g., "if the application doesn't have a window or the window doesn't have a screen"). DockTap is `.accessory` (`AppDelegate.applicationDidFinishLaunching` sets `NSApp.setActivationPolicy(.accessory)`) and has no foreground window of its own; depending on macOS version and the user-session state, `NSScreen.main` can be `nil` at the moment the snap fires (e.g., immediately after lock-screen unlock, after the frontmost app quits, during a Space switch).

With `mainScreen == nil`, the `displayFrames()` map sets `isMain` to `false` on every entry. The converter then returns `nil` from `mainTopY(in:)`, and `selectDisplay` returns `nil`, and `WindowActor` no-ops.

**Severity.** Blocker. The fix for B-1 (anchor on origin-zero screen) also closes B-2, because `NSScreen.screens.first(where: { $0.frame.origin == .zero })` is well-defined whenever any displays are connected; macOS guarantees the primary display sits at AppKit origin `.zero`.

### B-3 — Plan documentation contradicts its own intent and matches the buggy implementation

**Where.** `docs/plans/m4-window-snap.md:107` says:

> `isMain: Bool` — whether this display is the primary; exactly one entry in any valid `[DisplayFrame]` has `isMain == true` (or zero entries if the caller had no main display).

And `docs/plans/m4-window-snap.md:197`:

> Map `NSScreen.screens` to `[DisplayFrame]`, marking the entry equal to `NSScreen.main` as `isMain: true`.

These are inconsistent: "primary" (`frame.origin == .zero`) and "the entry equal to `NSScreen.main`" (focused-window screen) are not the same display in general. The implementation followed the latter, the converter assumes the former. Fix needs to update both.

**Severity.** Document-level blocker — leaving this inconsistency in the source-of-truth plan means a future regression is one revert away.

### C-1 — `selectDisplay` does not use `visibleFrame`, but `WindowActor` then snaps inside `visibleFrame`

**Where.** `Sources/DockTap/ScreenCoordinateConverter.swift:38-53`. `selectDisplay` picks the display by `display.frame` intersection (full frame, including menu bar / dock zones). `WindowActor` then computes the target rect against `display.visibleFrame`.

For a window whose center lies inside a screen's dock / menu-bar strip (a small zone but reachable, especially with dock auto-hide off + a narrow window), the chosen display is correct, the snap is fine. The asymmetry is benign in the common case. But there is a subtler case: a tall window straddling two side-by-side displays of different aspect ratios where the "dock strip" of one screen is exactly the slice that tips the intersection area. Picking by `visibleFrame` would be more consistent with the user's perception of "which screen is this window on", but picking by `frame` is what Rectangle uses and is arguably more permissive.

**Severity.** Concern, not blocker. Worth flagging as a follow-up consistency tweak; not on the multi-monitor fix critical path.

### C-2 — No log surfaces *which* display was picked

**Where.** `Sources/DockTap/WindowActor.swift:78-80` log line includes `currentAppKit`, `rectAppKit`, `originAX`, AX result codes — but not the chosen display's `identifier`, `frame`, or `visibleFrame`. For multi-monitor bug triage this is the single most useful piece of context to have in the log. Adding it costs one extra field on the log line and zero behavior risk.

**Severity.** Concern; quality-of-life. Worth bundling into the same change that fixes B-1.

### C-3 — `currentAppKitRect` is computed but only used in the log

**Where.** `Sources/DockTap/WindowActor.swift:60-79`. `currentAppKitRect` is built solely for the log message. It is fine as-is, but the surrounding flow recomputes the same axRect→appKit translation inside `selectDisplay`. Two minor refactor options if we touch this file for B-1:

1. Let `selectDisplay` return `(DisplayFrame, appKitRect)` so the caller doesn't recompute.
2. Drop `currentAppKitRect` and log the chosen display + raw AX rect instead — the AppKit rect is derivable but rarely the thing you actually want in a triage log.

**Severity.** Concern; bundle if convenient.

### C-4 — `selectDisplay` tie-breaker uses `.frame.contains(center)`, missing displays with negative-origin frames

**Where.** `Sources/DockTap/ScreenCoordinateConverter.swift:48-51`. `CGRect.contains(_ point:)` is correct for any rect, including ones with negative origin (a secondary display above/left of primary has negative AppKit y or x). Verified mentally — no defect here, but the existing `ScreenCoordinateConverterTests.testSelectDisplayFallsBackToCenterOnTieOrZeroIntersection` only exercises the center-fallback on the *right-of-primary* fixture, not the above-primary or below-primary fixtures. Worth extending; see test matrix.

**Severity.** Concern at the test-coverage layer; converter logic itself is OK.

### C-5 — `WindowActor` does not log when `selectDisplay` falls back to `isMain`

**Where.** Same surface as C-2. When the window is off-screen (e.g., Stage Manager strip animations, a window that was on a now-disconnected display), `selectDisplay` returns the `isMain` display silently. After the B-1 fix, `isMain` will be the primary, so the snap will land on primary. That is a *behavior change for off-screen windows* that the user should be able to see in the log.

**Severity.** Concern; one extra log line.

### N-1 — `displayFrames()` is private; not exercised by unit tests

The current `ScreenCoordinateConverterTests` build `[DisplayFrame]` directly, which keeps the converter pure and testable but leaves the WindowActor→DisplayFrame mapping (the buggy seam) outside any test net. After fix, that mapping should either be a pure helper on `DisplayFrame` (e.g., a static factory `DisplayFrame.fromScreens(_:)` that takes `NSScreen.screens` and the primary anchor) or be left in WindowActor with a clear comment naming the invariant.

### N-2 — Half-pixel boundaries on odd-width displays

`leftHalf.width = visibleFrame.width / 2`. For odd-point widths (rare on retina but common on some external panels), the AppKit math produces `.5` boundaries and AX rounds. Minor visual seam between left and right halves. Not a multi-monitor bug; calling out only because the test matrix should include at least one odd-width fixture so future regressions are caught.

<!-- 修订v4: 应 Reviewer Multi C-2——原 N-3 升级为 C-7，minimized 窗口行为留白足以让 user 误以为 snap 静默失败 -->
### N-3 — *(elevated to C-7 in v4; see below)*

### N-4 — `WindowActor.perform(_:)` switches off the intent shape, not the case

```
guard case .windowAction(let action, shortcutLabel: _) = intent else { return }
```

Pattern is fine. If another `.windowAction`-shaped case is added later, the guard will need to grow into a switch.

<!-- 修订v4: 应 Reviewer Multi C-1——action applied 是无条件 log，AX 失败时与 axResult 错误码并存，运维误导面大 -->
<!-- 修订v3: lead 拍板（v3 final re-confirmation）——Lead 第 1 点再次点名，确认 fix shape 不变：双 success → applied / 单边失败 → partial / 双失败 → failed；payload 不变只换 verb -->
### C-6 — `action applied` log is unconditional regardless of AX write success

**Where.** `Sources/DockTap/WindowActor.swift:76-80`:

```
let axSizeResult = setSize(targetAppKitRect.size, on: window)
let axPositionResult = setPosition(targetAXOrigin, on: window)
logStore.append(
    "action applied windowAction=\(action.rawValue) ... axSizeResult=\(axSizeResult.rawValue) axPositionResult=\(axPositionResult.rawValue)"
)
```

The verb `applied` fires unconditionally — even when `axSizeResult` or `axPositionResult` is a non-success code (e.g., `.cannotComplete = -25204`, `.apiDisabled = -25211`, `.invalidUIElement = -25202`). A user reading the log sees `action applied ... axSizeResult=-25204` and cannot tell at a glance whether the snap succeeded. For multi-monitor triage in particular, where the user is asking "did the snap land?" and reading the log, the verb is the first thing the eye catches.

**Fix.** Branch on the two AX codes:

- Both `.success` → `action applied ...` (current behavior, but now correctly named).
- One `.success` + one error → `action partial ...` (size set but position failed, or vice versa — a real state, e.g., when an Electron app accepts size but ignores position).
- Both error → `action failed ...`.

The diagnostic payload (`currentAppKit`, `rectAppKit`, `originAX`, both AX codes) stays in every branch — only the verb changes. No behavior change beyond log copy. Tester-facing improvement; cheap.

**Severity.** Concern. Cosmetic but the log is the primary tool for multi-monitor bug triage; mis-labeling failures as success will mask future regressions in the AX layer.

<!-- 修订v4: 应 Reviewer Multi C-2——原 N-3 升级；plan 现在欠 "minimized window AX write 怎么处理" 的明确合同 -->
<!-- 修订v3: lead 拍板（v3 final re-confirmation）——Lead 第 2 点再次点名 + 新增 manual/test notes 落字要求；manual matrix 已加 case #15/#16；fix 形状不变 -->
### C-7 — Minimized window behavior is undefined (was N-3)

**Where.** `Sources/DockTap/WindowActor.swift:40-43`:

```
if readBoolAttribute(Self.fullScreenAttribute, from: window).value == true {
    logStore.append("action skipped windowAction=\(action.rawValue) fullscreen")
    return
}
```

Fullscreen is checked and skipped. `kAXMinimizedAttribute` is not. The actual behavior depends on the app: many apps accept the AX writes silently and the window appears at the snapped rect when un-minimized; some apps refuse; some return `.success` but ignore the values. Either outcome is surprising for the user, who expects "I pressed snap, the window is in the Dock, nothing visible happened" to either be a no-op or to un-minimize the window — the current code does neither deterministically.

**Fix.** Read `kAXMinimizedAttribute` after the fullscreen check; if true, log `action skipped windowAction=<rawValue> minimized` and return **before** any `setSize` / `setPosition` write. Do not attempt to un-minimize (consistent with the M4 invariant: this code does not activate or transform apps, only re-rects already-visible windows). Same pattern as the existing fullscreen short-circuit.

<!-- 修订v2: lead 拍板——final minimized policy 锁定：必须在 AX write 前 short-circuit，不能尝试 set 后再观察；否则有 app 会把 set 当成 un-minimize 信号或更新 stored frame，破坏 "minimized window stays minimized + stored frame intact" 的契约 -->
**Lead final ruling on the contract:** "skip minimized, log `minimized`, do not write." The reason the write must not happen even speculatively: some apps (notably Electron-class) interpret a position/size write on a minimized window as "un-minimize and apply"; others silently mutate the stored geometry that the window will restore to on the user's next click in the Dock. Either is user-visible damage. The pre-write short-circuit is the only safe shape.

**Severity.** Concern. Not multi-monitor specific, but it ships in the same hotpath as the B-1 fix and is a one-attribute-read addition; bundling avoids touching `WindowActor.swift` twice.

<!-- 修订v4: 应 Reviewer Multi C-4——git log 验证：commit 75d4f49 同时改了 m4-window-snap.md 和 rectangle-integration-research.md，后者是 pre-M4 research doc，不在 M4 zone -->
<!-- 修订v3: lead 拍板（v3 final re-confirmation）——Lead 第 5 点再次点名；bless-with-explanation 是首选，silent 不行；split 是 fallback；executor 任选其一 -->
### C-8 — M4 implementation commit bundles `rectangle-integration-research.md` (out of zone)

**Where.** `git log --follow docs/plans/rectangle-integration-research.md` returns a single commit: `75d4f49 Add window snap actions`. The same commit also touched `docs/plans/m4-window-snap.md`. Per M4's own §Execution zones, the research doc was pre-M4 planning material; it should have been a separate commit (or already committed before M4 started). The bundled commit makes the M4 changelog noisier than it needs to be and conflates "decided to build" with "built."

**Fix.** Repo-hygiene-only; no source impact. Two acceptable resolutions:

a. **Bless retroactively.** Add a one-line note in the next commit message acknowledging the bundle; no rewrite. Lead's lean.
b. **Split.** If the team prefers a clean history, the executor for the B-1 fix can include a follow-up that adds a separate "Document M4 → R1 research handoff" commit that re-attributes the research doc. Not worth a rebase of `75d4f49` itself (already shipped, no value in rewriting public history).

<!-- 修订v2: lead 拍板——bless 路径附加硬约束：commit message 必须解释，不能默不作声留着 -->
**Lead final ruling.** Lead leans (a) bless, **with a hard constraint**: the bless requires the next M4-zone commit message to explicitly say something like "M4 implementation commit `75d4f49` bundled the prior `rectangle-integration-research.md` planning doc; this is the acknowledgement that the research predates M4 and was appropriately co-located, not lost." A silent bless (i.e., never mentioning it again) is **not** acceptable — that turns the bundled commit into an undocumented archaeology trap for the next contributor reading the history. If the executor balks at writing that sentence, option (b) split is the alternative. Either way, no silent acceptance.

**Severity.** Concern at the repo-hygiene layer; does not affect runtime behavior or the B-1 fix.

## Root causes

<!-- 修订v2: lead 拍板——根因表述加入 "anchor display vs current/selected display 应当是两个独立概念" 这条结构性观察；这是 v2 fix plan 的架构出发点 -->
The dominant cause behind B-1, B-2, B-3 is a single conceptual conflation: **"the main display" in macOS APIs has two distinct meanings, and the M4 implementation collapsed them into one `isMain` field.**

- AppKit's `NSScreen.main` = the screen containing the keyboard-focused window. Used by AppKit UI code to decide where to draw, where modal sheets attach. Changes as the user moves windows; can be `nil`.
- AX / Quartz coordinate origin = the **menu-bar / coordinate-anchor** display. Stable across focus changes. Exposed by AppKit as `NSScreen.screens.first` (Apple documents `screens[0]` as the menu-bar display) and by Core Graphics as `CGMainDisplayID()`. Both are well-defined whenever any display is connected.

These are **two different concepts** that the code (and the M4 plan text) treated as one. `ScreenCoordinateConverter` consumes the anchor concept; `WindowActor.displayFrames()` produces the focused-screen concept. Single-display and horizontal-same-height setups have the two collapse to the same screen by coincidence, hiding the defect in most reviewer environments.

The structural fix (carried into the Fix plan below) is to **separate the two concepts at the type layer**: the anchor display (which feeds the AX↔AppKit translation) and the current / selected display (which feeds `targetRect(in:)`) are independent responsibilities. They happen to be the same DisplayFrame value in some cases, but the converter's contract should make clear which one it needs.

C-1, C-2, C-3, C-5 are local quality / observability issues uncovered while tracing the B-class bug. They are independent of the root cause but worth bundling because they touch the same surface.

## Fix plan

### Files to change

<!-- 修订v2: lead 拍板——anchor 取法改为 NSScreen.screens.first（必要时 CGMainDisplayID 兜底）而非 frame.origin==.zero；DisplayFrame.isMain 改名 isCoordinateAnchor；anchor 与 current/selected display 在类型层面拆开；测试矩阵补 "selected ≠ anchor" -->

1. **`Sources/DockTap/WindowActor.swift`**
   <!-- 修订v2: lead 拍板——final anchor rule 取代上面 v2 inflight 段；primary 路径回到 frame.origin == .zero（几何真理），NSScreen.screens.first 作 fallback 并 log warning -->
   - Rewrite `displayFrames()` to mark the anchor based on the **menu-bar / coordinate-anchor** display, not the focused-window screen. **Final anchor-resolution rule (v2 final):**
     - Primary path: `displays.first(where: { $0.frame.origin == .zero })`. This is the geometric definition of "the AppKit origin display, which is also the menu-bar display in steady state" — directly aligned with what `ScreenCoordinateConverter` consumes via `anchorTopY`.
     - Fallback path: `NSScreen.screens.first`. Apple documents `screens[0]` as the menu-bar display; this catches the rare transition states (briefly mid-drag in System Settings → Displays) where no screen has `frame.origin == .zero` for a frame or two. **When the fallback fires, log `anchor fallback: no screen at frame.origin == .zero; using screens[0]` so the rarity becomes visible.**
     - Sanity cross-check (optional): if `screens[0]` does not match `CGMainDisplayID()` via `deviceDescription[.screenNumber]`, log a warning. Do not treat as fatal — Core Graphics and AppKit's notion of "the main display" can disagree transiently during display reconfiguration.
     - **Do not** use `NSScreen.main`. Apple docs explicitly define it as the keyboard-focused screen, not the menu-bar / coordinate-anchor display. This is the M4 misuse the entire v2 final consolidation closes.
     - If neither primary nor fallback resolves (zero connected screens — only happens during display teardown), return an empty array; the caller logs `no anchor display` and no-ops.
   - Build the `[DisplayFrame]` array from `NSScreen.screens` in order; set `isCoordinateAnchor = true` on the one entry that matches the anchor resolved above, `false` on the rest. Behavior is deterministic and depends only on display topology, not focus state.
   - Add a log line after `selectDisplay` returns, naming the chosen display (`identifier`, `frame`, `visibleFrame`) and whether the choice came from intersection, center-fallback, or anchor-fallback. If the converter exposes which branch fired, prefer that; otherwise the log line can simply name the chosen display by `identifier` + frame and let triage infer.
   - Add a distinct log line for the B-2 case ("no anchor display in NSScreen.screens") versus the B-1-symptom case ("no selectable display").
   - Keep the size-then-position write order (same-display snap — no regression in v1 scope).

2. **`Sources/DockTap/ScreenCoordinateConverter.swift`**
   - Rename `mainTopY` to `anchorTopY` (or equivalent). The lookup changes from `displays.first(where: \.isMain)` to `displays.first(where: \.isCoordinateAnchor)`. **Private-helper rename + DisplayFrame field rename; public function signatures (`axRectToAppKit`, `appKitPointToAX`, `axPointToAppKit`, `selectDisplay`) stay identical.**
   - `selectDisplay`'s anchor-fallback branch (currently `displays.first(where: \.isMain)`) becomes `displays.first(where: \.isCoordinateAnchor)`. Same behavior, clearer name.
   - Optionally extend `selectDisplay` to return a tagged enum (`.intersection(DisplayFrame)`, `.containingCenter(DisplayFrame)`, `.fallbackToAnchor(DisplayFrame)`, `.none`) so `WindowActor` can log which branch chose the display. Trade-off: small API churn. Alternative: leave `selectDisplay` as-is and have `WindowActor` re-derive the branch (more duplication). Planner's lean: tagged enum, because it removes a class of "why did it pick that display?" triage questions and the API surface is internal to the module.
   - **Concept separation note for the executor:** the converter's API takes `[DisplayFrame]` and internally needs exactly one entry with `isCoordinateAnchor: true` to do AX↔AppKit translation. `selectDisplay` returns the **current / selected display** for the window — a different concept. These two roles can be the same `DisplayFrame` value (single-display setups, single-monitor focus on the anchor) or different values (focus on a non-anchor screen). The rename and the field name make this distinction unmissable; the converter does not collapse them.

3. **`Sources/DockTap/DisplayFrame.swift`**
   <!-- 修订v2: lead 拍板——rename 是 preferred path；保留 isMain + 注释也 acceptable，executor 自决；doc comment 必须显式区分 AX anchor vs NSScreen.main -->
   - **Preferred path: rename field `isMain` → `isCoordinateAnchor`.** Update the doc comment to: "True iff this entry is the AppKit-origin / menu-bar / coordinate-anchor display (the screen at AppKit `frame.origin == .zero` in steady state, falling back to `NSScreen.screens.first` during display rearrangements). Defines the AX coordinate origin via `mainTopY = anchor.frame.maxY`. **NOT** the same as `NSScreen.main`, which is the keyboard-focused screen and must not be used for AX↔AppKit translation. Distinct from `selectDisplay`'s return value, which is the current / selected display for a window." All construction sites in `Sources/` and `Tests/` get the same rename. This is the option that lets future readers grep one name and see the contract.
   - **Acceptable fallback path: keep `isMain` and add the same doc comment verbatim.** If the executor judges the rename's diff size (12+ call sites across source and tests) outweighs the ergonomic win, leaving the field name as `isMain` is OK **only if** the doc comment above lands intact directly on the field. The contract is what matters; the name is the convenience.
   - No new fields. The struct's other fields (`frame`, `visibleFrame`, `identifier`, `scaleFactor`) stay as-is.

4. **`docs/plans/m4-window-snap.md`**
   - Update the `DisplayFrame.isMain` description (currently line 107) to use the new name `isCoordinateAnchor` and the new resolution rule (`NSScreen.screens.first`, not `NSScreen.main` and not `frame.origin == .zero`).
   - Update the `WindowActor` step that says "marking the entry equal to `NSScreen.main` as `isMain: true`" (currently around line 197) to "marking the entry equal to `NSScreen.screens.first` as `isCoordinateAnchor: true`."
   - Update every other reference to `isMain` in the file (search and replace, but each site reviewed by hand). Add a `<!-- 修订vN: -->` marker at each edit per this file's revision-marker convention. This closes B-3.
   <!-- 修订v3: 应 Reviewer Tests N-1——m4 plan §AX implementation notes step 8 写 "selectDisplay(for: <converted AppKit rect>...)" 是错的，函数签名收 AX rect、内部自己转换；不修会误导 executor 把转换提前到调用方 -->
   <!-- 修订v4: 应 Reviewer Multi N-1——与 v3 Reviewer Tests N-1 同一处措辞 bug，两份 reviewer 同时点名，合并落字 -->
   <!-- 修订v3: lead 拍板（v3 final re-confirmation）——Lead 第 4 点再次点名；wording fix 是 ship 前 plan-doc 必修项，不可推迟 -->
   - **Fix the `selectDisplay` argument-type wording in §AX implementation notes step 8 (currently around line 199).** That step currently reads "Pick the target display with `ScreenCoordinateConverter.selectDisplay(for: <converted AppKit rect>, in: <displays>)`." That is wrong: `selectDisplay`'s signature is `selectDisplay(for axRect: CGRect, in: [DisplayFrame])` — it accepts the **AX-coordinate rect** and performs the AX→AppKit conversion internally (see `Sources/DockTap/ScreenCoordinateConverter.swift:33-54`). The step should read "Pick the target display with `ScreenCoordinateConverter.selectDisplay(for: <current AX rect>, in: <displays>)`," matching both the function signature and the production call site at `Sources/DockTap/WindowActor.swift:63`. Add a `<!-- 修订vN: -->` marker on the corrected line. Cross-reviewer + Lead confirmed (Reviewer Tests N-1 + Reviewer Multi N-1 + Lead v3 final).

5. **`Tests/DockTapTests/ScreenCoordinateConverterTests.swift`**
   - Rename all `isMain:` keyword arguments and helper-method `isMain` parameters to `isCoordinateAnchor:` in line with the field rename.
   - Add fixtures that have the anchor NOT as the first element of the `[DisplayFrame]` array, to lock that the converter relies on the field, not array order.
   - **Add the "vertical layout" fixture from B-1's canonical reproducer**: anchor `(0, 0, 1920, 1080)` + secondary directly above at `(0, 1080, 1440, 900)`. Assert: an AppKit rect on the secondary round-trips to an AX rect with **negative** y (e.g., `(0, -875, 720, 875)`), and `selectDisplay` returns the secondary `DisplayFrame` for a rect inside its bounds.
   - **Add the "selected ≠ anchor" fixture explicitly**: build a multi-display fixture where `selectDisplay` returns the non-anchor entry, then convert the resulting rect's origin both directions. Assert correctness in both. This is the core regression net for the conceptual separation in v2.
   - Keep the mixed-height horizontal fixture from v1 (primary 1080 + secondary 900 right-of) — it remains a valid second-class trigger.
   <!-- 修订v3: 应 Reviewer Tests C-1——补 left-of-anchor 负 X 与 side+vertical-offset fixture，覆盖 macOS 显示器排布的剩余两类常见组合 -->
   <!-- 修订v4: 应 Reviewer Multi C-3——negative-X 部分与 v3 Reviewer Tests C-1 完全重叠；以下条目即两份 reviewer 报告的合并落字 -->
   - **Add the "left-of-anchor" fixture (negative AppKit X).** Anchor `(0, 0, 1920, 1080)`, secondary `(-1440, 0, 1440, 900)` to the left. Assert: an AppKit rect on the secondary (e.g., `(-1000, 100, 600, 800)`) round-trips to AX with the same negative X, and `selectDisplay` returns the secondary. Locks the symmetry of the converter — it must not assume non-negative AppKit X.
   - **Add the "side display with vertical offset" fixture.** Anchor `(0, 0, 1920, 1080)`, secondary `(1920, 200, 1440, 880)` — to the right and offset down by 200pt (common when monitors of different sizes are bottom-aligned by the user). Assert: an AppKit rect on the secondary round-trips correctly, AX y reflects both the anchor-relative flip and the secondary's non-zero Y, and `selectDisplay` picks the secondary for a rect inside its bounds.
   - Add a fixture where no entry has `isCoordinateAnchor: true` and assert `axRectToAppKit`, `appKitPointToAX`, `axPointToAppKit`, and `selectDisplay` all return `nil` (locks the B-2 contract).

6. **`Tests/DockTapTests/WindowActionTests.swift`**
   - Add an odd-width visible frame fixture (e.g., `(0, 0, 1495, 877)`) and assert `leftHalf.maxX == rightHalf.minX` exactly (N-2). No multi-monitor coupling.

<!-- 修订v3: 应 Reviewer Tests C-3——RuleMatcherWindowActionTests 只覆盖 leftOption；arrow/Return/Space 的 shortcut label 在每个 TriggerModifierPreset 下都该有断言，防止 preset 切换时 label 拼接 silently 漂移 -->
<!-- 修订v3: lead 拍板（v3 final re-confirmation）——Lead 第 3 / 7 点交叉点名：matcher production 不动但 matcher tests 必须补；该位点是 ship 前测试 gap 的核心条目 -->
6a. **`Tests/DockTapTests/RuleMatcherWindowActionTests.swift`** *(extend existing file)*
   - The existing tests only exercise the `.leftOption` trigger preset (`triggerModifier: .leftOption` is hard-coded in the test helper `decide(...)` at line ~75). All six window-action keys' shortcut labels go through `triggerModifier.shortcutLabel(forKeyLabel:)`, which produces the user-visible string (e.g., `"Left Option+←"`) that ends up in logs and menu rows. A preset rename or a `TriggerModifierPreset.shortcutLabel(forKeyLabel:)` regression would silently change labels with no test coverage.
   - Parameterize the existing test to iterate over **every** `TriggerModifierPreset` case (`leftOption`, `rightOption`, `leftCommand`, `rightCommand`, `leftControl`, `rightControl`). For each preset, assert the six expected label strings (e.g., `"Right Command+←"`, `"Right Command+→"`, ..., `"Right Command+Space"`).
   - Also add a guard: with `windowActionsEnabled: false`, the same matrix produces `nil` for every (preset, key) pair — locks the cross-preset off-state.

7. **`Tests/DockTapTests/WindowActorDisplaySelectionTests.swift`** *(new, optional)*
   - Pure unit tests on the new `displayFrames()` helper. Two seam options for the executor to pick from:
     a. Extract a pure function `DisplayFrame.from(screens:anchorResolver:)` that takes a `[NSScreen]`-shaped input (or a protocol seam) and produces `[DisplayFrame]`. Test that function directly.
     b. Accept the helper stays private to `WindowActor` and is exercised only by the manual matrix.
   - Planner's lean: option (a), because the anchor-resolution rule is exactly the place a regression would silently land. A single test "given a list of three screens where the second is `NSScreen.screens.first`-equivalent, the second is marked anchor" prevents the M4-class bug from reappearing.
   <!-- 修订v4: 应 Reviewer Multi C-3——补 "unstable anchor" 测试位点，验证 displayFrames 没缓存、每次现读 -->
   - **Add the "unstable anchor across calls" test (Reviewer Multi C-3's residual concern).** With seam (a), feed two different `[NSScreen]`-shaped inputs in sequence (e.g., first input has `screens[0]` = display A; second input has `screens[0]` = display B because the user dragged the menu bar). Assert the helper's `isCoordinateAnchor` flag tracks the input on each call — i.e., the helper is **stateless** and does not memoize the anchor across invocations. This is the unit-test complement to manual matrix case 11 (drag menu bar mid-session). If the executor picks seam (b), this case stays manual-only and the manual matrix case 11 carries the regression net alone.

8. **Optional: `Sources/DockTap/AppDelegate.swift`** — no required change for the B-class fix. If `WindowActor` grows a structured display-selection log, the existing log window surfaces it automatically.

### What not to change in this fix

<!-- 修订v3: lead 拍板——RuleMatcher/decider 行 production 不动 ✓，但 matcher TESTS 要补跨 preset 覆盖（§Fix plan #6a），不能再写成 "orthogonal/works correctly" 把 reader 误导到 "测试也不用动" -->
- `Sources/DockTap/WindowAction.swift` — `targetRect(in:)` is correct; do not touch.
- **`Sources/DockTap/RuleMatcher.swift`, `KeyEventDecider.swift`, `EventTapController.swift` — production matcher / decider / tap layer needs no source change** (the multi-monitor bug lives entirely in `WindowActor` + `ScreenCoordinateConverter`; the matcher correctly returns `.windowAction(...)` regardless of display topology). **But the matcher tests need extension per §Fix plan #6a** — current `RuleMatcherWindowActionTests` only exercises `.leftOption` preset, leaving the cross-preset shortcut-label pipeline unguarded against a `TriggerModifierPreset.shortcutLabel(forKeyLabel:)` regression. The production code stays still; the test file does not.
- `Sources/DockTap/SettingsStore.swift`, `MenuContentModel.swift`, `AppDelegate.swift` — UI and settings wiring is unaffected.
- Cross-display window movement, `next-display` / `previous-display` verbs — explicitly out of scope per M4 plan; this review does not propose adding them.

### Trade-offs the executor should know about

<!-- 修订v2: lead 拍板——anchor 取法首选 NSScreen.screens.first（替换 v1 提出的 frame.origin==.zero 方案），更贴合 Apple 文档与 CGMainDisplayID 语义；保留 origin==.zero 仅作健康检查 -->
<!-- 修订v2: lead 拍板（v2 final consolidation）——再次反转：final rule 是 frame.origin==.zero 首选 + NSScreen.screens.first fallback + warning，合并 v1 几何真理与 inflight-v2 文档化 API 两种意见；下面段落已重写以匹配 -->
- **Final anchor-resolution rule layers geometric truth + documented fallback.** The primary discriminator is `frame.origin == .zero` (the geometric definition of the AppKit origin display, which is also the AX coordinate anchor by construction). The fallback `NSScreen.screens.first` covers the brief System Settings transition windows where `frame.origin` may be transiently non-zero across all screens; when the fallback fires, the code logs a `anchor fallback` warning so the rare path is visible in triage. Earlier rounds of this plan ping-ponged between these two rules; v2 final layers them deliberately rather than choosing one. `NSScreen.main` is never used.
- **`isMain` → `isCoordinateAnchor` rename is preferred but not mandatory.** Renaming touches `DisplayFrame.swift`, `ScreenCoordinateConverter.swift`, `WindowActor.swift`, and `ScreenCoordinateConverterTests.swift` (12+ call sites by quick count). Mechanical, low-risk; the executor can take the small-diff fallback (keep `isMain`, add the contract doc comment) without violating any invariant. The contract — "this flag means AX coordinate anchor, never NSScreen.main" — is what must land; the name is convenience.
- **Logging the chosen display on every snap inflates the log volume.** Acceptable in DockTap's current usage profile (snaps are user-initiated, low-frequency). If volume becomes an issue, the log line can be conditional on a verbose flag.

## Test matrix

Pure unit tests added or extended (XCTest, no AX, no `NSScreen`):

### Coordinate converter

<!-- 修订v2: lead 拍板——重写测试矩阵：所有 isMain 改名 isCoordinateAnchor；首行新增 "vertical layout 必触发" 用例（Lead 强调）；新增 "selected ≠ anchor" 显式 fixture -->

| Scenario | Fixture | Assertion |
|---|---|---|
| **Vertical layout — secondary above anchor.** Anchor `(0, 0, 1920, 1080)`, secondary `(0, 1080, 1440, 900)` above. | `[anchor(isCoordinateAnchor:true), secondary]` | An AppKit rect `(0, 1080, 720, 875)` on the secondary round-trips to AX `(0, -875, 720, 875)` (negative AX y, since secondary sits above anchor in AX). `selectDisplay` for that rect returns the secondary `DisplayFrame`. **This is Lead's canonical B-1 reproducer; the test must exist verbatim.** |
| **Vertical layout — secondary below anchor.** Anchor `(0, 0, 1920, 1080)`, secondary `(0, -900, 1440, 900)` below. | `[anchor(isCoordinateAnchor:true), secondary]` | An AppKit rect on the secondary round-trips to AX with y in the `[1080, 1980]` band. |
| **"Selected ≠ anchor" explicit fixture.** Anchor `(0, 0, 1920, 1080)`, secondary right-of at `(1920, 0, 1440, 1080)` same height. | `[anchor(isCoordinateAnchor:true), secondary]` | `selectDisplay` for a rect inside secondary returns the **secondary** entry; converting that rect's origin both directions uses **anchor's** `frame.maxY` for `mainTopY`. Locks the v2 conceptual separation. |
| **Horizontal mixed-height** (v1 B-1 reproducer). Anchor `(0, 0, 1920, 1080)`, secondary `(1920, 0, 1440, 900)` right-of, shorter. | `[anchor(isCoordinateAnchor:true), secondary]` | A rect at AppKit `(1920, 0, 720, 875)` round-trips to AX `(1920, 205, 720, 875)`. AX origin is anchored at 1080, not 900. |
| **Anchor field, not array order, defines the anchor.** | `[secondary(isCoordinateAnchor:false), anchor(isCoordinateAnchor:true)]` | Conversion picks the anchor entry via the field, not array index 0. Locks against "first element" regressions. |
| **No anchor in the array.** | `[a(isCoordinateAnchor:false), b(isCoordinateAnchor:false)]` | `axRectToAppKit`, `appKitPointToAX`, `axPointToAppKit`, `selectDisplay` all return `nil`. Locks the B-2 contract. |
| Window straddling two same-height side-by-side displays | existing-style fixture, AX rect 50/50 split | `selectDisplay` returns the display with strictly larger intersection; if exactly tied, returns the one containing the center. |
| Window center inside the dock strip of one display | secondary `visibleFrame ≠ frame`, center inside the dock | `selectDisplay` still picks that display via frame intersection (C-1 documents this as deliberate). |

### Rect math

| Scenario | Fixture | Assertion |
|---|---|---|
| Odd-width visible frame `(0,0,1495,877)` | — | `leftHalf.maxX == rightHalf.minX` exactly; no seam. (N-2.) |
| Non-zero-origin visible frame `(1920, 100, 1440, 800)` (secondary, dock on bottom) | — | Existing tests cover this; add an assertion that `topHalf.minY > bottomHalf.maxY` is false (they meet at `midY`). |

### Display selection helper (if extracted)

<!-- 修订v2: lead 拍板——helper 测试矩阵改为 NSScreen.screens.first 路径；anchor 不再以 frame.origin==.zero 为判据 -->

| Scenario | Fixture (as `[NSScreen]`-shaped input) | Assertion |
|---|---|---|
| One screen | single | That screen is marked `isCoordinateAnchor: true`, returned as the anchor. |
| Two screens, screens[0] = anchor | two | `screens[0]` is marked; `screens[1]` is not. |
| Two screens, screens[0] is the **shorter** of two; user has dragged menu bar to screens[1] in System Settings | two | `screens[0]` (the array-first one, which is the documented menu-bar display) is still marked anchor — unless `CGMainDisplayID()` disagrees, in which case the helper logs a warning and prefers `CGMainDisplayID()`. Documents the rare fallback path. |
| Zero screens | empty | Helper returns empty array; caller no-ops with `no anchor display` log. |

Manual matrix (live AX, signed bundle, multi-display rig):

<!-- 修订v2: lead 拍板——vertical layout 抬升为 #1（Lead 标的 canonical break case）；菜单栏拖动行为对应 anchor 选取的改动，case 5 重写 -->
<!-- 修订v3: 应 Reviewer Tests C-2——补全 left/offset/visibleFrame-inset/fully-vs-straddling，并对每个用例标注预期 AX y 符号与 band，让 tester 可以直接对照 log 验证 -->

For every case below, the manual tester should: (a) reproduce, (b) read the `action applied` log line that includes `currentAppKit` / `rectAppKit` / `originAX`, (c) confirm the AX origin's sign and band match the "expected AX log" column. A wrong sign or wrong band is the fingerprint of a residual B-1-class bug surviving the fix.

| # | Layout | Action | Expected AX y sign / band on the snapped window | Pre-fix observed |
|---|---|---|---|---|
| 1 | **Vertical — secondary above anchor.** Anchor `(0, 0, 1920, 1080)`, secondary at AppKit y ∈ `[1080, 1980]`. Focus on secondary. | Snap left-half on secondary. | AX y **negative**, in band `[-875, 0)` (since secondary's top in AX is at `0 - 900 = -900`). | Window warps down to anchor screen. |
| 2 | **Vertical — secondary below anchor.** Anchor `(0, 0, 1920, 1080)`, secondary at AppKit y ∈ `[-900, 0]`. Focus on secondary. | Snap left-half on secondary. | AX y **positive**, in band `[1080, 1980)` (since secondary's top in AX is at `1080`). | Window warps up to anchor screen. |
| 3 | **Horizontal mixed-height — secondary right-of anchor, shorter.** Anchor `(0, 0, 1920, 1080)`, secondary `(1920, 0, 1440, 900)`. Focus on secondary. | Snap left-half on secondary. | AX y in band `[180, 1055]` (secondary visibleFrame minY in AX ≈ `1080 - 900 = 180`). | Window ~180pt too high; partly off-screen. |
| 4 | **Horizontal same-height — control case.** Two same-height monitors side by side at AppKit y=0. Focus on either. | Snap left-half. | AX y in band `[0, ~876]` on both. | Lands correctly pre-fix and post-fix; this is the control. |
| 5 | **Horizontal — secondary LEFT of anchor (negative AppKit X).** Anchor `(0, 0, 1920, 1080)`, secondary `(-1440, 0, 1440, 900)`. Focus on secondary. | Snap right-half on secondary. | AX **x negative** (in band `[-720, 0)`), AX y in band `[180, 1055]`. | Negative X passes through correctly — the v1 fixture set did not cover this; C-1 / C-2 add it. |
| 6 | **Side display with vertical offset.** Anchor `(0, 0, 1920, 1080)`, secondary `(1920, 200, 1440, 880)` (right-of and bottom-aligned). Focus on secondary. | Snap top-half on secondary. | AX y in band `[200, 640]` (AX y for AppKit y=200 is `1080 - 200 = 880`; for top half, AppKit y at `200 + 880/2 = 640` → AX y = `1080 - 640 - 440 = 0` for the top edge). Tester confirms the rect's top edge in AX is at the expected band; not pushed to the wrong screen. | Mis-anchor stacks with the y-offset — log shows a confusing rect entirely off the target screen. |
| 7 | **Mixed-scale.** 4K (1× scale) + Retina (2× scale) side by side. Focus alternates. | Snap each half on each screen. | AX y bands match the screen's own `visibleFrame`; **AX values are in points, not pixels** — same band whether scale is 1× or 2×. | Coordinates in points either way; the test confirms the converter does not scale. |
| 8 | **Mixed visibleFrame insets.** One display with dock at the bottom + menu bar at top; the other with dock at the right (or auto-hide on). Focus alternates. | Snap on each screen. | Each screen's snap rect equals that screen's `visibleFrame` halves / center; dock and menu-bar zones are excluded per-screen. Log's `rectAppKit` shows different inset amounts for each screen. | — |
| 9 | **Fully on secondary.** Window entirely inside the secondary screen's bounds before snap. | Snap any. | `selectDisplay` picks the secondary; `action applied` log includes the secondary's identifier. | — |
| 10 | **Straddling two displays.** Window straddles the anchor/secondary boundary (~50/50 by area). Pre-position the window across the boundary. | Snap any. | `selectDisplay` picks the side with strictly larger intersection; if the user moves it slightly so one side has 51%, that side wins. Log line names the chosen display. | — |
| 11 | **Drag the menu bar to the other display.** System Settings → Displays → drag the white menu-bar strip to the previously-secondary display. After macOS confirms the rearrangement, `NSScreen.screens.first` updates to the new menu-bar display. | Snap on each screen after the rearrangement. | AX origin tracks the new menu-bar display; snap lands correctly on both. If snap is wrong after rearrangement, executor is caching anchor — must re-read `NSScreen.screens.first` per invocation. | — |
| 12 | **Toggle `Displays have separate Spaces`** (System Settings → Desktop & Dock → Mission Control). Repeat cases 1–3. | Each snap respects each screen's current `visibleFrame`. Behavior unchanged versus the matching base case. | — |
| 13 | **Focus-transition moment.** Trigger snap immediately after unlocking the screen while no app is frontmost. | Pre-fix B-2: log `no selectable display`. Post-fix: anchor resolves via `NSScreen.screens.first` even when `NSScreen.main` is `nil`; if `frontmostApplication` is also nil, log `no frontmost app` and no-op (unchanged path). | Silent failure. |
| 14 | **Dock auto-hide mixed state.** One display with dock auto-hide on, the other off. Snap on each. | Snap rect respects each screen's current `visibleFrame` (taller on the auto-hide screen). | — |
<!-- 修订v3: 应 Reviewer Multi C-2 + Lead final——manual/test notes 落地：C-7 minimized policy 必须有对应 manual 验证位 -->
| 15 | **Minimized window (C-7 policy verification).** Minimize a resizable app's window (yellow traffic-light button → Dock). Window is in the Dock. Trigger any snap shortcut. | Log shows `action skipped windowAction=<x> minimized`; **no AX size/position write happens**; click the Dock icon to restore — window restores to its **pre-minimize** position and size (stored frame intact). | Pre-fix: undefined / app-specific (Electron may un-minimize and apply the snap; others silently mutate the stored frame so the next un-minimize lands at the snap rect instead of the user's original position). Post-fix: deterministic skip. |
| 16 | **Test note.** Minimized-window behavior is not covered by an XCTest (would require live AX). The manual row above is the regression net; if an automated test for the minimized short-circuit becomes valuable later, it would need an `AXUIElement` protocol seam — out of scope for the B-1 fix bundle. | — | — |

<!-- 修订v4: 应 Reviewer Multi 优先级要求——Lead 要求按 blocker→correctness→test gap→hygiene 排序成一份 executor 可逐 stage 推进的清单 -->
## Staged fix plan

Post-fix status in the current workspace: Stages 1-3 are implemented, including the coordinate-anchor rename, origin-zero/fallback mapping, minimized guard, applied/partial/failed result logs, chosen-display logging, converter fixtures, cross-preset matcher matrix, odd-width rect coverage, and pure display-mapper tests. Stage 4 remains a commit-message / repo-hygiene decision for whoever creates the follow-up commit. Optional Stage 5 is still future hardening. The original staged checklist is retained below as the execution trace.

### Stage 1 — Blocker (B-1 / B-2 / B-3): coordinate-anchor split + rename

Single, self-contained change. Lands the multi-monitor correctness fix and the doc edit that prevents regression.

- `Sources/DockTap/DisplayFrame.swift` — rename `isMain` → `isCoordinateAnchor`; add the doc comment from §Fix plan #3.
- `Sources/DockTap/ScreenCoordinateConverter.swift` — rename `mainTopY` → `anchorTopY`; field lookup uses `isCoordinateAnchor`. Public API signatures unchanged.
- `Sources/DockTap/WindowActor.swift` — rewrite `displayFrames()` per §Fix plan #1: resolve anchor via the **v2-final layered rule** (primary: `frame.origin == .zero`; fallback: `NSScreen.screens.first` with `anchor fallback` warning; optional sanity: `CGMainDisplayID()` cross-check); **do not** call `NSScreen.main`; **do not** cache across calls. Add the "no anchor display" log and the "chosen display" log line.
- `Tests/DockTapTests/ScreenCoordinateConverterTests.swift` — propagate the `isCoordinateAnchor:` rename. Other test additions arrive in Stage 3.
- `docs/plans/m4-window-snap.md` — rename + anchor-rule + step-8 wording edits per §Fix plan #4. **Must land in this stage**, not deferred, because a stale plan invites regression on the very next contributor.

Exit criterion: existing single-display behavior unchanged in manual matrix case 4 (control); manual matrix cases 1, 2, 3, 5, 6, 13 demonstrably fixed.

### Stage 2 — Correctness concerns (C-6, C-7, C-2, C-5)

Bundles into one PR; small surface; same hotpath as Stage 1 so iteration cost is low.

- `Sources/DockTap/WindowActor.swift` — branch the `action applied` log into `applied` / `partial` / `failed` per AX result codes (C-6). Add `kAXMinimizedAttribute` short-circuit alongside the existing `AXFullScreen` check (C-7). Add the `selectDisplay`-branch log line if the converter exposes which branch fired (C-2, C-5).
- `Sources/DockTap/ScreenCoordinateConverter.swift` — *(optional)* extend `selectDisplay` to return a tagged enum so the log can name the branch. If skipped, C-2 / C-5 are partially satisfied via the "chosen display" log from Stage 1.

Exit criterion: failed snaps log `action failed` (or `partial`) instead of `applied`; minimized windows produce `action skipped ... minimized`; every successful snap names the chosen display in the log.

### Stage 3 — Test gaps (Reviewer Tests C-1 / C-2 / C-3, Reviewer Multi C-3)

Pure test additions; no source change. Safe to land in parallel with Stages 1–2 or after.

- `Tests/DockTapTests/ScreenCoordinateConverterTests.swift` — add the left-of-anchor, side+vertical-offset, vertical-above, vertical-below, selected ≠ anchor, no-anchor fixtures per §Fix plan #5 and §Test matrix.
- `Tests/DockTapTests/WindowActionTests.swift` — odd-width fixture (N-2).
- `Tests/DockTapTests/RuleMatcherWindowActionTests.swift` — cross-preset matrix per §Fix plan #6a.
- `Tests/DockTapTests/WindowActorDisplaySelectionTests.swift` *(new, optional)* — anchor-resolution + unstable-anchor-across-calls tests per §Fix plan #7. If the executor declines the seam, the unstable-anchor case stays manual-only (matrix case 11).

Exit criterion: `swift test` green; the new converter fixtures cover all four layout classes (vertical above, vertical below, horizontal-left, horizontal-right-with-offset); matcher tests exercise every `TriggerModifierPreset`.

### Stage 4 — Documentation / repo hygiene (C-8)

- Decide between bless-retroactive (a) or split-into-new-commit (b) for `docs/plans/rectangle-integration-research.md`'s presence in `75d4f49`. Lead call; planner's lean is (a). Either way, the action belongs in its own PR so it does not muddy the Stage 1 diff.

Exit criterion: PR description for the M4-zone follow-up explicitly addresses the bundle, even if it chooses to leave history as-is.

### Optional Stage 5 — Future hardening (not blocked on M4 review)

Not required by this review, but worth recording so they do not get lost:

- Live Accessibility revoke detection (out of M4 scope per `docs/plans/m4-window-snap.md` §Risks).
- `selectDisplay` consistency around `visibleFrame` vs. `frame` for tie-break (C-1 in this report, distinct from Reviewer Tests C-1).
- Optional `verbose` log flag if the new per-snap log lines prove noisy in real usage.

## Rollout risks

<!-- 修订v2: lead 拍板——补充 rename 影响面（DisplayFrame.isMain 字段在测试和构造点广泛存在）与 anchor 取法切换的语义变化 -->

- **Silent visual change for current users on multi-display setups.** Users who have been working around B-1 (e.g., always snapping on the anchor screen because non-anchor results were off) will see different behavior post-fix. The behavior change is in the correct direction (snap now actually lands where the user expects on non-anchor screens), so this is the intended improvement, not a regression. Worth a one-line note in the README / changelog.
- **`isMain` → `isCoordinateAnchor` rename has a broad blast radius.** The field name appears in `DisplayFrame.swift`, `ScreenCoordinateConverter.swift`, `WindowActor.swift`, and `ScreenCoordinateConverterTests.swift` (12+ call sites by quick count). Mechanical, low-risk, but the executor should `grep -n isMain` to confirm completeness — leftover references will fail to compile, which is the desired failure mode (loud, not silent).
- **Off-screen window fallback changes meaning.** Pre-fix, the fallback was the focused-display screen; post-fix, it is the menu-bar / anchor display. If a user had a window on a now-disconnected display and triggered snap, pre-fix would fall back to the focused display (which may or may not be sensible); post-fix it falls back to the anchor. The anchor is the more predictable default; documenting this is enough.
- **Log volume.** Adding a "chosen display" log line per snap adds one line per shortcut. Snap rate is human-paced; volume is fine.
- **B-3 doc edit must land in the same change.** If the source is fixed but `docs/plans/m4-window-snap.md` still says "mark `NSScreen.main` as isMain," the next executor or contributor may revert the fix. The plan-edit is the load-bearing part of "this stays fixed."
- **`NSScreen.screens.first` semantics depend on macOS continuing to define `screens[0]` as the menu-bar display.** This is documented and has been stable for years. The `CGMainDisplayID()` cross-check in the fix plan is the belt for the suspenders.
- **No new TCC prompt.** No expansion of the AX trust surface; the fix only changes which display anchors the conversion. No permissions risk.
- **Test additions are pure unit tests, no live AX / NSScreen.** Stable in CI; no flakiness risk.
<!-- 修订v3: lead 拍板——"will report independently" 改为已完成口径；v3 final 即整合结果 -->
- **Reviewer integration is complete.** Both reviewer audits (multi + tests) reported; their findings are folded into this file with marker attribution. No further reviewer round is pending before executor handoff. If post-implementation surprises surface a new bug class, the next plan (not this one) should cover it.
