<!-- 修订v1: lead 拍板——创建 M3 Menu Polish 计划，理由 M2 已提交且用户确认主菜单应从调试面板收敛为轻量产品菜单 -->
# M3 Menu Polish Plan

## Context

M2 commit `743b1c3` shipped daily-driver basics: formal bundle id `ai.resopod.docktap`, Launch at Login, trigger modifier presets, Dock preference refresh, and README coverage. The current menu still feels like a debug panel because it lists every Dock slot in the top-level menu and mixes status, settings, actions, and diagnostic detail in one flat surface.

M3 is a UX polish pass. It should keep the working M2 architecture intact while making the menu read as a small utility: a compact status summary, a few examples that explain the shortcut rule, a dedicated mapping view for users who need detail, and short actions with product copy.

The main trade-off is intentionally not building a full preferences UI or localization system. A tiny centralized text surface is enough now because the app has one menu, one README, and a small set of repeated labels.

## Scope & Non-goals

In scope:
- Replace the long top-level Dock slot list with a compact status row and four example rows:
  - `<preset>+1  First Dock app`
  - `<preset>+2  Second Dock app`
  - `<preset>+0  Tenth Dock app`
<!-- 修订v2: lead 拍板（应 Reviewer N-2）——Finder 只出现在顶层示例，不进入 Dock mapping，理由 mapping 子菜单应只表达 10 个 Dock shortcut slots -->
  - ``<preset>+`  Finder``
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——顶部状态使用 assigned Dock shortcut count，理由 这是可快捷 slot 数且最多 10，不应误称 app count -->
- Show top-level status as only the necessary summary: readiness or missing permission, current trigger preset, and assigned Dock shortcut count such as `9 shortcuts` or `9 Dock shortcuts`.
<!-- 修订v2: lead 拍板（应 Reviewer N-1）——固定入口名为 Show Dock Mapping，理由 executor/reviewer 需要明确 UI 目标 -->
- Move the complete 10-slot Dock shortcut mapping into a `Show Dock Mapping` submenu, including assigned and unassigned slots.
- Move trigger preset choices into a `Trigger Modifier` submenu. The top-level menu should show the current trigger value, not all choices.
- Rename `Refresh Dock` to `Update Dock Shortcuts`.
- Document that Dock shortcuts update automatically on launch and when the menu opens; the manual update command is a fallback.
- Keep Launch at Login and Accessibility rows minimal: one visible state plus the necessary action, without long diagnostic prose in the main menu.
- Add `AppText` or a similarly small central home for menu/README-reusable UI copy.
- Preserve all M2 shortcut, Dock parsing, app activation, login item, signing, and permission behavior.

Out of scope:
- No icon work, packaging, notarization, installer, Sparkle, or release channel work.
- No window cycling, window picker, or per-window switching.
- No Custom trigger modifier and no shortcut recorder.
- No full `Localizable.strings`, language switching, or broader i18n architecture.
- No Dock mutation, per-slot remapping, onboarding window, preferences window, or SwiftUI rewrite.

## Architecture

Menu shape:
- Keep `AppDelegate` as the menu owner. This is a polish pass, not a menu framework rewrite.
- Split the top-level menu into predictable groups:
<!-- 修订v2: lead 拍板（应 Reviewer C-2）——状态行 count 定义为 assigned Dock shortcut count，理由 skipped/more-than-10 不是顶层状态信息 -->
  1. One disabled summary row: `Ready` or `Missing Accessibility Permission`, current trigger preset, and assigned Dock shortcut count capped at 10. Do not show skipped count or more-than-10 detail in the top-level status row; keep those details out of the primary menu and in logs.
  2. A small examples section with only the four locked examples.
<!-- 修订v2: lead 拍板（应 Reviewer N-2）——Show Dock Mapping 只放 10 个 Dock slots，理由 Finder 是独立 shortcut 示例，不属于 Dock slot mapping -->
  3. A `Show Dock Mapping` submenu with exactly the 10 Dock shortcut rows, including assigned and unassigned slots, and no Finder row.
  4. A `Trigger Modifier` submenu with the five existing preset choices and checkmark state.
  5. Minimal operational actions: Launch at Login state/action, Accessibility action when needed, `Update Dock Shortcuts`, `Show Logs`, `Quit`.
- Keep diagnostic detail in logs and the mapping submenu, not in the primary menu. The top-level menu should not show `shortcutIndex`, `dockOrdinal`, skipped count, tap internals, or every slot.

Dock updates:
- Preserve the existing automatic refresh on app launch and `menuWillOpen`.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——只有顶层 statusMenu 的 menuWillOpen 可触发 refresh/rebuild，理由 避免子菜单打开导致重复刷新、递归 rebuild 或 stale delegate 行为 -->
- Hard invariant: only the top-level `statusMenu` may have the `NSMenuDelegate` that runs `menuWillOpen` refresh/rebuild. `Show Dock Mapping` and `Trigger Modifier` submenus must not set that same delegate and must not trigger Dock refresh or menu rebuild when opened.
- Build submenus from the current menu content snapshot produced during the top-level rebuild. Opening the top-level menu should perform one Dock refresh and one menu rebuild; opening child submenus should only reveal already-built content.
- Manual `Update Dock Shortcuts` should call the same refresh path and log reason `manual`. It is a recovery action for users who changed Dock contents and want an immediate refresh without reopening the menu.
- README should describe launch/menu-open auto update first, then manual update as fallback.

Menu content model:
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——引入轻量 pure MenuContentModel/DockMenuSummary，理由 菜单内容可测且 AppDelegate 只负责 NSMenu 渲染 -->
- Add a tiny pure `MenuContentModel`, `DockMenuSummary`, or similarly named type. Input should be current slot rows, selected preset, accessibility/tap/login statuses, and any last concise failure. Output should be render-ready summary text, example rows, 10 mapping rows, trigger submenu labels/checkmarks, and action labels.
- `AppDelegate` should render that model into `NSMenu` items and remain responsible for actions, delegates, and lifecycle wiring. Do not add broad AppKit menu tests.
- Keep this model narrow to menu content. It must not read Dock preferences, call `SMAppService`, query Accessibility, mutate settings, or log.

Text centralization:
- Add `AppText` as a small namespace/struct for user-facing labels that are reused or likely to be reused: app/status labels, example labels, menu item titles, permission text, Launch at Login title variants, and README-aligned command names.
- Do not move every log line or test-only string into `AppText`. Keep the centralization practical and avoid a pseudo-localization layer.
- Keep `TriggerModifierPreset.menuTitle` as preset metadata unless moving those labels into `AppText` makes call sites simpler. The important boundary is that menu/README copy should not be scattered through `AppDelegate`.

Launch at Login and Accessibility:
- Keep `LoginItemController` and `LoginItemMenuModel` behavior unchanged.
- Polish `LoginItemMenuModel` output so the top-level row/action is short and based on actual status. If `requiresApproval` or a failure exists, expose one concise hint/action rather than a paragraph.
- For Accessibility, show missing/trusted state and action. Use `Open Accessibility Settings` and/or `Check Accessibility` only when useful; do not add a new permission flow.

Code simplicity:
- Prefer small private menu-building helpers in `AppDelegate` over introducing a broad menu model.
- If the mapping submenu requires selection of first/second/tenth rows, add tiny helpers near existing menu row code or on `DockSlotStore` only if it reduces duplication.
- Do not alter event tap callback behavior, matcher rules, Dock parsing, app activation, or settings persistence.

## Files to change

- `Sources/DockTap/AppDelegate.swift` - rebuild menu structure: compact summary, examples, mapping submenu, trigger submenu, renamed update command, minimal permission/login rows.
- `Sources/DockTap/AppText.swift` - new small central namespace for reusable menu and README-aligned UI copy; no full localization system.
- `Sources/DockTap/MenuContentModel.swift` or `Sources/DockTap/DockMenuSummary.swift` - new small pure model for summary text, example rows, mapping rows, trigger submenu rows, and action labels.
- `Sources/DockTap/LoginItemMenuModel.swift` - adjust top-level Launch at Login titles/hints only if needed for the simpler menu.
- `Sources/DockTap/TriggerModifierPreset.swift` - keep existing preset metadata; optionally add tiny display helpers only if they remove menu duplication.
- `Sources/DockTap/DockSlotStore.swift` - optional small read helper for menu/mapping rows if `AppDelegate` would otherwise duplicate indexing logic; do not change refresh or snapshot semantics.
- `Tests/DockTapTests/LoginItemMenuModelTests.swift` - update expected copy after title/hint polish.
- `Tests/DockTapTests/TriggerModifierPresetTests.swift` - update only if preset labels/helpers change.
- `Tests/DockTapTests/MenuContentModelTests.swift` or `Tests/DockTapTests/DockMenuSummaryTests.swift` - pure tests for top-level examples, 10-row mapping, trigger checkmark state, summary count wording, and `Update Dock Shortcuts` label.
- `Tests/DockTapTests/AppTextTests.swift` - optional focused tests for central text helpers if they contain branching logic.
- `README.md` - update usage copy to describe automatic Dock shortcut updates on launch and menu open, plus the renamed `Update Dock Shortcuts` fallback action.
- `docs/plans/m3-menu-polish.md` - this plan.

## Implementation steps

1. Add the tiny `AppText` surface first, limited to user-facing menu/README-aligned labels and command names.
2. Rename the manual refresh action in code and README from `Refresh Dock` to `Update Dock Shortcuts`.
<!-- 修订v2: lead 拍板（应 Reviewer C-3）——先抽 pure model 并补轻量测试，理由 菜单内容规则不应靠手测和 AppKit 宽测兜底 -->
3. Add the small pure menu content model and tests before reshaping `AppDelegate`.
4. Rework `AppDelegate.rebuildMenu` into small rendering sections: summary, examples, `Show Dock Mapping` submenu, `Trigger Modifier` submenu, operations, logs/quit.
5. Replace the top-level 10-slot loop with four example rows using the selected preset label and generic Dock position language.
6. Add `Show Dock Mapping` as a submenu that contains exactly the 10 Dock shortcut slots with current app names/statuses and unassigned rows; do not include Finder.
7. Move preset choices under `Trigger Modifier`, with the parent item showing the current preset and child items keeping the existing checkmarks.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——子菜单只渲染当前 snapshot，理由 顶层打开后一次 rebuild 已足够且更可预测 -->
8. Ensure only the top-level `statusMenu` has `menuWillOpen` refresh/rebuild behavior. Child submenus must be plain menus built from the current model snapshot.
9. Polish Launch at Login and Accessibility rows so they show only the needed state/action in the main menu; leave detailed failure information in logs or one short hint.
10. Update README copy after menu labels settle, explicitly saying shortcuts auto-update at launch and each menu open.
11. Update narrow tests for changed menu model/text behavior. Avoid broad AppKit menu tests.

## Verification

Automated:
- Run `swift test`.
- Run focused tests touched by copy/model changes:
  - `swift test --filter MenuContentModelTests` or `swift test --filter DockMenuSummaryTests`
  - `swift test --filter LoginItemMenuModelTests`
  - `swift test --filter TriggerModifierPresetTests` if preset helpers changed
  - `swift test --filter AppTextTests` if added
- Run `swift build`.

<!-- 修订v2: lead 拍板（应 Reviewer C-3）——轻量 pure 测试成为 M3 验收项，理由 AppKit 宽测不必要但内容规则必须固定 -->
Pure test expectations:
- The content model's top-level rows do not include all 10 Dock app names.
- The mapping output has exactly 10 Dock shortcut rows.
- The trigger submenu output marks exactly the selected preset as checked.
- The manual update action label is exactly `Update Dock Shortcuts`.
- The summary count is assigned Dock shortcut count capped at 10, with no skipped or more-than-10 wording.

Manual:
- Launch the signed packaged app with `DOCK_TAP_CODESIGN_IDENTITY="<local signing identity>" scripts/run-app.sh`.
- Open the status menu and confirm the first row is lightweight: `Ready` or `Missing Accessibility Permission`, current trigger preset, and assigned Dock shortcut count such as `9 Dock shortcuts`.
- Confirm the top-level menu shows only the four examples: `<preset>+1`, `<preset>+2`, `<preset>+0`, and ``<preset>+`  Finder``.
- Confirm the top-level menu does not directly list all 10 Dock apps.
- Open `Show Dock Mapping` and confirm exactly 10 Dock shortcut slots are visible with assigned app names/statuses or unassigned labels, and Finder is not listed there.
- Open `Trigger Modifier` and confirm all five presets are present, the current preset is checked, and changing it updates the top-level current value and examples.
- Open `Show Dock Mapping` and `Trigger Modifier` repeatedly after the top-level menu opens and confirm child submenu opening does not trigger additional Dock refreshes or rebuild logs.
- Confirm the manual command reads `Update Dock Shortcuts` and still refreshes Dock-derived mappings.
- Change Dock contents, relaunch app, and confirm mappings update on launch.
- Change Dock contents again, open the menu, and confirm mappings update on menu open without using the manual command.
- With Accessibility missing, confirm the main menu shows the missing state and only the needed permission action.
- Toggle Launch at Login status or simulate known statuses where possible and confirm the menu stays concise while logs retain failure detail.
- Read README and confirm command names match the app menu.

## Risks

- Hiding the full mapping from the top-level menu may make troubleshooting less immediate. The mitigation is a clearly named `Show Dock Mapping` submenu plus unchanged logs.
- Centralizing text can become noisy if treated like full localization. Keep `AppText` small and only move strings that are reused, user-facing, or likely to drift.
- `menuWillOpen` currently refreshes Dock state and rebuilds the menu. The M3 menu restructure must avoid duplicate refresh/rebuild loops or stale submenu content.
<!-- 修订v2: lead 拍板（应 Reviewer C-1）——记录子菜单 delegate 风险，理由 误绑 delegate 会导致打开子菜单也 refresh/rebuild -->
- Accidentally assigning the top-level menu delegate to child submenus would reintroduce refresh/rebuild loops. Treat child submenus as static render output for the current top-level snapshot.
- Dynamic Dock counts below 10 require examples to stay generic. The examples teach the rule; the mapping submenu remains the source of exact assigned/unassigned slots.
- README and menu labels can drift if command names are changed late. Use the final `AppText` labels as the source for documentation wording during the M3 edit.
