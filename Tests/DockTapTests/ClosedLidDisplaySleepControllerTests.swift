import XCTest
@testable import DockTap

final class ClosedLidDisplaySleepControllerTests: XCTestCase {
    private var clamshellStateProvider: FakeClamshellStateProvider!
    private var displayTopologyProvider: FakeDisplayTopologyProvider!
    private var commandRunner: FakeDisplaySleepCommandRunner!
    private var logStore: LogStore!
    private var controller: ClosedLidDisplaySleepController!

    override func setUp() {
        super.setUp()
        clamshellStateProvider = FakeClamshellStateProvider()
        displayTopologyProvider = FakeDisplayTopologyProvider()
        commandRunner = FakeDisplaySleepCommandRunner()
        logStore = LogStore()
        controller = ClosedLidDisplaySleepController(
            clamshellStateProvider: clamshellStateProvider,
            displayTopologyProvider: displayTopologyProvider,
            commandRunner: commandRunner,
            logStore: logStore,
            monitorInterval: 60
        )
    }

    override func tearDown() {
        controller.invalidate()
        controller = nil
        logStore = nil
        commandRunner = nil
        displayTopologyProvider = nil
        clamshellStateProvider = nil
        super.tearDown()
    }

    func testActiveKeepAwakeWithClosedLidTriggersDisplaySleep() {
        clamshellStateProvider.lidClosed = true

        controller.setKeepAwakeActive(true)

        XCTAssertEqual(commandRunner.sleepDisplayCallCount, 1)
    }

    func testOffKeepAwakeDoesNotTriggerDisplaySleep() {
        clamshellStateProvider.lidClosed = true

        controller.evaluateNow()
        controller.setKeepAwakeActive(false)
        controller.evaluateNow()

        XCTAssertEqual(commandRunner.sleepDisplayCallCount, 0)
    }

    func testStoppingKeepAwakeDisablesDisplaySleepChecks() {
        clamshellStateProvider.lidClosed = false
        controller.setKeepAwakeActive(true)
        controller.setKeepAwakeActive(false)

        clamshellStateProvider.lidClosed = true
        controller.evaluateNow()

        XCTAssertEqual(commandRunner.sleepDisplayCallCount, 0)
    }

    func testExternalDisplaySkipsDisplaySleep() {
        clamshellStateProvider.lidClosed = true
        displayTopologyProvider.hasExternalDisplay = true

        controller.setKeepAwakeActive(true)

        XCTAssertEqual(commandRunner.sleepDisplayCallCount, 0)
        XCTAssertTrue(logStore.entries.contains { $0.text.contains("external display active") })
    }

    func testDisplaySleepRunsOncePerClosedLidTransition() {
        clamshellStateProvider.lidClosed = true
        controller.setKeepAwakeActive(true)
        controller.evaluateNow()

        clamshellStateProvider.lidClosed = false
        controller.evaluateNow()
        clamshellStateProvider.lidClosed = true
        controller.evaluateNow()

        XCTAssertEqual(commandRunner.sleepDisplayCallCount, 2)
    }
}

private final class FakeClamshellStateProvider: ClosedLidClamshellStateProviding {
    var lidClosed: Bool?

    func isLidClosed() -> Bool? {
        lidClosed
    }
}

private final class FakeDisplayTopologyProvider: ClosedLidDisplayTopologyProviding {
    var hasExternalDisplay = false

    func hasActiveExternalDisplay() -> Bool {
        hasExternalDisplay
    }
}

private final class FakeDisplaySleepCommandRunner: ClosedLidDisplaySleepCommandRunning {
    private(set) var sleepDisplayCallCount = 0
    var result = ClosedLidDisplaySleepCommandResult(terminationStatus: 0, standardError: "")

    func sleepDisplays() -> ClosedLidDisplaySleepCommandResult {
        sleepDisplayCallCount += 1
        return result
    }
}
