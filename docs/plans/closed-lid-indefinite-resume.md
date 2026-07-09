<!-- 修订v1: lead 拍板——只规划 closed-lid Enable Indefinitely 重启恢复，理由用户目标限定为持久化用户意图而非改变 helper lease 语义 -->
<!-- 修订v4: 简化产品语义——Enable for 1 Hour 直接清除 resume intent；跨 App/Mac 重启持久化；不做额外模式系统 -->
# Closed-Lid Indefinite Resume Plan

## Context

User-facing behavior to change:

- `Enable Indefinitely` should resume after Dock Tap restarts (including Mac reboot when Launch at Login brings the app back).
- `Enable for 1 Hour` stays non-persistent and **clears** any saved indefinite resume intent (new user choice).
- Quit and Sparkle update paths must still stop the privileged helper, so normal lid sleep is restored while Dock Tap is not running.
- `Stop Now` clears the persisted indefinite intent.

Existing code shape:

- `Sources/DockTap/ClosedLidKeepAwakeController.swift`
  - `enableForOneHour()` and `enableIndefinitely()` both call `start(duration:logMode:)`.
  - `stopNow()` and lifecycle gates both flow into `stopActiveSession(reason:showFailureAlert:completion:)`.
  - `stopBeforeTermination(reason:completion:)` is used by app quit and Sparkle update.
  - `completeStop(success:message:)`, `clearActiveSession()`, `applyStatus(_:)`, and `renewLease()` are shared by user stop, lifecycle stop, status refresh, and helper expiry paths.
<!-- 修订v2: lead 拍板——persistence 必须由 start intent/source 驱动，理由 final helper session mode 无法区分用户意图 -->
  - `beginApprovalFollowUp(duration:)` currently carries only duration; the implementation must carry start intent/source through approval follow-up too.
- `Sources/DockTap/SettingsStore.swift`
  - Current durable settings include trigger preset, feature toggles, and `hasSeenClosedLidWarning`; there is no closed-lid resume intent key yet.
- `Sources/DockTap/AppDelegate.swift`
  - Launch currently calls `closedLidController.refreshStatus()`.
  - `applicationShouldTerminate(_:)` gates quit through `closedLidController.stopBeforeTermination(reason: "quit")`.
  - `updateController.stopBeforeUpdate` gates Sparkle through `stopBeforeTermination(reason: "sparkle-update")`.
<!-- 修订v3: lead 拍板（应 Reviewer C-1）——菜单必须暴露清除 resume intent 的显式入口，理由 restore 失败后 .error/.requiresApproval 当前没有 Stop Now -->
- `Sources/DockTap/MenuContentModel.swift`
  - Current `.error` menu shows status plus enable actions; `.requiresApproval` shows status plus open settings; `.off` shows enable actions. None of those states currently has a visible explicit clear path for a persisted indefinite resume intent.
- `Sources/DockTap/ClosedLidHelperClient.swift`
  - Already supports `start(duration: nil)`, `status`, `renewLease`, and `stop`.
  - `stop(token:nil, reason:)` can discover the active helper session through `status`.
- `Sources/DockTapClosedLidHelperCore/ClosedLidHelperCore.swift`
  - Helper lease/journal is intentionally liveness-based. Indefinite sessions still expire if Dock Tap stops renewing, and stale journals restore normal sleep.

Key design decision:

- Persist only the App-side user intent to restore indefinite mode. Do not make helper indefinite leases durable across App downtime. This preserves the existing safety rule that App quit/update restores normal lid sleep.
<!-- 修订v2: lead 拍板——不能用最终 active indefinite 作为写入条件，理由 timed click 也可能收到 alreadyActive(.indefinite) -->
- The persisted setting is written only from an explicit `Enable Indefinitely` start intent after that intent succeeds. A final helper response of `.activeIndefinite` or `.alreadyActive(.indefinite)` is not enough by itself.
<!-- 修订v3/v4: non-active 且 resume intent=true 时菜单暴露 Stop Now 清除入口；1 Hour 也会清 intent，幽灵状态更少 -->
- When `shouldResumeClosedLidIndefinitely == true` and closed-lid is not active, the menu exposes `Stop Now` (same clear path) so the user can drop resume without starting a session.

## Approach

1. Add a `SettingsStore` boolean for the durable user intent, named around the behavior rather than implementation details, e.g. `shouldResumeClosedLidIndefinitely`.
   - Default is `false`.
   - This is separate from `hasSeenClosedLidWarning`.

<!-- 修订v2: lead 拍板——start source 贯穿 prepare/start/alreadyActive/approval，理由写入资格来自用户动作不是 helper 最终状态 -->
2. Teach `ClosedLidKeepAwakeController` to carry an explicit start intent/source.
   - Add an internal source concept such as user timed, user indefinite, and launch restore.
   - `enableForOneHour()` starts with user timed source, **clears** the resume setting when the start actually begins, and never writes `true` (even if helper returns `alreadyActive(.indefinite)`).
   - `enableIndefinitely()` starts with user indefinite source and writes the setting `true` only after that same start intent succeeds as an indefinite session.
   - Launch restore starts with launch restore source and does not write the setting; it relies on the setting already being `true`.
   - Start failure should not create a new persistent intent.
   - Persistence branches on start source first, not on session mode alone.

<!-- 修订v2: lead 拍板——approval follow-up 必须保存 start source，理由当前只保存 duration 会丢失 indefinite intent -->
3. Replace approval follow-up's duration-only state with request state that includes both duration and start source.
   - `beginApprovalFollowUp` should receive and store the same start source used by the original start.
   - `handleApprovalFollowUp(.ready)` must call the prepared start path with both duration and source.
   - Repeated `.requiresApproval` cycles must keep the same source until the request succeeds, fails, times out, or is canceled.

4. Add a public launch-time restore entry point on `ClosedLidKeepAwakeController`.
   - If the new setting is `false`, preserve current launch behavior by refreshing helper status.
   - If the setting is `true` and the controller can start, request `start(duration: nil)` through the same prepare/start path, with launch restore source and a restore-specific log mode.
   - Reuse existing first-use warning behavior; in normal persisted cases the warning was already acknowledged before the intent was stored.
   - Do not clear the setting if restore fails, helper requires approval, status is inactive, renewal fails, or helper lease expires.

5. Wire App launch to the restore entry point.
   - Replace the launch-only `closedLidController.refreshStatus()` in `AppDelegate.applicationDidFinishLaunching(_:)` with the restore-aware method.
   - Keep `menuWillOpen(_:)` using `refreshStatus()` so menu opening remains a status reconciliation, not an implicit restart loop.

<!-- 修订v2/v4: Stop Now 与 Enable for 1 Hour 清 intent；lifecycle stop 保留 -->
6. Clear the setting from explicit user choices that leave indefinite resume:
   - `stopNow()` clears immediately and sets a suppress flag so a late start success cannot write it back.
   - `enableForOneHour()` clears when a timed start actually begins.
   - Do not clear from `completeStop`, `completeDeferredStop`, `clearActiveSession`, `applyStatus(.inactive)`, `renewLease()` inactive/expired handling, `stopBeforeTermination`, App quit, or Sparkle update.
   - Lifecycle stop restores pmset but preserves the resume intent; user stop restores pmset and clears the resume intent.

<!-- 修订v2: lead 拍板——lifecycle deferred-stop 保留原始 start intent，理由 quit/update 是安全 stop 不是用户撤销 -->
7. Preserve start intent semantics when quit/update arrives during a pending start.
   - If `stopBeforeTermination` is called while a user indefinite start is in flight, the app should still retain or write the resume intent when that start succeeds, then stop the helper for quit/update safety.
   - If `stopBeforeTermination` is called while launch restore is in flight, do not change the setting; it was already `true` if restore was attempted.
   - If the pending start was user timed, do not write the setting, even if the helper's final session is indefinite.

<!-- 修订v3: lead 拍板（应 Reviewer C-1）——菜单显示显式清除入口，理由 restore 失败/需批准后仍需用户可撤销 resume intent -->
8. Add a minimal menu/UI boundary for clearing persisted indefinite resume intent.
   - Pass the new resume-intent setting into `MenuContentModel` when building closed-lid menu rows.
   - If the setting is `true` and the state is non-active/stable, especially `.off`, `.error`, and `.requiresApproval`, include a visible command that clears the resume intent.
   - Prefer using existing `.stop` menu action so AppDelegate continues to call `stopNow()` and the controller owns the explicit clear path. If `Stop Now` reads poorly in `.off`, `.error`, or `.requiresApproval`, use a distinct title like `Disable Indefinite Resume` while still routing to the same explicit clear path.
   - In `.requiresApproval`, keep `Open Login Items Settings...` and add the clear command; approval recovery and cancellation must both be available.
   - `Enable for 1 Hour` **does** clear the resume setting (user chose timed mode).

9. Do not change helper core lease/journal behavior.
   - `ClosedLidHelperCore` should continue restoring normal sleep on stale leases and should continue requiring App renewal for indefinite mode.
   - Changing helper indefinite lease expiry would keep `pmset disablesleep 1` active while Dock Tap is not running, which conflicts with the requested quit/update safety behavior.

10. Update documentation.
   - README currently says Dock Tap does not automatically re-enable a previous session on launch. Replace that with the new narrower behavior: only previously active `Enable Indefinitely` is restored on Dock Tap launch; timed sessions are not restored; quit/update still restore normal sleep until the App starts again; `Stop Now` clears the indefinite resume intent.

## Files to Change

- `Sources/DockTap/SettingsStore.swift`
  - Add the new boolean key and computed property.

- `Sources/DockTap/ClosedLidKeepAwakeController.swift`
  - Add restore-aware launch method.
<!-- 修订v2: lead 拍板——controller 改动必须携带 start/stop source，理由异步 approval 与 deferred-stop 需要保留原始意图 -->
  - Add start-source/persistence handling so only successful user indefinite start intent stores intent.
  - Carry start source through prepare, helper start, `alreadyActive`, approval follow-up, and deferred-stop completion.
  - Add explicit user-stop cancellation semantics so `Stop Now` during `.starting` cannot be undone by a later start completion.
  - Clear the resume setting in `stopNow()` and timed start; not in shared stop completion.

- `Sources/DockTap/AppDelegate.swift`
  - Use the restore-aware launch method in `applicationDidFinishLaunching(_:)`.
  - Leave quit/update stop gates unchanged.
<!-- 修订v3: lead 拍板（应 Reviewer C-1）——AppDelegate 需把 resume intent 传入菜单模型并路由清除动作，理由 UI 清除入口依赖 settings bool -->
  - Pass `settingsStore.shouldResumeClosedLidIndefinitely` into `MenuContentModel`.
  - Route the menu clear command to the same explicit clear path as `stopNow()`.

<!-- 修订v3: lead 拍板（应 Reviewer C-1）——MenuContentModel 需渲染非 active 清除入口，理由 .error/.requiresApproval/.off 不能只有 enable/open settings -->
- `Sources/DockTap/MenuContentModel.swift`
  - Accept the resume-intent boolean in the model input.
  - When the boolean is true and closed-lid state is `.off`, `.error`, or `.requiresApproval`, include an explicit clear/stop command.

- `Tests/DockTapTests/MenuContentModelTests.swift`
  - Cover the new menu rows and unchanged false-intent behavior.

<!-- 修订v3: lead 拍板（应 Reviewer C-1）——如 Stop Now 文案不适合无 active helper，可新增文案，理由动作仍应复用显式清除路径 -->
- `Sources/DockTap/AppText.swift`
  - Only needed if executor chooses a distinct menu label such as `Disable Indefinite Resume` instead of reusing `Stop Now`.

- `Resources/en.lproj/Localizable.strings` and `Resources/zh-Hans.lproj/Localizable.strings`
  - Only needed if a new label is added through `AppText`.

- `Tests/DockTapTests/SettingsStoreTests.swift`
  - Cover default false and persistence of the new key.

- `Tests/DockTapTests/ClosedLidKeepAwakeControllerTests.swift`
  - Cover user indefinite persistence, timed non-persistence, launch restore, lifecycle stop preservation, and user stop clearing.

- `README.md`
  - Update closed-lid behavior text.

No planned changes:

- `Sources/DockTapClosedLidHelperCore/ClosedLidHelperCore.swift`
- `Sources/DockTap/ClosedLidHelperClient.swift`
- XPC protocol types

## Pitfalls to Avoid

- Do not clear the persisted setting inside any shared helper-stop completion method. `stopBeforeTermination` and `stopNow` share most of the same path; clearing in `completeStop` would make quit/update erase the resume intent.
- Do not key clearing off the stop `reason` string in the low-level stop path. Keep the ownership explicit at `stopNow()` so future lifecycle reasons cannot accidentally clear user intent.
<!-- 修订v2: lead 拍板——alreadyActive 不能作为持久化依据，理由用户 timed start 也可能收到 active indefinite session -->
- Do not persist just because helper returns an indefinite session. The caller source must be user indefinite; user timed plus `alreadyActive(.indefinite)` remains non-persistent.
- Do not let `finishDeferredStopAfterStart` write the setting after an explicit `Stop Now` canceled the pending start.
- Do not drop start source across approval follow-up. A duration-only stored request is insufficient because both user indefinite and launch restore use nil duration.
- Do not persist timed sessions or infer persistence from helper `status` alone. A status response can be lifecycle repair/adoption, not a fresh user choice.
- Do not make helper indefinite leases survive without renewal. That would leave lid sleep disabled while the App is quit or updating.
- Do not auto-restart on every menu status refresh; restore should be a launch behavior.
- Active sessions still require `Stop Now` before starting the other mode (`canStartSession` is false while active). From inactive states with resume intent set, `Enable for 1 Hour` clears intent and starts timed; `Stop Now` clears intent without starting.
- Do not hide the clear action behind helper approval. In `.requiresApproval` with resume intent, the user must be able to open settings or clear via `Stop Now`.

## Verification

Unit tests:

- `SettingsStoreTests`
  - New resume-intent setting defaults to `false`.
  - Setting persists `true` and `false` across `SettingsStore` instances.

- `ClosedLidKeepAwakeControllerTests`
  - `Enable Indefinitely` with a successful indefinite helper start stores the resume intent.
  - `Enable for 1 Hour` with a successful timed helper start does not store the resume intent.
<!-- 修订v2: lead 拍板——验证覆盖 source 优先于 helper mode，理由 alreadyActive(.indefinite) 是本次 blocker -->
  - `Enable for 1 Hour` with helper returning `alreadyActive(.indefinite)` does not store the resume intent.
  - Failed indefinite start does not store the resume intent.
  - Launch restore with the setting `true` calls helper start with nil duration and reaches `.activeIndefinite`.
  - Launch restore with the setting `true` and helper success leaves the setting unchanged rather than treating launch restore as a fresh user write.
  - Launch restore with the setting `false` preserves the existing status-refresh behavior and does not call start.
  - `stopBeforeTermination(reason: "quit")` and `stopBeforeTermination(reason: "sparkle-update")` stop the helper but leave the setting `true`.
<!-- 修订v2: lead 拍板——验证 pending-start stop 竞争，理由 Stop Now 必须赢过异步 start completion -->
  - `Stop Now` during `.starting` for a user indefinite start clears the setting and the later `finishDeferredStopAfterStart` path does not write it back.
  - `stopBeforeTermination(reason: "quit")` during `.starting` for a user indefinite start writes or preserves the setting when start succeeds, then stops the helper.
  - `stopBeforeTermination(reason: "sparkle-update")` during `.starting` for launch restore does not change the setting beyond its existing `true`.
  - `stopBeforeTermination` during `.starting` for user timed does not store the setting even if the helper later returns `.alreadyActive(.indefinite)`.
<!-- 修订v2: lead 拍板——验证 approval follow-up 携带 source，理由 duration-only 会丢 indefinite intent -->
  - Approval follow-up for user indefinite carries source through `.requiresApproval -> .ready -> start success` and then stores the resume intent.
  - Approval follow-up for launch restore carries launch source through the same path and does not perform a fresh user-intent write.
  - `stopNow()` clears the setting and still stops the current helper token.
<!-- 修订v3: lead 拍板（应 Reviewer C-1）——验证 restore failure/approval 后可见清除入口，理由 resume intent 保留时用户需要撤销路径 -->
  - Launch restore failure leaves `shouldResumeClosedLidIndefinitely == true`, moves to `.error(...)`, and the menu includes an explicit clear/stop command.
  - Launch restore requiring approval leaves `shouldResumeClosedLidIndefinitely == true`, moves to `.requiresApproval`, and the menu includes both `Open Login Items Settings...` and an explicit clear/stop command.
  - Selecting the explicit clear/stop command from `.error`, `.requiresApproval`, or `.off` clears the setting even when no active helper token is present.
  - `MenuContentModel` with resume intent `false` keeps existing `.off`, `.error`, and `.requiresApproval` rows unchanged.
  - `MenuContentModel` with resume intent `true` and `.off` includes a visible clear command in addition to enable actions.
  - Clicking `Enable for 1 Hour` while resume intent is true clears the setting.
  - Renewal/status inactive paths do not clear the setting.

Manual smoke:

- Enable indefinitely, quit Dock Tap, verify helper stop restores normal lid sleep during downtime, relaunch Dock Tap, verify closed-lid status returns to `On indefinitely`.
- Enable for 1 Hour, quit and relaunch Dock Tap, verify it does not auto-start.
- Enable indefinitely, choose `Stop Now`, quit and relaunch Dock Tap, verify it stays off.
- Force a launch restore failure or helper approval-required state, verify the menu exposes a clear resume command, use it, and verify the next launch stays off.
- Trigger Sparkle update gate while indefinite is active, verify update stop gate still runs and the next launch restores indefinite mode if the user had not chosen `Stop Now`.
