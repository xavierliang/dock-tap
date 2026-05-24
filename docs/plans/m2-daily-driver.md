<!-- 修订v1: lead 拍板——创建 M2 Daily Driver 计划，理由 M1 已提交且用户确认正式 bundle id、Launch at Login 与修饰键预设边界 -->
# M2 Daily Driver Plan

## Context

M1 commit `bc8717c` gives Dock Tap a working product skeleton: signed packaged app, menu bar UI, active `CGEventTap`, physical left Option matching, read-only Dock slot parsing, and app/Finder activation.

M2 should make the app usable as a daily driver without turning it into a broader shortcut manager. The locked user decisions are:
- Formal bundle id is `ai.resopod.docktap`.
- Launch at Login is in M2.
- Modifier settings use fixed presets only. No Custom option and no shortcut recorder.
- Preset physical trigger keys are Left Option by default, Left Command, Left Control, Right Option, and Right Command.

The main trade-off is accepting one fresh TCC/Accessibility grant for the final bundle id now. That is cheaper than letting users daily-drive the app under `dev.local.DockTap` and migrating trust later.

## Scope & Non-goals

In scope:
- Change packaged app identity from `dev.local.DockTap` to `ai.resopod.docktap` in bundle metadata and signing scripts.
- Make permission copy and menu actions clearer for the new TCC grant caused by the bundle id change.
- Add Launch at Login using `SMAppService.mainApp` on macOS 13+.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——Launch at Login 记录当前 packaged app path，理由 build artifact 被移动或清理会让本地登录项失效 -->
- Document that M2 local daily-driver Launch at Login registers the current packaged signed app path. Daily use should run `DockTap.app` from a stable location such as `/Applications` or a project build path the user will not clean.
- Persist the selected trigger modifier preset in `UserDefaults`, defaulting to Left Option.
- Generalize shortcut matching from hardcoded Left Option to the selected physical preset while keeping side-specific modifier tracking.
- Tighten the status menu for daily use: clearer status, compact Dock rows, modifier preset selection, Launch at Login toggle, refresh, logs, permission/settings actions, and quit.
- Add concise README or usage documentation for local build, signing, Accessibility, Launch at Login, and preset behavior.
- Keep current Dock slot reading, immutable shortcut intent binding, activation/launch behavior, and event tap architecture.

Out of scope:
- No Sparkle, notarized DMG, installer, auto-update, paid/licensing features, analytics, or release channel work.
- No App Store/MAS compatibility pass.
- No window cycling, window picker, per-window switching, or "cycle through windows of app".
- No Dock mutation, Dock auto-listening, Dock Accessibility scraping, or background Dock observer.
- No complex shortcut recorder, Custom trigger, multi-key chords, app-specific shortcuts, or per-slot remapping.
- No broad UI rewrite, SwiftUI migration, onboarding flow, or preferences window.

## Architecture

Bundle identity and TCC:
- Update the app bundle id to `ai.resopod.docktap` in `Resources/Info.plist` and `scripts/run-app.sh`.
- Keep the existing stable-signing requirement. Ad-hoc remains explicit launch-smoke only and must not be presented as valid for Accessibility validation.
- Treat the bundle id change as a fresh TCC identity. Logs, menu copy, and README should explicitly say the user must grant Accessibility to the packaged signed `DockTap.app` with bundle id `ai.resopod.docktap`.
- Do not attempt automatic TCC migration or deletion of the old `dev.local.DockTap` entry. That is user/system controlled and should be documented only.

Settings model:
- Add a tiny `TriggerModifierPreset` value type or enum with exactly five cases: `leftOption`, `leftCommand`, `leftControl`, `rightOption`, `rightCommand`.
- Each preset owns its stable raw value, menu title, shortcut label prefix, and physical key semantics.
- Add `SettingsStore` backed by injectable `UserDefaults`. It stores only the selected preset in M2 and falls back to Left Option for missing or unknown values.
- Avoid persistence from the event tap callback. The app delegate reads settings on launch and pushes a small immutable/current preset value into the input layer.

Input matching:
- Keep `ModifierState` as the source of side-specific physical key state.
- Replace the current hardcoded "leftOption must be down and other command/control/option/shift modifiers reject" logic with preset-aware matching.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——逐 preset 固定 matcher 不变量，理由 selected family 不能被自己的 Option/Command/Control 族 reject -->
- A shortcut matches only when the selected physical preset key bit is true.
- Every non-selected Option/Command/Control side key must be false. For example, Left Command preset is not rejected by Left Command itself, but Right Command, either Option, and either Control reject; Right Option preset is not rejected by Right Option itself, but Left Option, either Command, and either Control reject.
- Any Shift key must be false for every preset.
- Caps Lock and Fn remain non-rejecting where observable.
- Assigned digit slots are still consumed and bound to immutable `DockSlotTarget` values. Unassigned digit shortcuts still pass through.
- Finder backtick remains global and uses the same selected preset, so the visible behavior changes from `leftOption+backtick` to `<selected preset>+backtick`.
- The event tap callback should do only modifier update/resync, snapshot read, pure matching, enqueueing, and consume/pass-through. No AppKit, ServiceManagement, UserDefaults, Dock reads, or logging-heavy work in the callback.

Launch at Login:
- Add a small `LoginItemController` wrapper over `SMAppService.mainApp`.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——LoginItemController 使用 injectable adapter 并强制 pure tests，理由 注册失败和状态映射必须可测且不能假装成功 -->
- Put the direct `SMAppService.mainApp` calls behind a tiny injectable adapter/protocol so `LoginItemControllerTests` can exercise status mapping and thrown register/unregister failures without mutating real login items.
- The status menu toggle calls register/unregister and then rebuilds the menu from actual `SMAppService.status`.
- The OS login item status is the source of truth. M2 does not need to store a separate "launch at login" preference, except optional diagnostic copy if the implementation already needs it.
- Surface statuses simply: enabled, disabled, requires approval, not found/error. For `requiresApproval`, point the user to System Settings Login Items.
- If register or unregister throws, log/display the failure and leave the menu state derived from the actual service status; never flip the checkmark optimistically.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——登录项路径稳定性进入架构约束，理由 M2 无 installer 不能假装 build/DockTap.app 是发布安装路径 -->
- `SMAppService.mainApp` registers the bundled app at its current path. If the user registers `build/DockTap.app` and later deletes, cleans, or moves that path, the login item may stop launching or launch an obsolete copy. M2 should document this clearly and validation should confirm both `SMAppService.mainApp.status` and the app path observed after restart/login.
- Trade-off: using the main app login item avoids helper targets and keeps the bundle simple, but local testing must use the packaged signed app, not `swift run`.

Menu UI:
- Keep the accessory menu bar app and status item title `DT`.
- Replace development-heavy slot titles with daily-use labels. Keep enough state to diagnose, but remove noisy `shortcutIndex=` / `dockOrdinal=` text from the main menu rows.
- Suggested menu shape:
  - One disabled status row: Accessibility, tap state, Dock slot count, login item state.
  - Dock shortcut rows using the selected preset label, digit, app name, and status.
  - Finder row using the selected preset label plus backtick.
  - Trigger Modifier section with radio/checkmark items for the five presets.
  - Launch at Login checkable item.
  - Commands: Refresh Dock, Open Accessibility Settings or Check Accessibility, Show Logs, Quit.
- Logs can keep `shortcutIndex` and `dockOrdinal` for debugging, but user-facing menu rows should read like a product menu.

Documentation:
- Add `README.md` if it does not exist.
- Keep README concise and operational: what Dock Tap does, macOS 13+ requirement, build/run command, stable signing env var, Accessibility grant, Launch at Login behavior, preset list, and known limitations.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——README 建议稳定 app 路径，理由 daily driver 本地登录项依赖注册时 bundle path -->
- README must recommend a stable local daily-use app path before enabling Launch at Login, such as copying the built `DockTap.app` to `/Applications` or keeping the project build path intact.
- Do not add marketing copy or publish/release promises in M2 docs.

## Files to change

- `Resources/Info.plist` - change `CFBundleIdentifier` to `ai.resopod.docktap`; keep accessory app metadata and version simple.
- `scripts/run-app.sh` - change `BUNDLE_ID`; keep stable signing checks and explicit unstable ad-hoc fallback wording aligned with the formal bundle id.
- `Sources/DockTap/AppDelegate.swift` - wire settings load/save, menu preset selection, login item toggle/status, clearer permission actions, and event tap preset updates while keeping app lifecycle small.
- `Sources/DockTap/EventTapController.swift` - accept and lock the current trigger preset alongside the slot snapshot; pass both into pure matching.
- `Sources/DockTap/RuleMatcher.swift` - replace hardcoded Left Option matching with preset-aware physical modifier matching.
- `Sources/DockTap/KeyEventDecider.swift` - thread the selected preset/configuration into shortcut decisions.
- `Sources/DockTap/ModifierState.swift` - keep physical side tracking; add small helper behavior only if it keeps preset matching readable.
- `Sources/DockTap/KeyCodes.swift` - use existing side-specific modifier keycodes; add labels only if needed for preset metadata.
- `Sources/DockTap/ShortcutIntent.swift` - update label/display behavior so Finder and Dock shortcuts reflect the selected preset where user-facing text needs it; do not weaken immutable target binding.
- `Sources/DockTap/LogStore.swift` and `Sources/DockTap/LogWindowController.swift` - adjust log messages only where M2 status/preset/login item copy needs clarity.
- `Sources/DockTap/PermissionGate.swift` - optionally add an `openAccessibilitySettings` helper or keep this in a tiny separate UI helper; do not hide the existing trust check.
- `Sources/DockTap/SettingsStore.swift` - new small UserDefaults-backed store for selected trigger preset.
- `Sources/DockTap/TriggerModifierPreset.swift` - new preset model for the five allowed physical trigger keys.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——LoginItemController 包装 injectable SMAppService adapter，理由 状态和失败路径必须纯单测覆盖 -->
- `Sources/DockTap/LoginItemController.swift` - new small wrapper around `SMAppService.mainApp` through an injectable adapter/protocol; maps raw service status and register/unregister failures to menu/log-facing state.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——测试文件命名具体化，理由 executor/reviewer 需要可直接运行的目标 -->
- `Tests/DockTapTests/TriggerModifierPresetTests.swift` - new tests for preset raw values, menu titles, shortcut label prefixes, and selected physical key semantics.
- `Tests/DockTapTests/RuleMatcherPresetTests.swift` - new or renamed tests for each preset's matcher invariants, assigned/unassigned slots, Finder backtick, and immutable target binding.
- `Tests/DockTapTests/ModifierStateTests.swift` - keep current side-specific modifier coverage and add assertions only if preset helpers land there.
- `Tests/DockTapTests/SettingsStoreTests.swift` - new tests for default Left Option, persistence, and unknown raw value fallback.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——LoginItemControllerTests 必须覆盖状态映射和 throw，理由 登录项 UI 不能在失败时显示成功 -->
- `Tests/DockTapTests/LoginItemControllerTests.swift` - required pure tests with the injectable adapter; cover enabled, disabled, requiresApproval, notFound, error display mapping, and register/unregister throw behavior.
- `README.md` - new concise daily-driver usage and local validation notes.

## Implementation steps

1. Update bundle id metadata and run script constants to `ai.resopod.docktap`; keep signing verification strict.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——先落 preset 不变量测试再改 matcher，理由 防止 Command/Option family 误 reject selected key -->
2. Add `TriggerModifierPreset`, `SettingsStore`, and their tests before touching event tap matching.
3. Refactor matching so `RuleMatcher` decides against a selected preset instead of hardcoded Left Option, with tests proving: selected key matches; paired/non-selected side key alone does not match; selected plus Shift rejects; selected plus another non-selected Option/Command/Control key rejects; Caps/Fn do not reject.
4. Push the selected preset from `AppDelegate` into `EventTapController` on launch and whenever the menu selection changes.
5. Update menu rendering to show compact shortcut labels derived from the selected preset, plus checkmarked preset choices.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——登录项先做 adapter 和 pure tests，理由 register/unregister 失败必须显示失败而非乐观成功 -->
6. Add `LoginItemController` using an injectable `SMAppService.mainApp` adapter, then wire a checkable Launch at Login menu item that updates from actual service status and logs/displays thrown failures.
7. Improve permission menu/log copy for the formal bundle id and add an action that either prompts again or opens Accessibility settings.
8. Keep Dock refresh, immutable shortcut intents, and activation behavior unchanged except for user-facing shortcut labels.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——README 和验收必须说明登录项路径，理由 build/ 里的 app 不是稳定安装路径 -->
9. Add or update tests for presets, settings persistence, and login-item state/failure mapping; then document Launch at Login path stability before manual validation.
10. Add the concise README after behavior and command names are final.

## Verification

<!-- 修订v2: lead 拍板（应 Reviewer N-1）——验证命令和测试名具体化，理由 reviewer 需要可机械执行的 checklist -->
Automated:
- Run `swift test`.
- Run focused tests during implementation:
  - `swift test --filter TriggerModifierPresetTests`
  - `swift test --filter SettingsStoreTests`
  - `swift test --filter LoginItemControllerTests`
  - `swift test --filter RuleMatcherPresetTests`
- Run `swift build`.
- Run `DOCK_TAP_CODESIGN_IDENTITY="<local signing identity>" scripts/run-app.sh`.
- Verify bundle id with `plutil -extract CFBundleIdentifier raw -o - build/DockTap.app/Contents/Info.plist`; expected output is `ai.resopod.docktap`.
- Verify signing with `codesign -d -r- build/DockTap.app` and confirm the designated requirement is not cdhash-only.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——逐 preset 测试矩阵列入验收，理由 selected key 与同族 reject 规则最容易回归 -->
- In `RuleMatcherPresetTests`, cover every preset: selected physical key matches; paired/non-selected side key alone does not match; selected plus Shift rejects; selected plus another non-selected Option/Command/Control key rejects; selected plus Caps/Fn still matches.
- In `SettingsStoreTests`, use isolated `UserDefaults` suites and confirm tests do not write to the developer's real app defaults.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——登录项纯测不可选，理由 失败路径不能依赖手测才发现 -->
- In `LoginItemControllerTests`, cover enabled, disabled, requiresApproval, notFound, and error display mapping, plus register/unregister throws that log/display failure and do not report success.

Manual:
- Launch the packaged signed app after the bundle id change and grant Accessibility to the new `DockTap.app` entry.
- Confirm the menu clearly distinguishes missing Accessibility, trusted Accessibility, tap ready/not ready, and Dock slot count.
- Select each modifier preset from the menu, reopen the menu, and confirm the checkmark persists after quit/relaunch.
- For each preset, press the preset plus `1` on an assigned slot in a text field; confirm the key is consumed and the target app activates or launches.
- Press an unassigned digit shortcut if fewer than 10 slots exist; confirm it passes through.
- Press the non-selected side/key equivalents, such as Right Option when Left Option is selected; confirm they pass through.
- Press the selected preset plus Shift/Command/Control/other Option as an extra modifier; confirm it passes through unless that key is the selected preset itself.
- Press the selected preset plus backtick from TextEdit or another ordinary text field; confirm Finder activates globally and the key does not insert text.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——手动登录项 checklist 增加 status 与 path，理由 本地 daily-driver 依赖注册路径仍存在 -->
- Before enabling Launch at Login for daily use, place `DockTap.app` at a stable path such as `/Applications/DockTap.app` or keep the chosen project `build/DockTap.app` path intact.
- Toggle Launch at Login on and confirm the menu reports the actual `SMAppService.mainApp.status` as enabled, not merely the requested action.
- Quit, log out/in or restart, and confirm Dock Tap starts as an accessory menu bar app from the expected app path shown in launch logs.
- Move or delete only a disposable test copy after disabling Launch at Login; do not treat a cleaned `build/` artifact as a stable installed app.
- Toggle Launch at Login off and confirm the menu reports disabled and the app no longer starts on the next login.
- If macOS reports login item approval required, confirm the menu/README directs the user to System Settings Login Items.

## Risks

- TCC trust is tied to bundle identity and signing requirement. The M2 bundle id change intentionally requires a new Accessibility grant; old `dev.local.DockTap` permission entries may remain visible until the user removes them.
- `SMAppService.mainApp` behavior depends on running a bundled, signed app. Testing with `swift run` is not meaningful for Launch at Login.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——记录 build artifact 路径风险，理由 登录项引用注册时 app path -->
- Local Launch at Login registration points at the current packaged app path. If that path is under `build/` and the directory is cleaned or moved, the login item can break; M2 mitigates by documentation and manual path validation, not by adding an installer.
- Command and Control presets can collide with common app/menu shortcuts. Dock Tap will consume assigned shortcuts for the selected preset, but unassigned shortcuts pass through to the frontmost app.
- Some users may expect Right Control or Custom. M2 deliberately excludes them to keep the input model small and avoid a recorder.
- Login item registration may enter `requiresApproval`; the app can explain the state, but the user must approve it in System Settings.
- Secure Input and event tap disablement risks remain from M1. M2 should preserve the minimal callback and existing recovery behavior.
- Non-US keyboard layouts and dead-key behavior still affect the physical backtick key. M2 keeps physical-key semantics; layout-aware shortcuts are out of scope.
