<!-- 修订v1: lead 拍板——创建 M0 输入探针计划，理由 方案已锁定需交给 executor 按单一路径实现 -->
# M0 Input Probe Plan

## Context

The repository is effectively empty. M0 is a narrow macOS input-engine probe, not a complete Dock Tap product.

Locked decisions:
- Use Swift + AppKit only.
- Use an active `CGEventTap` so matched events can be consumed.
- Track physical left/right modifier keys with an explicit state machine.
- Hardcode default probes: `leftOption+1..9,0` globally, and `leftOption+backtick` only when Finder is frontmost.

Success means the app can request the needed permission, install the tap, distinguish left Option from right Option, match the hardcoded rules, consume matched keyDown events, and show enough live logging to verify behavior.

## Scope & Non-goals

In scope:
- A minimal native macOS accessory app with a menu bar item and a small log window.
- Accessibility permission check and prompt path.
- Active keyboard event tap for `keyDown`, `keyUp`, and `flagsChanged`.
- Physical modifier tracking for left/right Option, Command, Control, and Shift where needed for reliable matching.
- Rule matching for the locked M0 shortcuts.
- Human-readable logs for permission state, tap state, modifier state changes, raw key events, rule matches, consumed events, and frontmost app bundle id.

Out of scope:
- No Electron, Tauri, Rust, React, webview shell, plugin system, or complex framework.
- No full Dock Tap behavior, app launching/switching, Dock integration, preferences UI, persistence, login item, updater, analytics, signing, notarization, or installer.
- No user-editable shortcuts in M0; rules remain hardcoded and easy to inspect.

## Architecture

Build shape:
- Use a SwiftPM executable target plus a tiny script that assembles `build/DockTapProbe.app` with an `Info.plist`.
- Trade-off: this avoids large generated Xcode project churn while still giving the probe an app bundle identity for permissions. The cost is one simple packaging script.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——只用 packaged .app 验证 TCC，理由 Accessibility 信任绑定 bundle 身份而不是裸 swift run 进程 -->
- The packaged app is the only accepted runtime for permission/tap verification. Fix `CFBundleIdentifier` and `CFBundleExecutable` in `Info.plist`; do not use `swift run` as evidence that TCC behavior is correct.
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——TCC 手测必须稳定签名，理由 ad-hoc designated requirement 绑定 cdhash，重建后授权不可复用 -->
- Manual TCC validation requires a stable local code signing identity supplied to `scripts/run-probe.sh` through `DOCK_TAP_CODESIGN_IDENTITY`. Do not automatically create Keychain certificates. Ad-hoc signing is allowed only through explicit unstable fallback for launch smoke tests, not Accessibility/TCC acceptance.

App shell:
- `AppDelegate` owns lifecycle, status item, log window, permission gate, and event tap controller.
- The app should run as an accessory/menu-bar app. The log window can be shown from the status menu and should not require a Dock icon.

Permission gate:
- Check Accessibility trust on launch and trigger the system prompt when not trusted.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——Accessibility 是 active consume 主权限，理由 Input Monitoring/listen access 不能证明吞键路径 -->
- Active event consumption must be gated on Accessibility trusted access. Do not treat Input Monitoring or `CGRequestListenEventAccess` as equivalent substitutes; those are listen-only semantics and do not prove the active consume path.
- The UI/log should make three states obvious: permission missing, tap installed, tap failed.
- Do not attempt private APIs or extra permission workarounds.

Event tap:
- Install a session-level active keyboard tap at the head of the stream.
- Observe `keyDown`, `keyUp`, `flagsChanged`, and tap-disabled events.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——tap callback 禁止重 AppKit 工作，理由 active tap 超时会被系统禁用且影响输入路径 -->
- Inside the tap callback, do only modifier-state updates, pure matching, primitive-value capture needed by later logging, and the final `nil` or original-event return.
- Frontmost app lookup, log formatting, and UI updates belong on the main-thread/asynchronous path.
- The Finder-only backtick rule should use a cached frontmost bundle id maintained outside the tap callback, not call AppKit workspace APIs from the callback.
- Re-enable the tap when macOS disables it for timeout or user input.

Modifier state:
- Maintain physical key state from modifier keycodes, not only aggregate flag masks.
- Track at minimum left/right Option and enough Command/Control/Shift state to reject ambiguous extra-modifier chords.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——定义 M0 extra modifier 边界，理由首轮只拒绝会改变 chord 语义的修饰键 -->
- For M0 matching, treat Shift, Command, Control, and right Option as extra modifiers that reject a rule. Record Caps Lock and Fn when observable, but do not reject only because they are active unless implementation proves they alter the relevant physical keycode behavior.
- Resync from `CGEventSource` key state on ordinary key events to recover from missed `flagsChanged` events.

Rule matcher:
- Match only `keyDown` events.
- Global rules: left Option down, right Option up, no Shift/Command/Control extra modifier active, and physical digit keycodes for `1..9,0`.
- Finder rule: same left Option requirements plus physical backtick keycode, and frontmost bundle id exactly `com.apple.finder`.
- Keep the matcher pure enough to unit test without installing an event tap.

Logging UI:
- Keep a bounded in-memory log buffer so the window remains responsive.
- Show newest events with timestamp, event type, keycode/key label, left/right modifier snapshot, frontmost bundle id, matched rule id, and consumed/pass-through result.

## Files to create

- `Package.swift` - SwiftPM package with one executable target and focused tests; no third-party dependencies.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——固定 bundle identity，理由 TCC 验证必须锚定同一 packaged .app -->
- `Resources/Info.plist` - minimal app bundle metadata, fixed bundle id, fixed executable name, accessory-app setting, and display name.
- `scripts/run-probe.sh` - build the executable, assemble `build/DockTapProbe.app`, and launch it.
- `Sources/DockTapProbe/main.swift` - AppKit bootstrap only.
- `Sources/DockTapProbe/AppDelegate.swift` - app lifecycle, status menu, window ownership, and controller wiring.
- `Sources/DockTapProbe/PermissionGate.swift` - Accessibility trust check and prompt trigger.
- `Sources/DockTapProbe/EventTapController.swift` - tap creation, enable/disable, callback bridge, and tap-disabled recovery.
- `Sources/DockTapProbe/ModifierState.swift` - physical modifier state machine and resync behavior.
- `Sources/DockTapProbe/RuleMatcher.swift` - hardcoded M0 rules and match result model.
- `Sources/DockTapProbe/ActiveAppProvider.swift` - frontmost bundle id lookup via AppKit workspace APIs.
- `Sources/DockTapProbe/LogStore.swift` - bounded log model and main-thread update surface.
- `Sources/DockTapProbe/LogWindowController.swift` - simple AppKit log window.
- `Tests/DockTapProbeTests/ModifierStateTests.swift` - pure tests for left/right modifier transitions and resync assumptions.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——测试 extra modifier 定义，理由 executor 需锁住首轮 reject 边界 -->
- `Tests/DockTapProbeTests/RuleMatcherTests.swift` - pure tests for global digit rules, Finder backtick rule, right Option/Shift/Command/Control rejection, and Caps Lock/Fn record-only behavior when observable.

## Implementation steps

1. Create the SwiftPM skeleton and app-bundle run script.
2. Add the AppKit accessory app bootstrap, status item, Quit action, and Show Logs action.
3. Add the bounded log store and simple log window before wiring global input, so permission/tap status is visible immediately.
4. Add the Accessibility permission gate and status reporting.
5. Add the active `CGEventTap` controller with explicit install, enable, disable, failure logging, and timeout recovery.
6. Add the physical modifier state machine and keycode constants in one place.
7. Add the hardcoded M0 rule matcher and unit tests for its pure behavior.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——前台 app 缓存放在 tap callback 外，理由 Finder 规则需要 bundle id 但不能在 callback 做重查询 -->
8. Maintain a main-thread frontmost-app cache via workspace notifications or periodic refresh, then pass the cached bundle id into matching.
9. Wire event tap callbacks to modifier tracking, pure matching, consumption, and lightweight event summaries for asynchronous logging.
10. Keep all product-like behavior out of M0; if a feature is not needed to prove the input engine, leave it out.

## Verification

Automated:
- Run `swift test`.
- Run `swift build`.
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——验收 packaged .app 而非 swift run，理由 TCC 行为需按真实 bundle 身份验证 -->
- Run `DOCK_TAP_CODESIGN_IDENTITY="<local signing identity>" scripts/run-probe.sh` and confirm `build/DockTapProbe.app` launches with the fixed bundle id and a non-cdhash-only designated requirement. Do not use `swift run` or ad-hoc fallback for TCC/tap acceptance.

Manual:
- On first launch without Accessibility permission, confirm the app logs missing permission and opens the system prompt.
- After granting permission and relaunching, confirm the tap installs and logs an active state.
<!-- 修订v2: lead 拍板（应 Reviewer B-1）——增加文本框吞键验收，理由 M0 必须证明 active tap 命中会消费事件且非命中不会误吞 -->
- In TextEdit, Notes, or any ordinary text field, press `leftOption+1`; confirm the probe logs the expected global rule as `consumed` and no character is inserted into the text field.
- In the same text field, press `rightOption+1`; confirm no rule match, no consumed event, and the system's normal behavior reaches the focused app.
- In the same text field, press a non-matching combination such as `leftOption+shift+1`; confirm the probe rejects it and the focused app receives the system's normal behavior.
- Press `leftOption+9` and `leftOption+0`; confirm each logs the expected global rule and `consumed`.
- With Finder frontmost, press `leftOption+backtick`; confirm the Finder-only rule logs with bundle id `com.apple.finder` and `consumed`.
- With another app frontmost, press `leftOption+backtick`; confirm it does not match the Finder rule.
- Use the status menu Quit action and confirm the process exits cleanly.

## Risks

- macOS permission behavior differs by launch path; executor should verify the packaged `.app`, not only `swift run`.
- Accessibility/TCC trust is tied to the app's signing requirement. Ad-hoc signing is cdhash-only and may invalidate authorization on each rebuild; use a stable local signing identity for manual M0 validation.
- Keyboard labels vary by layout; M0 should match physical keycodes for digits and backtick, not localized characters.
- Secure Input contexts may suppress or limit keyboard taps; log tap failures clearly instead of treating them as matcher bugs.
- Missed `flagsChanged` events can leave stale modifier state; the state machine must resync from hardware key state on normal key events.
- Active taps can be disabled by macOS on timeout; callback work must stay minimal and recovery must be logged.
