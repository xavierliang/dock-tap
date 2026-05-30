import XCTest
import CoreGraphics
@testable import DockTap
import DockTapClosedLidIPC

// MARK: - Fakes

private final class FakeBrightnessController: BrightnessControlling {
    var current: Double?
    private(set) var setValues: [Double] = []
    var setSucceeds = true

    init(current: Double? = 0.8) {
        self.current = current
    }

    func currentInternalBrightness() -> Double? {
        current
    }

    @discardableResult
    func setInternalBrightness(_ value: Double) -> Bool {
        setValues.append(value)
        if setSucceeds {
            current = value
        }
        return setSucceeds
    }
}

private final class FakeLidObserver: LidStateObserving {
    var onLidStateChanged: ((Bool) -> Void)?
    var closed = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func isLidCurrentlyClosed() -> Bool {
        closed
    }

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    /// 测试驱动：模拟系统发来的合盖/开盖事件。
    func emit(closed: Bool) {
        self.closed = closed
        onLidStateChanged?(closed)
    }
}

private final class StubHelperClient: ClosedLidHelperClienting {
    var startResult: ClosedLidHelperStartResult
    var stopResult: ClosedLidHelperStopResult = .stopped

    init(startResult: ClosedLidHelperStartResult) {
        self.startResult = startResult
    }

    func prepareForUse(completion: @escaping (ClosedLidHelperPreparationResult) -> Void) {
        completion(.ready)
    }

    func start(duration: TimeInterval?, completion: @escaping (ClosedLidHelperStartResult) -> Void) {
        completion(startResult)
    }

    func renewLease(token: String, completion: @escaping (ClosedLidHelperRenewResult) -> Void) {
        completion(.renewed)
    }

    func stop(token: String?, reason: String, completion: @escaping (ClosedLidHelperStopResult) -> Void) {
        completion(stopResult)
    }

    func status(completion: @escaping (ClosedLidHelperStatusResult) -> Void) {
        completion(.inactive)
    }

    func openApprovalSettings() {}

    func invalidate() {}
}

// MARK: - Controller dimming tests

final class LidCloseDimmingTests: XCTestCase {
    private func makeController(
        brightness: FakeBrightnessController = FakeBrightnessController(),
        lid: FakeLidObserver = FakeLidObserver()
    ) -> (ClosedLidKeepAwakeController, FakeBrightnessController, FakeLidObserver, SettingsStore) {
        let defaults = UserDefaults(suiteName: "LidCloseDimmingTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.hasSeenClosedLidWarning = true
        let controller = ClosedLidKeepAwakeController(
            settingsStore: settings,
            helperClient: StubHelperClient(
                startResult: .started(
                    ClosedLidHelperSession(token: "tok", mode: .indefinite, endDate: nil)
                )
            ),
            logStore: LogStore(),
            brightnessController: brightness,
            lidObserver: lid
        )
        return (controller, brightness, lid, settings)
    }

    func testLidCloseDimsAndLidOpenRestores() {
        let (controller, brightness, lid, _) = makeController()
        controller.enableIndefinitely()
        XCTAssertEqual(lid.startCount, 1, "active session should start lid observation")

        lid.emit(closed: true)
        XCTAssertEqual(brightness.setValues, [0.0], "lid close should dim to 0")

        lid.emit(closed: false)
        XCTAssertEqual(brightness.setValues, [0.0, 0.8], "lid open should restore saved brightness")
    }

    func testSessionStopRestoresWhenStillDimmed() {
        let (controller, brightness, lid, _) = makeController()
        controller.enableIndefinitely()
        lid.emit(closed: true)
        XCTAssertEqual(brightness.setValues, [0.0])

        // 会话仍在合盖压暗状态下结束 → 兜底恢复
        controller.stopNow()
        XCTAssertEqual(brightness.setValues, [0.0, 0.8], "stop should restore brightness as fallback")
        XCTAssertGreaterThanOrEqual(lid.stopCount, 1, "stop should end lid observation")
    }

    func testNonActiveLidEventDoesNotChangeBrightness() {
        let (_, brightness, lid, _) = makeController()
        // 未启动会话；直接触发合盖事件
        lid.emit(closed: true)
        XCTAssertTrue(brightness.setValues.isEmpty, "lid event while inactive must not touch brightness")
    }

    func testAlreadyClosedAtStartDimsImmediately() {
        let lid = FakeLidObserver()
        lid.closed = true
        let (controller, brightness, _, _) = makeController(lid: lid)
        controller.enableIndefinitely()
        XCTAssertEqual(brightness.setValues, [0.0], "starting with lid already closed should dim immediately")
    }

    func testRepeatedCloseDoesNotResaveBrightness() {
        let (controller, brightness, lid, _) = makeController()
        controller.enableIndefinitely()
        lid.emit(closed: true)
        // 重复合盖事件不应覆盖已保存的 0.8
        brightness.current = 0.0
        lid.emit(closed: true)
        lid.emit(closed: false)
        XCTAssertEqual(brightness.setValues, [0.0, 0.8], "restore must use first saved value, not re-saved 0")
    }

    func testFailedDimDoesNotMarkBrightnessAsSavedAndCanRetry() {
        let brightness = FakeBrightnessController()
        brightness.setSucceeds = false
        let (controller, _, lid, _) = makeController(brightness: brightness)
        controller.enableIndefinitely()

        lid.emit(closed: true)
        XCTAssertEqual(brightness.setValues, [0.0], "first close should attempt to dim")

        brightness.setSucceeds = true
        lid.emit(closed: true)
        lid.emit(closed: false)
        XCTAssertEqual(
            brightness.setValues,
            [0.0, 0.0, 0.8],
            "failed dim must not block retry or restore a brightness that was never changed"
        )
    }
}

// MARK: - BrightnessController backend selection

private final class FakeBackend: DisplayBrightnessBackend {
    let name: String
    private var value: Double?
    let canSet: Bool
    private(set) var setCalls: [Double] = []

    init(name: String, value: Double?, canSet: Bool = true) {
        self.name = name
        self.value = value
        self.canSet = canSet
    }

    func brightness(for id: CGDirectDisplayID) -> Double? {
        value
    }

    func setBrightness(_ value: Double, for id: CGDirectDisplayID) -> Bool {
        setCalls.append(value)
        if canSet {
            self.value = value
        }
        return canSet
    }
}

private struct FixedLocator: BuiltinDisplayLocating {
    let id: CGDirectDisplayID?
    func builtinDisplayID() -> CGDirectDisplayID? { id }
}

final class BrightnessControllerTests: XCTestCase {
    func testSkipsBackendThatCannotRead() {
        let bad = FakeBackend(name: "bad", value: nil) // 模拟 CoreDisplay 在新系统失效
        let good = FakeBackend(name: "good", value: 0.6)
        let controller = BrightnessController(
            locator: FixedLocator(id: 1),
            backends: [bad, good]
        )
        XCTAssertEqual(controller.currentInternalBrightness(), 0.6)
        controller.setInternalBrightness(0.1)
        XCTAssertEqual(good.setCalls, [0.1])
        XCTAssertTrue(bad.setCalls.isEmpty, "unusable backend must not receive sets")
    }

    func testNoBackendDegradesToNoOp() {
        let bad = FakeBackend(name: "bad", value: nil)
        let controller = BrightnessController(
            locator: FixedLocator(id: 1),
            backends: [bad]
        )
        XCTAssertNil(controller.currentInternalBrightness())
        XCTAssertFalse(controller.setInternalBrightness(0))
    }

    func testNoBuiltinDisplayDegradesToNoOp() {
        let good = FakeBackend(name: "good", value: 0.5)
        let controller = BrightnessController(
            locator: FixedLocator(id: nil),
            backends: [good]
        )
        XCTAssertNil(controller.currentInternalBrightness())
        XCTAssertFalse(controller.setInternalBrightness(0))
    }

    func testSetClampsToUnitRange() {
        let good = FakeBackend(name: "good", value: 0.5)
        let controller = BrightnessController(locator: FixedLocator(id: 1), backends: [good])
        controller.setInternalBrightness(5.0)
        controller.setInternalBrightness(-3.0)
        XCTAssertEqual(good.setCalls, [1.0, 0.0])
    }
}
