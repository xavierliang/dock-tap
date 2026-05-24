<!-- 修订v1: lead 拍板——创建 M1 Dock Tap 产品骨架计划，理由 M0 输入方向已手动验收可进入真实 Dock 槽位动作 -->
# M1 Dock Product Skeleton Plan

## Context

M0 has validated the hard part: a Swift + AppKit accessory app can use an active `CGEventTap`, track the physical left Option key, consume matched shortcuts, and pass through non-matches.

M1 turns that probe into the first real Dock Tap skeleton. The product should read the user's pinned Dock apps, expose the first 10 `.app` slots in the menu bar, and route the already-proven shortcuts to app activation or launch.

Locked decisions:
- Keep Swift + AppKit; no Electron, SwiftUI rewrite, webview, or extra runtime.
- Keep the active `CGEventTap` input engine and physical left Option semantics from M0.
- Treat the Dock preferences as read-only source data.
- Use product identity now: `Dock Tap`, not `DockTapProbe`. This requires a fresh Accessibility grant, but avoids carrying probe naming and bundle identity into future milestones.
- Keep callback work minimal. The tap callback may decide and consume; all Dock reads, menu updates, and `NSWorkspace` / `NSRunningApplication` work happen outside the callback.

## Scope & Non-goals

In scope:
- Read Dock `persistent-apps` from the `com.apple.dock` preferences domain.
- Parse pinned `.app` entries in Dock order and expose the first 10 app slots as `leftOption+1` through `leftOption+9` and `leftOption+0`.
- Show slot names and simple state in the menu bar app.
- Activate a running slot app with `NSRunningApplication`; launch a non-running slot app with `NSWorkspace`.
- Make `leftOption+backtick` activate Finder globally.
- Keep Accessibility permission, stable local signing, and packaged `.app` launch behavior from M0.
- Keep concise logs for app lifecycle, permission/tap state, Dock sync, shortcut actions, and failures.

Out of scope:
- No full settings page, editable shortcuts, Dock editor, app reordering, or persistence beyond reading Dock preferences.
- No Sparkle, login item, installer, notarization/publishing flow, paid features, analytics, or onboarding.
- No window cycling or per-window switching; activating an already-active app is a no-op-style activation.
- No App Store compatibility work in M1.
- No attempt to observe or mutate the live Dock UI through Accessibility.
- No verbose probe log stream for every `flagsChanged`, pass-through key, or raw key event.

## Architecture

Product shape:
- Rename the SwiftPM product, executable target, source folder, app bundle, and display name from `DockTapProbe` to `DockTap`.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——本地里程碑固定使用 dev.local.DockTap，理由 避免 M1 之后因随意换 bundle id 反复触发 TCC 迁移 -->
- Use bundle id `dev.local.DockTap` for M1 and later local milestones. Do not change it casually after M1; any real release bundle id requires a separate migration plan outside M1.
- Keep `DOCK_TAP_CODESIGN_IDENTITY` as the stable-signing input. Ad-hoc signing remains explicit launch-smoke fallback only, not TCC acceptance.
- Trade-off: renaming costs one new Accessibility approval, but it prevents M1 from stabilizing around a probe identity.

Dock slot model:
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——区分 dockOrdinal 与 shortcutIndex，理由 原始 Dock 位置和过滤后快捷键槽位不能混用 -->
- Introduce a small value model for the 10 product slots: shortcut label, `dockOrdinal`, `shortcutIndex`, app URL, display name, optional bundle id, and status.
- `dockOrdinal` means the original position in the Dock `persistent-apps` array; `shortcutIndex` means the filtered Dock Tap slot index `0...9` used by `leftOption+1..9,0`.
- Read `persistent-apps` using `CFPreferences` or `UserDefaults` property-list APIs, not by shelling out to `defaults`.
- Parse defensively: preserve Dock order, inspect `tile-data` / `file-data`, accept local `.app` file URLs, keep missing `.app` paths visible as missing, and ignore folders, documents, spacers, malformed tiles, and non-app entries.
- Take the first 10 accepted `.app` entries. Non-app Dock items do not consume Dock Tap shortcut slots.
- Refresh slots on launch, when the menu is opened, and when the user chooses a simple `Refresh Dock` menu command. Avoid fragile Dock notification plumbing in M1.
- Trade-off: this can be stale immediately after Dock edits until refresh/menu open, but keeps M1 simple and avoids pretending Dock preference notifications are a stable API.

Input and actions:
- Convert the M0 rule layer from "probe matches" to product shortcut intents.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——数字快捷键使用 shortcutIndex 命名，理由 避免把过滤后槽位误称为原始 Dock 位置 -->
- `leftOption+1..9,0` maps to `shortcutIndex` values `0...9` only when that slot exists in the latest slot snapshot; unassigned digit shortcuts pass through.
<!-- 修订v1: lead 拍板——missing Dock app 仍视为 assigned slot，理由 固定槽位应给出失败反馈而不是把按键漏给前台 app -->
- A parseable but missing `.app` path remains an assigned slot: consume the shortcut, show `missing`, and log the activation failure.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——ShortcutIntent 绑定 immutable slot snapshot 内的目标，理由 refresh 后已入队动作不能漂移到新槽位 -->
- When the tap callback creates a `ShortcutIntent`, it must bind the target from one immutable slot snapshot: slot id, app URL, display name, bundle id, missing status, `dockOrdinal`, and `shortcutIndex`.
- Slot refresh swaps in a new snapshot only for future key events. The main-thread action handler must execute the target already bound inside the queued intent and must not perform a second lookup by latest `shortcutIndex`.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——Finder backtick 保持全局吞键，理由 这是 M1 的有意产品行为而非 Finder-frontmost 特例 -->
- `leftOption+backtick` maps to Finder activation globally; it is no longer gated on Finder being frontmost.
- Keep extra-modifier rejection from M0: right Option, Shift, Command, and Control reject product shortcuts; Caps Lock / Fn remain record-only where observable.
- The tap callback consumes only recognized product shortcuts, enqueues a shortcut intent to the main thread, and returns immediately.
- Slot lookup for consume/pass-through decisions uses a simple thread-safe immutable snapshot of assigned slot targets, not AppKit calls.

Activation:
- Resolve each slot's bundle id from its `.app` bundle when available. Use the app URL as the launch source of truth.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——激活层只消费 intent 内绑定目标，理由 防止 main thread 按最新槽位二次查找 -->
- For a running app, choose a matching `NSRunningApplication` by the bundle id bound in the `ShortcutIntent` and activate it with all windows.
- If no matching app is running, launch via `NSWorkspace` from the app URL bound in the `ShortcutIntent` and log completion or error.
- For Finder, activate an existing `com.apple.finder` running application; if needed, fall back to launching Finder through `NSWorkspace` by bundle id.
- Do not implement same-app window cycling. Repeated shortcut presses simply activate the target app.

Menu bar UI:
- Keep an accessory/menu-bar app with status item title `DT`.
- Replace the M0 probe menu with product rows:
  - A compact status row for Accessibility/tap state and number of loaded Dock slots.
  <!-- 修订v2: lead 拍板（应 Reviewer C-2）——菜单和日志显式标注 shortcutIndex/dockOrdinal，理由 reviewer 需要机械确认两种序号未混用 -->
  - Slot rows for `leftOption+1` through `leftOption+0`, each showing shortcut label, `shortcutIndex`, `dockOrdinal`, display name, and state: active, running, not running, or missing.
  - A Finder row for `leftOption+backtick`.
  - Commands: `Refresh Dock`, `Show Logs`, `Check Accessibility`, and `Quit`.
- Update running/active state from `NSWorkspace` launch, terminate, and activate notifications.
- Keep the log window as a diagnostic view, but default logs should be action-level and state-level, not raw input tracing. Slot-related logs must label `shortcutIndex` and `dockOrdinal` explicitly.

## Files to change

- `Package.swift` - rename package/product/target to `DockTap`; keep one executable target and focused tests.
- `Resources/Info.plist` - rename display/executable/bundle metadata to Dock Tap, fixed M1 bundle id, accessory app setting, and current local version.
- `scripts/run-probe.sh` - replace with `scripts/run-app.sh` for `build/DockTap.app`; preserve stable signing checks and explicit unstable ad-hoc fallback. Leave a small compatibility shim only if current local workflow still needs the old script name.
- `Sources/DockTapProbe/` - mechanically rename to `Sources/DockTap/`.
- `Sources/DockTap/AppDelegate.swift` - wire product services, status menu, permission/tap lifecycle, Dock refresh, workspace state updates, and shortcut action handling.
- `Sources/DockTap/EventTapController.swift` - keep M0 tap installation/recovery; replace probe record emission with shortcut intent enqueueing and assigned-slot snapshot updates.
- `Sources/DockTap/ModifierState.swift` - keep M0 physical modifier behavior.
- `Sources/DockTap/KeyCodes.swift` - keep digit/backtick/modifier physical keycodes.
- `Sources/DockTap/KeyEventDecider.swift` - rename or adapt to return product shortcut intents and consume only recognized assigned shortcuts.
- `Sources/DockTap/RuleMatcher.swift` - rename or adapt to product shortcut matching; remove Finder-frontmost requirement.
- `Sources/DockTap/ActiveAppProvider.swift` - repurpose for active app state, or fold into a small workspace state service if that keeps `AppDelegate` cleaner.
- `Sources/DockTap/LogStore.swift` - rename probe-specific event/result types and remove raw pass-through/state-only record assumptions.
- `Sources/DockTap/LogWindowController.swift` - keep the simple bounded log window.
- `Sources/DockTap/DockPreferencesReader.swift` - new focused parser for Dock `persistent-apps`.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——DockSlotStore 发布 immutable slot snapshot，理由 tap 与 action 必须共享同一目标版本 -->
- `Sources/DockTap/DockSlotStore.swift` - new small owner for current slots, immutable assigned-slot snapshots, refresh results, and menu-facing state.
- `Sources/DockTap/ShortcutIntent.swift` - new small value model carrying the shortcut kind plus the bound slot target fields needed by activation/logging.
- `Sources/DockTap/AppActivator.swift` - new focused service for app/Finder activation and launch; it consumes the bound `ShortcutIntent` target, not a mutable `shortcutIndex` lookup.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——parser tests 使用真实 Dock plist 抽样 fixture，理由 纯手写 fixture 容易漏掉 Apple 实际结构 -->
- `Tests/DockTapTests/Fixtures/real-dock-persistent-apps-sanitized.plist` - sanitized fixture derived from a real Dock `persistent-apps` sample, with private paths/usernames removed but original structure preserved.
- `Tests/DockTapTests/DockPreferencesReaderTests.swift` - fixture-based tests for Dock plist parsing, filtering, ordering, first-10 behavior, missing apps, malformed tiles, and the sanitized real Dock sample.
- `Tests/DockTapTests/RuleMatcherTests.swift` - update shortcut tests for assigned slots, unassigned pass-through, immutable intent target binding, Finder global backtick, extra-modifier rejection, and keyUp pass-through.
- `Tests/DockTapTests/ModifierStateTests.swift` - carry over M0 modifier tests under the renamed target.

## Implementation steps

1. Rename the package, target, app bundle metadata, script, source directory, and test directory from probe identity to product identity.
2. Preserve the existing Accessibility gate, stable signing checks, app-bundle launch path, event tap install/recovery, and modifier state tests before adding product behavior.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——Dock parser 先覆盖真实结构 fixture，理由 M1 要证明能读现实 persistent-apps 而非理想化样本 -->
3. Add the Dock preferences parser with property-list fixtures, including the sanitized real Dock sample, and tests before wiring it into the app.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——slot store 以 immutable snapshot 驱动 intent，理由 refresh 不能改写已入队快捷键目标 -->
4. Add the slot store that owns the latest parsed slots, immutable assigned-slot snapshots for the input engine, and menu-facing state.
5. Replace probe rules with product shortcut intents: assigned Dock slot digits and global Finder backtick.
6. Wire event tap matches to create fully bound `ShortcutIntent` values from one snapshot and enqueue them on the main thread, while keeping callback work limited to modifier update, pure matching, snapshot read, enqueue, and consume/pass-through.
7. Add `AppActivator` and route slot/Finder intents to running-app activation or workspace launch using only the target data carried by the intent.
8. Rebuild the status menu around slot rows, state rows, refresh, logs, permission check, and quit.
9. Reduce logging to concise product diagnostics: launch, permission/tap state, Dock refresh summary, action start/success/failure, and tap recovery.
10. Remove or rename probe-only model names once behavior is covered by tests.

## Verification

Automated:
- Run `swift test`.
- Run `swift build`.
- Run `DOCK_TAP_CODESIGN_IDENTITY="<local signing identity>" scripts/run-app.sh` and verify `build/DockTap.app` launches with bundle id `dev.local.DockTap` and a non-cdhash-only designated requirement.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——deterministic parser tests 使用 sanitized real Dock fixture，理由 单测稳定且覆盖真实 persistent-apps 形状 -->
- Confirm parser tests do not read the developer's real Dock during deterministic runs; they should use in-memory fixture dictionaries plus the sanitized real Dock plist fixture.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——测试已入队 intent 不受 refresh 漂移影响，理由 防止快捷键按下与执行目标不一致 -->
- Add a pure test where a slot snapshot creates an intent, the store refreshes to a different app at the same `shortcutIndex`, and the action layer still receives the original intent target fields.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——增加 opt-in 真实 Dock smoke，理由 验证本机现实数据但不污染 deterministic unit test -->
- Run an opt-in smoke path, such as `DOCK_TAP_SMOKE_REAL_DOCK=1 swift test --filter DockPreferencesReaderSmokeTests`, that reads the current user's real Dock preferences and prints a parsed summary. This smoke is informational and must not be required for deterministic CI-style unit tests.

Manual:
- First launch without Accessibility permission: menu/logs should show missing permission and the system prompt path.
- After granting Accessibility and relaunching: tap should install and menu should show trusted/tap-ready state.
- Open the menu and confirm the first 10 pinned `.app` Dock entries appear in Dock order, with non-app items ignored.
- Use `Refresh Dock` after changing pinned Dock apps; confirm slot rows update without relaunching the app.
- In a text field, press `leftOption+1` for an assigned slot; confirm no character is inserted and the target app activates or launches.
- Press a shortcut for an unassigned slot, if fewer than 10 slots exist; confirm it passes through and no activation is attempted.
- Press `rightOption+1` and `leftOption+shift+1`; confirm they pass through and do not activate apps.
- Press `leftOption+0`; confirm it targets the tenth parsed Dock app.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——手测菜单/日志序号标签，理由 确认 dockOrdinal 与 shortcutIndex 没有 UI 混淆 -->
- Open the menu and logs after a Dock refresh; confirm slot rows/action logs explicitly label both `shortcutIndex` and `dockOrdinal`, or otherwise make their meaning unambiguous.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——验收 TextEdit 中 Finder backtick 被全局吞键，理由 这是有意产品行为 -->
- In TextEdit or another ordinary text field, press `leftOption+backtick`; confirm no character/dead-key input reaches the field and Finder activates globally.
- Quit from the menu and confirm the event tap stops cleanly.

## Risks

- Dock preference structure is not a formal product API. Defensive parsing and fixture coverage reduce breakage, but M1 should log skipped malformed entries instead of failing launch.
- Slot refresh can be stale until launch, menu open, or manual refresh. This is accepted for M1 to avoid unreliable Dock observation.
- Some Dock entries may point to missing, moved, or translocated apps. Keep parseable missing `.app` entries visible as assigned-but-missing slots, consume their shortcuts, and log a clear failure.
- Bundle id resolution can fail for damaged or missing apps. Launch by URL should be preferred for concrete slots; bundle id is mainly for running-state detection.
- Accessibility/TCC trust changes with the M1 bundle id. Manual verification must use the packaged signed `.app`, not `swift run`.
- Secure Input and system tap disablement risks remain from M0; keep callback work minimal and recovery logs concise.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——记录非 US/dead-key 风险，理由 M1 仍按物理 backtick keycode 实现全局 Finder 快捷键 -->
- Non-US keyboard layouts and dead-key behavior may make physical keycode 50 feel different from a displayed backtick. M1 keeps the physical-key behavior; layout-aware or configurable shortcuts are a later milestone.
