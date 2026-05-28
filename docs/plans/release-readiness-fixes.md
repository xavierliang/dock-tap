<!-- 修订v1: lead 拍板——发布前 must/should fixes 初版，理由 Lead 指定范围并锁定 UpdateController 使用 Sparkle 标准 scheduled 提示 -->
# Release Readiness Fixes

## Context

当前发布前风险集中在两类：

- **更新链路可用性**：`docs/appcast.xml` 已发布的 `sparkle:deltas` 指向 `DockTap3-2.delta`，但 GitHub Release 没有对应资产时会造成 delta 404。Sparkle 可回退到完整 DMG，但首次更新体验会变慢并产生不必要错误日志。
- **运行态 readiness 准确性**：菜单 summary、Accessibility 状态、event tap install/disable/recovery、Dock 偏好读取，以及 README 的发布说明已经落后于当前代码形态，容易让用户和发布执行者误判状态。

目标是发布前修掉这些 must/should 项，不扩大功能面，不重写 Sparkle、event tap 或 Dock parsing 架构。

## Decisions

- **Appcast 策略：短期禁用 delta，live feed 只发布完整 DMG enclosure。** 这是发布前最低风险路径：完整包体积小，避免必须上传/管理 `.delta` 资产；之后若要恢复 delta，需要先把 delta asset 上传、URL 校验和 release checklist 做完整。
<!-- 修订v2: lead 拍板（应 Reviewer B-1/B-2）——URL validation 区分正式和 dry-run 并定义 HTTP 语义，理由 vNext dry-run asset 尚不存在 -->
- **`release.sh` 需要防复发，而不只手修 `docs/appcast.xml`。** 生成 feed 后必须移除/禁止 delta。正式 release 在 GitHub Release asset 上传后校验所有 appcast enclosure URL；dry-run 不要求 vNext URL 可访问，只验证生成 XML、无 `sparkle:deltas`/`.delta`、历史 enclosure 可访问，并明确记录跳过的新版本 URL。HTTP validation follow redirects，接受 2xx；优先 HEAD，必要时 fallback 到 `GET` range `0-0`，带短重试。
- **`UpdateController` scheduled prompt 采用 Sparkle 标准提示。** `standardUserDriverShouldHandleShowingScheduledUpdate` 返回 `true`，并移除 gentle reminder 声明；Dock Tap 暂不自研后台提醒 UI。取舍：会用 Sparkle 默认 alert，而不是菜单内轻提示；优点是符合 Sparkle 标准行为，发布前更稳。
- **菜单 readiness 以 Accessibility trust 和 event tap readiness 共同决定。** `MenuContentModel` 已接收 `isEventTapReady`，但当前 summary 只看 `isAccessibilityTrusted`；需要让 trusted-but-tap-not-ready 变成明确的非 ready 状态。
<!-- 修订v2: lead 拍板（应 Reviewer B-3/C-1/C-4）——引入持续 health reconcile timer 且 disabled callback 请求重装，理由菜单必须以真实 tap ready 为准 -->
- **tap 状态由 `EventTapController` 暴露可查询 truth，`AppDelegate` 负责持续 reconcile。** 不再把 `didInstallTap` 当成长期 truth；它只能是 AppDelegate 本地缓存或被删除。App 生命周期内运行 health reconcile timer（例如 5s/10s，具体间隔由 executor 按现有风格定），每次重新读 Accessibility trust 和 `EventTapController.isReady`：trusted 且 not ready 时重装，not trusted 时 stop/mark not ready，状态变化就 rebuild menu。tap disabled callback 先标记 recovering/not ready 并请求 main-thread reconcile/reinstall；不要求检测 `CGEvent.tapEnable` 的返回值。
- **Dock preferences 读取前调用 synchronize。** `DockPreferencesReader.readCurrentDockApps` 在 `CFPreferencesCopyAppValue` 前同步 `com.apple.dock`，优先保证菜单打开/手动刷新能看到最新 Dock 持久项；代价是每次读取多一次系统偏好同步，但触发频率低。
- **README 必须反映当前发布能力。** 已有 Sparkle updater、notarized DMG、Window Snap 说明，但 Known Limits 仍写“不 notarize、不 install updater”，需要改成实际安装/更新/限制说明。

## File-zone split

### Zone A: Release feed and script

- `docs/appcast.xml`
  - 删除当前 `sparkle:deltas` 块，保留 `0.3.0` 和历史完整 DMG item。
  - 确认每个完整 DMG enclosure URL 对应 GitHub Release asset。
- `scripts/release.sh`
  - 调用 `generate_appcast` 时显式加 `--maximum-deltas 0`，避免历史 DMG 进入 staging 后自动生成 delta。
<!-- 修订v2: lead 拍板（应 Reviewer B-1/B-2）——正式校验所有 enclosure、dry-run 跳过 vNext URL，理由 dry-run 不会先上传新 asset -->
  - 生成后增加 appcast URL validation：解析所有 `enclosure url`。正式 release 必须在 `gh release create` 上传 DMG 后校验所有 URL；dry-run 只校验历史 URL，对新版本 URL 打印“skipped in dry-run”。
  - validation follow redirects，接受 2xx；优先 HEAD，HEAD 不支持或异常时 fallback 到 `GET` range `0-0`；使用短重试处理 GitHub asset 刚上传后的可见性延迟。
  - validation 失败时打印坏 URL、HTTP 状态和人工恢复步骤，并终止在 `git add/commit/push docs/appcast.xml` 之前；不承诺全自动回滚已创建的 GitHub Release 或已上传资产。
  - 保留 per-version DMG URL rewrite，因为完整 DMG item 仍需要各自 tag 路径。
  - Dry-run 也应执行 feed 生成与本地 shape validation：XML 存在、可解析、无 `sparkle:deltas`、无 `.delta` enclosure。

### Zone B: Sparkle scheduled update prompt

- `Sources/DockTap/UpdateController.swift`
  - `standardUserDriverShouldHandleShowingScheduledUpdate(... )` 返回 `true`。
  - 移除 `supportsGentleScheduledUpdateReminders` override，避免声明支持但不实现 gentle reminder。
  - 保留 menu-driven `checkForUpdates()` 与 `availableUpdateVersion` 更新逻辑。

### Zone C: Menu readiness model

- `Sources/DockTap/MenuContentModel.swift`
  - `statusTitle` 同时考虑 `isAccessibilityTrusted` 和 `isEventTapReady`。
  - Missing Accessibility 仍优先显示；trusted 但 tap 未 ready 时显示明确 starting/not ready copy。
  - Summary 不加入诊断细节，保持短。
- `Sources/DockTap/AppText.swift`
  - 增加或复用 tap-not-ready 状态文案。
- `Tests/DockTapTests/MenuContentModelTests.swift`
  - 更新现有 trusted-but-tap-not-ready 测试，不再期待 `Ready`。
  - 增加 Accessibility trusted/tap false、Accessibility false/tap false、both true 的优先级覆盖。

### Zone D: Tap health and permission reconcile

- `Sources/DockTap/EventTapController.swift`
  - 暴露线程安全只读状态，例如 event tap 是否 installed/running，必要时区分 installing。
<!-- 修订v2: lead 拍板（应 Reviewer C-1/C-4）——disabled callback 标记 not ready 并交给 reconcile 重装，理由不依赖 CGEvent.tapEnable 返回值 -->
  - 在 tap thread 退出、install 失败、stop、tap disabled recovery 后，能让 AppDelegate 得到状态变化通知，或提供 AppDelegate 可轮询的 health truth。
  - `scheduleTapRecovery` 不只写日志：disabled callback 应先把状态标记为 recovering/not ready，并请求 main-thread reconcile/reinstall。不要要求检测 `CGEvent.tapEnable` 返回值；菜单最终以 `isReady` truth 为准。
- `Sources/DockTap/AppDelegate.swift`
<!-- 修订v2: lead 拍板（应 Reviewer B-3/C-4）——reconcile timer 生命周期内持续运行，理由 tap health 可能在已授权后丢失 -->
  - 把 `checkPermission(prompt:)` 改成“读取权限 -> reconcile tap -> rebuild menu”的单一路径，或提取同等的 `reconcilePermissionAndTapHealth` helper。
  - 启动一个持续 health reconcile timer，在 App 生命周期内运行，而不是只在 missing permission 时运行。间隔可选 5s/10s，executor 按现有 timer 风格定。
  - 每次 reconcile 都重新读取 AX trust 和 `EventTapController.isReady`。
  - Accessibility 不 trusted 时，stop tap、标记 not ready，并保留下一轮 timer recheck。
  - Accessibility trusted 时，如果 tap 不 running，则更新 slot snapshot 后尝试 install；成功和失败都刷新菜单。
  - install 失败保持 not ready，timer 后续继续 retry；不能因为旧 `didInstallTap` 为 true 就跳过真实 health 检查。
  - `rebuildMenu()` 传入 `eventTapController` 的真实 readiness，而不是旧布尔值。
- Tests
<!-- 修订v2: lead 拍板（应 Reviewer B-3）——新增纯 helper/model 覆盖三类 reconcile 转换，理由 AppDelegate/CGEventTap 不适合硬测 -->
  - 若当前 AppDelegate 不易单测，优先新增小型纯 Swift helper/model 来覆盖 reconcile 状态转换；不要为了测试强行大改 AppDelegate。
  - helper/model 必须机械覆盖：ready 后 tap lost -> not ready + reinstall requested；permission revoked -> stop/not ready；install failure -> not ready + retry retained。
  - EventTapController 的 CGEventTap 创建仍以手动 smoke 验证为主，单测只覆盖可纯化的状态汇总/菜单输出。

### Zone E: Dock preferences synchronization

- `Sources/DockTap/DockPreferencesReader.swift`
  - 在 `CFPreferencesCopyAppValue("persistent-apps", "com.apple.dock")` 前调用 `CFPreferencesAppSynchronize("com.apple.dock")`。
  - 不改变 parser 对 malformed tiles、missing apps、limit 的行为。
- `Tests/DockTapTests/DockPreferencesReaderTests.swift`
  - 现有 parser tests 不需要依赖 real preferences。
  - 如为 synchronize 增加测试，先引入轻量注入 seam；不要让 CI 读写真实 Dock preferences。

### Zone F: README and release notes truth

- `README.md`
  - Install/Usage 中说明 notarized DMG + Sparkle updater 的实际用户路径。
  - Menu 或 Update section 说明 `Check for Updates...` 和后台 scheduled prompt。
  - Known Limits 删除“不 notarize releases / install updater”，改为真实限制：arm64-only、macOS 13+、read-only Dock slots、Window Snap 非 Rectangle 替代、delta updates 暂不发布。

## Implementation steps

1. **先修 live feed。** 编辑 `docs/appcast.xml` 移除 delta block，确认 XML 结构仍有效；这是可以单独发布的止血改动。
<!-- 修订v2: lead 拍板（应 Reviewer B-1/B-2/C-2/C-3）——release validation 前置到 commit appcast 前并打印人工恢复步骤，理由半发布窗口只能降风险不能全自动消除 -->
2. **加 release 防线。** 修改 `scripts/release.sh`：`generate_appcast` 传 `--maximum-deltas 0`，生成后验证 enclosure URL。正式 release 校验所有 URL；dry-run 校验历史 URL 并跳过 vNext URL。URL validation 要在 commit appcast 前执行，失败时输出所有坏 URL和人工恢复步骤。
3. **调整 Sparkle delegate。** 修改 `UpdateController`，让 scheduled update 由标准 user driver 处理；不要新增 gentle reminder UI。
4. **修菜单 readiness。** 让 `MenuContentModel` 使用 `isEventTapReady`，补文案与 tests。
<!-- 修订v2: lead 拍板（应 Reviewer B-3/C-1/C-4）——tap reconcile 由持续 timer 驱动，理由授权后 tap 仍可能丢失 -->
5. **重做 tap reconcile 的最小闭环。** 在 `EventTapController` 暴露真实 health；在 `AppDelegate` 中用持续 health timer 读取 AX trust + tap readiness，取代旧 `didInstallTap` 判定，并确保权限变化、tap disable/recovery、install failure 都会刷新菜单和保留 retry。
6. **同步 Dock preferences。** 在读取前 synchronize，保持 parser 行为不变。
7. **更新 README。** 把发布、更新、已知限制与实际代码对齐。
8. **最后统一跑测试与 release dry-run。** 先跑 unit tests，再跑 release dry-run，最后检查 appcast URL。

## Tests & release verification

- `swift test`
  - 预期覆盖 MenuContentModel、DockPreferencesReader parser、Settings/RuleMatcher 等现有单测。
- Targeted tests:
  - `swift test --filter MenuContentModelTests`
  - `swift test --filter DockPreferencesReaderTests`
<!-- 修订v2: lead 拍板（应 Reviewer B-3）——测试机械覆盖 menu 三态和 reconcile helper 三转换，理由防止 ready 状态再次漂移 -->
  - `swift test --filter <new-reconcile-helper-tests>`
- MenuContentModel tests must cover exactly these status inputs:
  - Accessibility false + tap false -> missing permission.
  - Accessibility true + tap false -> not ready/starting.
  - Accessibility true + tap true -> ready.
- Reconcile helper/model tests must cover:
  - ready 后 tap lost -> not ready + reinstall requested.
  - permission revoked -> stop/not ready.
  - install failure -> not ready + retry retained.
- Release script:
  - `scripts/release.sh <next-version> --dry-run`
  - 检查 dry-run 不创建 tag/release，不 push；验证 XML shape、无 `sparkle:deltas`/`.delta`、历史 enclosure 可访问，并明确打印跳过的新版本 URL。
- Appcast:
  - XML 中不应再出现 `sparkle:deltas` 或 `.delta` URL。
  - 所有完整 DMG enclosure URL 返回成功状态。
  - HTTP 检查 follow redirects，接受 2xx；HEAD 失败时 fallback `GET` range `0-0`，短重试后仍失败才报错。
  - `Resources/Info.plist` 的 `SUFeedURL` 仍指向 `https://xavierliang.github.io/dock-tap/appcast.xml`。
- Manual macOS smoke:
  - Fresh launch without Accessibility：菜单显示 missing permission，快捷键不被消费。
  - Grant Accessibility：tap 安装后菜单变 Ready，Dock shortcuts work。
  - Secure Input 或 tap disable 场景：日志有 tap recovery/reconcile 记录，菜单不长期误报 Ready。
  - Manual `Check for Updates...` opens Sparkle standard UI; background scheduled update path is Sparkle-controlled.

## Risks

- **Delta 禁用会增加更新下载体积。** 当前 DMG 体积小，发布前优先可靠性；后续恢复 delta 需要新增资产上传和 URL 校验。
<!-- 修订v2: lead 拍板（应 Reviewer C-2/C-3）——半发布窗口列为 remaining risk 而非承诺自动回滚，理由 release 创建和 appcast commit 无法原子化 -->
- **半发布窗口仍是 remaining risk。** `release.sh` 应尽量在 commit/push appcast 前完成 validation，失败时打印人工恢复步骤；但 GitHub Release 创建、asset 上传、appcast commit/push 不是原子事务，不承诺全自动回滚。
- **URL validation 时机可能与 GitHub Release asset 传播冲突。** 正式 release 已先创建 asset，再生成 appcast；validation 应在 GitHub API/HTTP 可见后执行，必要时短重试，但不能静默通过。
- **Event tap health 很难完全单测。** 通过纯化 reconcile 状态和手动 smoke 降低风险；不要把 CGEventTap 私有实现暴露过多只为测试。
- **`CFPreferencesAppSynchronize` 只能提高读取新鲜度，不保证 Dock 正在写入时的原子视图。** 菜单打开/手动刷新仍可能看到上一瞬间状态，但比当前不同步更可靠。
