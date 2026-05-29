<!-- 修订v1: 创建——Lead 指派 Closed-Lid Keep Awake，落地菜单控制 disablesleep + privileged helper 的实现 plan -->
# Closed-Lid Keep Awake Plan

## Context

Dock Tap is currently a SwiftPM macOS 13+ menu bar app with one executable target, manual app-bundle packaging, Sparkle release scripts, Accessibility permission handling, and `SMAppService.mainApp` usage for launch-at-login. There is no helper target today.

The product goal is a simple menu-controlled `Closed-Lid Keep Awake` feature backed by `pmset disablesleep`: `Enable for 1 Hour`, `Enable Indefinitely`, and `Stop Now`. The user explicitly does not want battery or thermal detection in this version.

The technical proof already exists: `scripts/lid-battery-test.sh` was added in commits `e68ddee` and `f4055f8`, and testing confirmed that `sudo pmset -a disablesleep 1` kept a heartbeat running with the lid closed for roughly 5 minutes. The production feature must preserve the script's most important safety behavior: always restore `pmset -a disablesleep 0` when the session ends.

<!-- 修订v2: 修正——应 Reviewer B-1/B-4/C-2，补本地 SDK 约束：精确状态名、LaunchDaemon 需 notarized /Applications、更新需重注册 -->
Apple's current macOS 13+ Service Management path is `SMAppService.daemon(plistName:)`, which registers LaunchDaemons that live inside the signed app bundle. Use that modern path for this app instead of adding a deprecated `SMJobBless` flow unless packaged validation proves it cannot satisfy the root-helper requirement. Local SDK check (`MacOSX.sdk/System/Library/Frameworks/ServiceManagement.framework/Headers/SMAppService.h`) says LaunchDaemons contained in apps must be notarized, are recommended to live in `/Applications` for boot availability, and must be re-registered when the daemon plist or executable changes.

## Product Decisions

- Menu options are exactly:
  - `Enable for 1 Hour`
  - `Enable Indefinitely`
  - `Stop Now`
- First use shows an explanatory warning before any helper registration or `pmset` change. The warning must say this changes the Mac's normal lid-sleep behavior, can increase battery drain and heat, should only be used on a ventilated surface, and can be stopped from the Dock Tap menu.
- Store a `hasSeenClosedLidWarning` preference after the user confirms. Do not show the warning again unless the preference is reset.
- `Enable for 1 Hour` means a hard 3600-second helper-owned expiry. The app can display remaining time, but the helper owns enforcement.
- `Enable Indefinitely` means no wall-clock expiry, but still requires an active app lease. If Dock Tap quits, crashes, or stops renewing the lease, the helper restores `disablesleep 0`.
<!-- 修订v2: 修正——应 Reviewer B-2，正常退出/更新必须用 termination gate 等待 Stop Now ack 或有界超时 -->
<!-- 修订v3: 修正——应 Reviewer C-1，正常 Quit 超时不得静默退出，Sparkle update 必须等 Stop Now ack 与 disablesleep 0 确认 -->
- Normal app quit must enter a termination gate before the process exits: request Stop Now, wait for helper acknowledgement that `pmset -a disablesleep 0` was run, then return terminate-now. If helper stop times out or fails, cancel termination, keep Dock Tap running, log/show recovery guidance, and tell the user the manual recovery command is `sudo pmset -a disablesleep 0`. Force Quit / kill still relies on helper lease-loss fallback.
- Sparkle update handoff must use the same pre-update stop gate before bundle replacement. The updater path cannot rely on `applicationWillTerminate` asynchronous cleanup, and update must be blocked/cancelled unless Stop Now is acknowledged and the helper confirms `disablesleep 0` restore. There is no bounded-timeout proceed path for updates.
- While any keep-awake session is active, both `Enable for 1 Hour` and `Enable Indefinitely` are disabled. Switching modes requires `Stop Now`, then a new enable.
- No automatic re-enable on launch. If a previous crashed session is still within its lease window, the app may reconnect and display it, but it must not silently start a new keep-awake session.
- Do not preserve a user's preexisting manual `disablesleep 1` setting in this version. Dock Tap's Stop Now and safety cleanup always set `pmset -a disablesleep 0`; this trade-off keeps behavior simple and matches the requested restore rule.

## Architecture

Use a two-process split:

- Main app: owns menu UI, warning copy, persisted user acknowledgement, helper registration, XPC client connection, lease renewal, logs, and mirrored display state.
- Privileged helper: owns all privileged work, runs as a LaunchDaemon, validates its XPC client, executes only fixed `pmset` commands, records active lease state, enforces timed expiry, and restores `disablesleep 0` on Stop Now, app exit, app crash / lease loss, stale journal recovery, and helper restart.

Use `SMAppService.daemon(plistName:)` for registration because the app's minimum OS is macOS 13. The helper executable and LaunchDaemon plist should live inside `DockTap.app/Contents/Library/LaunchDaemons/` and be covered by the app's code signature. The app should treat `.requiresApproval` as a first-class state and route the user to System Settings > General > Login Items & Extensions.

Add small SwiftPM targets rather than folding all privileged logic into the main executable:

<!-- 修订v2: 修正——应 Reviewer C-3，IPC 只用 NSXPC 可桥接类型，不跨 XPC 传 raw Swift struct -->
- `DockTapClosedLidIPC`: shared Objective-C-compatible XPC protocol plus `NSSecureCoding` classes / Foundation enum wrappers used by both app and helper. Do not send raw Swift structs or Swift-only enums across NSXPC.
- `DockTapClosedLidHelperCore`: pure helper state machine, lease journal model, expiry decisions, and `pmset` command-runner abstraction. This is the primary unit-test surface.
- `DockTapClosedLidHelper`: minimal executable that starts the XPC listener, validates clients, wires timers, journal storage, and the concrete `/usr/bin/pmset` runner.

The main app should add:

- `ClosedLidKeepAwakeController`: app-side state coordinator used by `AppDelegate`; exposes a stop-before-quit/update operation that reports completion to the termination gate.
- `ClosedLidHelperClient`: thin XPC client + SMAppService registration/status wrapper.
- Menu model additions in `MenuContentModel` so menu tests stay pure.

The helper must never run shell strings or accept arbitrary command arguments. It only runs `/usr/bin/pmset -a disablesleep 1` and `/usr/bin/pmset -a disablesleep 0` through a fixed command runner.

## Privileged Helper and Authorization

<!-- 修订v2: 修正——应 Reviewer B-1/B-4，使用精确 SMAppService.Status 名称并要求 helper 变更时重注册 -->
Register the helper lazily: first enable request shows the warning, then checks/registers the daemon, then connects over XPC. Do not prompt for helper approval at app launch.

Use exact `SMAppService.Status` cases from the local SDK:

- `.notRegistered` - service has not been registered or was unregistered.
- `.enabled` - service was registered and is eligible to run.
- `.requiresApproval` - service was registered, but the user/admin must approve it in System Settings; the SDK also says denied execution reports this status.
- `.notFound` - no such service could be found.

Registration flow:

- If status is `.enabled`, first verify the registered helper generation matches the bundled plist/executable generation. `.enabled` alone is not enough after an app update.
- If status is `.enabled` and the helper generation matches, connect and send the start request.
- If status is `.notRegistered`, call `register()` and then re-check status.
- If status is `.requiresApproval`, show a concise alert and offer to open System Settings with `SMAppService.openSystemSettingsLoginItems()`.
- If status is `.notFound`, log a packaging/registration error and show an error status row.
- If `register()` returns `kSMErrorLaunchDeniedByUser` or another denied-approval result, map it to the same `requiresApproval` UX, not a generic disabled/error state. Other register errors become an error status row.
- If the bundled helper plist or executable changes between app versions, call `unregister` then `register` before attempting to use the daemon. The local SDK says LaunchAgent/LaunchDaemon plist or executable updates require re-registration, and recommends unregister before re-register when the executable changed.

XPC and authorization requirements:

- Use a privileged Mach service name under the app namespace, e.g. `ai.resopod.docktap.closedlidhelper.xpc`.
- The LaunchDaemon label and plist filename should also stay under `ai.resopod.docktap`.
<!-- 修订v2: 修正——应 Reviewer C-1，client PID 只作诊断，授权基于 audit token / SecCode requirement -->
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——用公开 NSXPC code-signing requirement API，理由 本地 macOS 13+ SDK 暴露 listener/client 双向 set*CodeSigningRequirement -->
- The helper's `NSXPCListener` must reject clients that do not match Dock Tap's expected signing requirement using the public macOS 13+ API `NSXPCListener.setConnectionCodeSigningRequirement(_:)`. The app-side `NSXPCConnection` should also call `setCodeSigningRequirement(_:)` for the helper connection. The requirement string must be strict enough to bind Team ID plus Dock Tap bundle identity / designated requirement. `processIdentifier` and `effectiveUserIdentifier` are diagnostics only and must not authorize privileged work. Do not require a non-public audit-token property or a manual `SecCode` path; only add a lower-level validation path if executor finds a public SDK API that is necessary beyond the NSXPC requirement API.
- Do not store admin credentials, do not call `sudo`, do not use `AuthorizationExecuteWithPrivileges`, and do not expose a general command execution endpoint.
- Keep the helper protocol narrow: `start(durationSeconds: NSNumber?, completion)`, `renewLease(tokenString, completion)`, `stop(tokenString, reasonString, completion)`, and `status(completion)`. Method arguments and return payloads must be primitives, `NSString`/`NSNumber`/`NSDate`/`NSData`, or `NSSecureCoding` Objective-C classes. Response classes should include explicit outcomes such as success, `alreadyActive`, requires approval, and restore failure. Client PID diagnostics may come from public `NSXPCConnection.processIdentifier`; they must not be supplied by the client and must not affect authorization.

Packaging implications:

- Build the helper for the same architecture as the app.
- Copy the helper binary and LaunchDaemon plist into `Contents/Library/LaunchDaemons`.
- Sign the helper before signing the containing app.
<!-- 修订v2: 修正——应 Reviewer C-2，真实 LaunchDaemon 验证必须用 notarized /Applications app -->
- Verify the final app and DMG signatures include the helper and that notarization accepts the embedded daemon. A `--skip-notarize --zip` build may validate bundle layout and signing order only; real SMAppService LaunchDaemon registration/approval behavior must be tested with a notarized app placed in `/Applications`.

## Menu UX

Add a top-level submenu named `Closed-Lid Keep Awake` near the existing feature toggles, before launch-at-login and update items.

Inside the submenu:

- Disabled status row:
  - `Off`
  - `On until <time>` for the 1-hour mode
  - `On indefinitely`
  - `Helper approval required`
  - `Error: <short reason>` when the latest helper operation failed
- Commands:
  - `Enable for 1 Hour`
  - `Enable Indefinitely`
  - `Stop Now`

State rules:

- `Enable for 1 Hour` is checked when the active helper mode is timed.
- `Enable Indefinitely` is checked when the active helper mode is indefinite.
- `Stop Now` is enabled only when the helper reports an active session or the app has a pending active state.
- Enable commands are disabled while a start / stop request is in flight.
<!-- 修订v3: 修正——应 Reviewer C-2，active session 下禁止直接切换模式 -->
- Enable commands are also disabled while any timed or indefinite session is active. The menu must not offer direct mode switching; the user must Stop Now first, then start the other mode.
- If helper approval is required, include an `Open Login Items Settings...` command in the submenu.

First-use warning:

- Use `NSAlert` from the main app, not a helper prompt.
- `Cancel` leaves helper registration and `pmset` untouched.
- `Continue` stores the acknowledgement and proceeds with the requested enable action.

Localization:

- Add English and Simplified Chinese strings for all menu rows, warning title/body/buttons, helper approval text, and failure text.
- Keep technical `pmset disablesleep` wording visible in the warning so the user understands this is a system power-setting change.

## State Model and Lease

Helper is the source of truth. The app displays a mirror.

Suggested app states:

- `off`
- `starting`
- `activeTimed(endDate)`
- `activeIndefinite`
- `stopping`
- `requiresApproval`
- `error(message)`
<!-- 修订v3: 修正——应 Reviewer C-1，stop 失败要保持 app 可操作并显示恢复错误 -->
- `stopFailed(message)` for stop/restore timeout or failure during Quit/update; menu remains available and shows manual recovery guidance.

Suggested helper state:

- No active lease.
- Pending enable journal entry, written before running `pmset -a disablesleep 1`.
- Active lease with:
  - opaque token
  - mode: timed or indefinite
  - optional hard expiry date
  - lease deadline
  - client PID for logging / diagnostics
  - last renewal date

Lease behavior:

- App renews every 30 seconds while active.
- Helper lease TTL is 90 seconds. If renewals stop, helper runs `pmset -a disablesleep 0` and clears its active journal.
- Timed expiry always wins: the 1-hour session stops at its hard expiry even if renewals continue.
- Stop Now clears the active journal after `pmset -a disablesleep 0` succeeds, and records/logs failure if restore fails.
<!-- 修订v3: 修正——应 Reviewer C-2，helper active 时拒绝新的 start 且不改变现有 lease -->
- Helper `start` must reject requests while any active session exists with an `alreadyActive` response. It must leave the existing lease, expiry, and journal unchanged. The app should normally prevent this by disabling enable commands while active, but helper enforcement is required.
<!-- 修订v2: 修正——应 Reviewer B-2/B-3，明确 termination gate 与 journal 写入顺序/恢复规则 -->
<!-- 修订v3: 修正——应 Reviewer C-1，Quit/update gate 不再超时后继续 -->
- On normal app termination, `applicationShouldTerminate` or an equivalent termination gate returns `NSTerminateLater`, asks the controller to Stop Now, then calls `reply(toApplicationShouldTerminate: true)` only after the helper acknowledges Stop Now and confirms `pmset -a disablesleep 0` restore. If stop times out or fails, call `reply(...: false)`, keep the app running, log/show recovery error, and show the manual `sudo pmset -a disablesleep 0` command. `applicationWillTerminate` is only a final cleanup hook and cannot be the primary restore path.
- Sparkle pre-update handling must call the same stop gate before allowing the updater to replace the app bundle. If Stop Now is not acknowledged and `disablesleep 0` is not confirmed, cancel/block the update; do not proceed after a timeout.
- On start, the helper first writes a durable pending-enable journal with token, mode, requested expiry, lease deadline, and client diagnostics. It then runs fixed `pmset -a disablesleep 1`. Only after `pmset 1` succeeds does it atomically mark the journal active.
- If `pmset 1` fails, the helper runs fixed `pmset -a disablesleep 0` as a cleanup attempt, clears the pending journal, and returns failure.
- On helper launch / restart, read the journal. A pending-enable journal must restore `pmset -a disablesleep 0` and clear itself, because the helper cannot prove where the previous process crashed. An active journal may resume timers only if the hard expiry and lease deadline are still valid and the journal can be trusted; otherwise it must restore `pmset 0` immediately.
- Configure launchd so the helper is available to perform restart cleanup. The helper should be idle when no session is active.

Journal trade-off:

- Persisting a tiny root-owned helper journal is extra machinery, but it closes the helper-crash gap. The key invariant is write-before-side-effect: there must be a durable record before `pmset 1`, and restart recovery must bias toward restoring `pmset 0` unless a still-valid active lease can be proven.

## Files to Change

Zone A - Package, bundle, signing:

- `Package.swift` - add `DockTapClosedLidIPC`, `DockTapClosedLidHelperCore`, and `DockTapClosedLidHelper` targets; add needed dependencies from app/helper/tests.
- `Resources/LaunchDaemons/ai.resopod.docktap.closedlidhelper.plist` - new SMAppService LaunchDaemon plist with label, bundle-relative helper executable, MachServices, and restart behavior.
- `scripts/package-mac.sh` - build helper, copy daemon assets into the app bundle, sign helper bottom-up before signing the app, and verify the embedded plist exists.
- `scripts/release.sh` - change only if it hard-codes artifact assumptions not covered by `package-mac.sh`.

<!-- 修订v2: 修正——应 Reviewer C-1/C-3，文件职责补充 NSXPC 类型与 audit-token 授权边界 -->
<!-- 修订v3: lead 拍板（应 Reviewer B-1）——授权文件职责改为公开 NSXPC signing requirement API -->
Zone B - Shared IPC and helper:

- `Sources/DockTapClosedLidIPC/...` - shared XPC protocol and simple request/status `NSSecureCoding` classes / Foundation-backed enums. No raw Swift structs or Swift-only enums across XPC.
- `Sources/DockTapClosedLidHelperCore/...` - lease state machine, journal model, fixed `pmset` command runner abstraction, expiry logic.
- `Sources/DockTapClosedLidHelper/main.swift` - XPC listener bootstrap.
- `Sources/DockTapClosedLidHelper/ClosedLidHelperService.swift` - protocol implementation that calls core state and command runner.
- `Sources/DockTapClosedLidHelper/ClientCodeSigningRequirement.swift` - constructs the strict requirement string used by `NSXPCListener.setConnectionCodeSigningRequirement(_:)`; process ID and effective user ID are logs/diagnostics only.
- `Sources/DockTapClosedLidHelper/LaunchDaemonLogger.swift` or equivalent - small logging adapter.

Zone C - Main app integration:

- `Sources/DockTap/ClosedLidKeepAwakeController.swift` - app-side state, lease timer, warning gating, start/stop orchestration.
- `Sources/DockTap/ClosedLidHelperClient.swift` - SMAppService status/register/open-settings, app-side `NSXPCConnection.setCodeSigningRequirement(_:)`, and XPC calls.
<!-- 修订v2: 修正——应 Reviewer B-2，AppDelegate 需实现退出/更新前 stop gate -->
- `Sources/DockTap/AppDelegate.swift` - instantiate controller, route menu actions, rebuild menu on state changes, implement `applicationShouldTerminate` / equivalent stop gate for Quit and Sparkle update handoff.
- `Sources/DockTap/UpdateController.swift` - route Sparkle update installation through the same stop-before-update gate before allowing bundle replacement.
- `Sources/DockTap/MenuContentModel.swift` - add closed-lid submenu model rows and status.
- `Sources/DockTap/AppText.swift` - add all feature strings.
- `Sources/DockTap/SettingsStore.swift` - add first-use warning acknowledgement.
- `Sources/DockTap/LogStore.swift` - no structural change expected, but add logs from controller/helper-client call sites.

Zone D - Tests and docs:

- `Tests/DockTapTests/ClosedLidKeepAwakeControllerTests.swift` - fake helper client, warning acknowledgement, start/stop state transitions, renewal timer decisions.
- `Tests/DockTapTests/ClosedLidHelperCoreTests.swift` - pure helper lease expiry, timed expiry, Stop Now, journal recovery, command-runner calls.
- `Tests/DockTapTests/MenuContentModelTests.swift` - submenu rows, checked states, helper approval and error states.
- `Tests/DockTapTests/SettingsStoreTests.swift` - warning acknowledgement persistence.
- `Tests/DockTapTests/AppTextTests.swift` - new localized string accessors.
- `README.md` - document the feature, warning, helper approval, battery/heat caveat, and Stop Now behavior.
- `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings` - localized user-facing copy.

## Implementation Steps

<!-- 修订v2: 修正——应 Reviewer B-3/B-4，实施顺序加入 journal write-before-side-effect 与 helper 变更重注册 -->
1. Add the package targets and empty bundle asset path first, then update packaging so a signed app can carry the helper and LaunchDaemon plist.
2. Add a helper generation/version marker that changes when the LaunchDaemon plist or helper executable changes; use it to decide whether `.enabled` can be reused or needs unregister/re-register.
3. Implement `DockTapClosedLidHelperCore` with a fake command runner and journal abstraction. Unit-test every restore path before wiring real XPC, including pending-enable crash windows.
<!-- 修订v3: 修正——应 Reviewer B-1/C-1/C-2，实施步骤改为公开 code-signing requirement、严格 stop gate、active start reject -->
4. Implement the helper executable: XPC listener with `setConnectionCodeSigningRequirement(_:)`, concrete `/usr/bin/pmset` runner, active-session `alreadyActive` rejection, timers, journal load/save/clear, and launchd-friendly idle behavior.
5. Implement `ClosedLidHelperClient` in the main app: exact daemon status handling, registration, unregister/re-register when helper generation changed, settings routing, XPC connection, retry/invalidated handling.
6. Implement `ClosedLidKeepAwakeController`: first-use warning gate, menu action handlers, mirrored state, active-session enable disabling, lease renewal timer, stop-before-termination/update gate that cancels on stop failure, and logging.
7. Extend menu model, app delegate wiring, strings, settings tests, and README.
8. Run unit tests and then packaged-app manual tests on a clean user account or clean machine where the LaunchDaemon has not already been approved.

## Test Plan

Automated tests:

- `swift test`
- Verify menu rows for off, timed, indefinite, requires-approval, busy, and error states.
- Verify first-use warning acknowledgement defaults to false and persists true.
- Verify controller sends `start(3600)` for `Enable for 1 Hour`, `start(nil)` for `Enable Indefinitely`, and `stop` for Stop Now / app termination.
- Verify controller/menu disables both enable commands while any active timed or indefinite session exists, and re-enables them only after Stop Now completes.
- Verify the app renewal loop stops when helper reports inactive or an error.
- Verify helper core calls fixed `pmset 1` on start and fixed `pmset 0` on timed expiry, Stop Now, stale lease, stale journal, and restart cleanup.
- Verify timed expiry wins over lease renewal.
- Verify journal recovery resumes a still-valid active lease and restores immediately for a stale lease.
<!-- 修订v2: 修正——应 Reviewer B-1/B-2/B-3/B-4/C-1/C-3，测试覆盖 status、termination gate、journal crash window、重注册和授权/IPC -->
<!-- 修订v3: 修正——应 Reviewer B-1/C-1/C-2，测试改为 public NSXPC signing requirement、stop gate cancel、alreadyActive -->
- Verify pending-enable journal is written before the fake command runner receives `pmset 1`.
- Verify crash-window recovery: journal exists before `pmset 1`, after `pmset 1` but before active mark, and after active mark. The first two must restore `pmset 0`; the last may resume only with valid lease/expiry proof.
- Verify helper `start` returns `alreadyActive` when a lease is active and leaves the existing lease/journal unchanged.
- Verify Stop Now is requested through the termination gate. Normal Quit must cancel/keep app running on stop timeout or failure; Sparkle update must be blocked/cancelled unless helper acknowledges Stop Now and confirms `disablesleep 0`.
- Verify listener and client set the expected strict code-signing requirement strings with `setConnectionCodeSigningRequirement(_:)` and `setCodeSigningRequirement(_:)`. Do not require tests for a non-public audit-token property. PID, effective UID, claimed bundle id, or claimed app path alone must not pass authorization logic.
- Verify IPC payload classes conform to `NSSecureCoding` and NSXPC interface allowed classes are explicit.
- Verify `.notRegistered`, `.enabled`, `.requiresApproval`, and `.notFound` map to the intended menu/controller states.
- Verify `kSMErrorLaunchDeniedByUser` maps to requires-approval UX.
- Verify helper generation mismatch triggers unregister/re-register even when status is `.enabled`.

Manual packaged-app tests:

<!-- 修订v2: 修正——应 Reviewer C-2，真实 daemon approval 只能用 notarized /Applications build 验证 -->
- Build a signed local package with `scripts/package-mac.sh --skip-notarize --zip` only to validate bundle layout, helper copy location, and signing order.
- For real helper registration/approval tests, build a notarized app/DMG, install `DockTap.app` into `/Applications`, then launch it from that location.
- From the notarized `/Applications` app, choose `Enable for 1 Hour`, confirm the first-use warning, approve the background helper if macOS requires it, and verify the menu state changes.
- Check `pmset -g custom` after enabling and after Stop Now; expected transitions are `disablesleep 1` then `disablesleep 0`.
- Enable indefinitely, then use Dock Tap's Quit menu item. Verify normal quit proceeds only after helper confirms `disablesleep 0`.
- Simulate helper stop timeout/failure during Quit. Verify Dock Tap remains running and shows/logs manual recovery guidance with `sudo pmset -a disablesleep 0`.
- Enable indefinitely, trigger a Sparkle update flow or a simulated pre-update hook, and verify the same stop gate restores `disablesleep 0` before bundle replacement proceeds. Simulate stop timeout/failure and verify update is cancelled/blocked.
- Enable indefinitely, then kill the main app process. Verify the helper restores `disablesleep 0` within the 90-second lease TTL.
- Enable, kill the helper process, and verify launchd restarts it and journal recovery either resumes a valid lease or restores on stale lease.
- Repeat the existing closed-lid heartbeat test with the app feature enabled for 3 to 5 minutes, then Stop Now and verify normal sleep behavior is restored.
- Test helper approval disabled in System Settings: menu should surface `Helper approval required` and should not attempt `pmset`.

Release verification:

- Run the normal release packaging path with notarization.
- Verify `codesign --verify --deep --strict` on the app and `spctl` assessment on the app/DMG.
- Verify Sparkle update install path stops any active session before replacing the app bundle, and blocks/cancels the update if helper restore is not confirmed.
- Verify upgrading from a build with an older helper plist/executable unregisters/re-registers the daemon before use.

## Packaging and Release Risks

<!-- 修订v2: 修正——应 Reviewer B-1/B-2/B-4/C-2，发布风险补充 status、notarized 安装位置、更新重注册和退出门槛 -->
- SMAppService daemon approval is user-visible in System Settings. If status is `.requiresApproval` or `register()` returns `kSMErrorLaunchDeniedByUser`, Dock Tap must surface approval-required UX and must not claim the feature is active.
- The helper and LaunchDaemon plist live inside the signed app bundle; any packaging omission breaks registration. The package script needs explicit existence checks.
- Real LaunchDaemon behavior requires a notarized app in `/Applications`; debug zips are insufficient for approval/register validation.
- Sparkle updates can replace the app bundle while a keep-awake session is active. The pre-update stop gate must restore `disablesleep 0` before update handoff; if restore is not confirmed, the update must be cancelled/blocked.
- Helper plist/executable updates require SMAppService re-registration. Treat `.enabled` as "registered" only after the helper generation check passes.
- A user may move or delete the app after approving the helper. On next launch, re-check service status and re-register if needed; do not assume the previous registration still points at the current bundle.
- LaunchDaemon display names in Login Items may expose the helper label. Keep labels understandable and product-scoped.
- `pmset -a disablesleep` is a machine-wide setting. Stop Now intentionally resets it to `0`, even if another tool or the user set it to `1`.
- Manual testing requires admin-capable approval and may modify real sleep behavior. Every manual test must end by verifying `pmset -g custom` shows `disablesleep 0`.

## Open Questions

None blocking for executor. Lead/user decisions are already locked: no battery or thermal detection, three menu actions only, first-use warning required, and helper-enforced restore required.

<!-- 修订v2: 修正——应 Reviewer B-1/B-4/C-2，Open Question 改为 executor 校验事项而非状态名不确定 -->
Executor validation items: confirm the final LaunchDaemon plist uses SDK-supported keys, including `BundleProgram` when appropriate; confirm real daemon registration from a notarized `/Applications/DockTap.app`; confirm unregister/re-register behavior during helper updates. If those local SDK validations contradict this plan, report back to Lead before switching to `SMJobBless` or a package-installer-only design.
