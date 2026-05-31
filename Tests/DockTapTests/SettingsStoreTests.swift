import XCTest
@testable import DockTap

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "DockTapTests.SettingsStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultPresetIsLeftOption() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.selectedTriggerModifierPreset, .leftOption)
    }

    func testPersistsSelectedPreset() {
        let store = SettingsStore(defaults: defaults)
        store.selectedTriggerModifierPreset = .rightCommand

        let reloadedStore = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloadedStore.selectedTriggerModifierPreset, .rightCommand)
    }

    func testUnknownRawValueFallsBackToLeftOption() {
        defaults.set("custom", forKey: "triggerModifierPreset")
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.selectedTriggerModifierPreset, .leftOption)
    }

    func testWindowActionsDefaultToDisabled() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.windowActionsEnabled)
    }

    func testDockShortcutsDefaultToEnabled() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertTrue(store.dockShortcutsEnabled)
    }

    func testPersistsDockShortcutsEnabled() {
        let store = SettingsStore(defaults: defaults)

        store.dockShortcutsEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).dockShortcutsEnabled)

        store.dockShortcutsEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).dockShortcutsEnabled)
    }

    func testPersistsWindowActionsEnabled() {
        let store = SettingsStore(defaults: defaults)

        store.windowActionsEnabled = true
        XCTAssertTrue(SettingsStore(defaults: defaults).windowActionsEnabled)

        store.windowActionsEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).windowActionsEnabled)
    }

    func testWindowActionsEnabledLastWriteWins() {
        let store = SettingsStore(defaults: defaults)

        store.windowActionsEnabled = true
        store.windowActionsEnabled = false
        XCTAssertFalse(SettingsStore(defaults: defaults).windowActionsEnabled)
    }

    func testClosedLidWarningAcknowledgementDefaultsToFalse() {
        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.hasSeenClosedLidWarning)
    }

    func testPersistsClosedLidWarningAcknowledgement() {
        let store = SettingsStore(defaults: defaults)

        store.hasSeenClosedLidWarning = true
        XCTAssertTrue(SettingsStore(defaults: defaults).hasSeenClosedLidWarning)

        store.hasSeenClosedLidWarning = false
        XCTAssertFalse(SettingsStore(defaults: defaults).hasSeenClosedLidWarning)
    }
}
