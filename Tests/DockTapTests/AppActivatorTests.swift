import XCTest
@testable import DockTap

final class AppActivatorTests: XCTestCase {
    func testRouteUsesIntentBoundTargetAfterSlotRefresh() {
        let store = DockSlotStore()
        store.replace(entries: [
            appEntry(name: "Original", dockOrdinal: 1, bundleIdentifier: "dev.local.original")
        ])

        let intent = intentForFirstSlot(in: store.snapshot())

        store.replace(entries: [
            appEntry(name: "Replacement", dockOrdinal: 1, bundleIdentifier: "dev.local.replacement")
        ])

        let route = AppActivator.route(
            for: intent,
            context: AppActivationContext(
                runningBundleIdentifiers: ["dev.local.replacement"],
                finderIsRunning: false,
                finderURL: nil
            )
        )

        guard case .launchSlot(let target) = route else {
            return XCTFail("expected original intent target to be launched, got \(route)")
        }
        XCTAssertEqual(target.displayName, "Original")
        XCTAssertEqual(target.bundleIdentifier, "dev.local.original")
        XCTAssertEqual(target.shortcutIndex, 0)
        XCTAssertEqual(target.dockOrdinal, 1)
    }

    private func intentForFirstSlot(in snapshot: DockSlotSnapshot) -> ShortcutIntent {
        var modifiers = ModifierSnapshot()
        modifiers.leftOption = true

        let decision = KeyEventDecider().decide(
            kind: .keyDown,
            keyCode: KeyCodes.one,
            modifiers: modifiers,
            triggerModifier: .leftOption,
            slots: snapshot
        )

        guard let intent = decision.intent else {
            XCTFail("expected first slot intent")
            return .finder(shortcutLabel: "Left Option+`")
        }
        return intent
    }

    private func appEntry(name: String, dockOrdinal: Int, bundleIdentifier: String?) -> DockAppEntry {
        DockAppEntry(
            dockOrdinal: dockOrdinal,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            isMissing: false
        )
    }
}
