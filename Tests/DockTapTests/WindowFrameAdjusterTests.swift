import ApplicationServices
import XCTest
@testable import DockTap

final class WindowFrameAdjusterTests: XCTestCase {
    private let target = CGRect(x: 0, y: 25, width: 1440, height: 800)

    func testAnimatedWritesReachTargetInOneAttemptAndRestoreEnhancedUI() {
        let window = TestWindow()
        window.enhancedUI = true
        // Model the failure: each animated write starts from the current frame,
        // replacing the previous pending update before it has reached its target.
        _ = window.access.setSize(target.size)
        _ = window.access.setPosition(target.origin)
        _ = window.access.setSize(target.size)
        window.settleAnimation()
        XCTAssertNotEqual(window.frame, target)

        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        var writes: WindowFrameAdjuster.WriteResult?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, value in writes = value },
                       completion: { result = $0 })

        XCTAssertNil(result, "Do not claim success before the settled frame is read")
        XCTAssertEqual(window.frame, target)
        XCTAssertEqual(window.enhancedUI, true)
        XCTAssertEqual(window.enhancedUIChanges, [false, true])
        XCTAssertEqual(writes?.disableEnhancedUI, .success)
        XCTAssertEqual(writes?.restoreEnhancedUI, .success)
        scheduler.runNext()
        XCTAssertEqual(result?.outcome, .verified)
        XCTAssertEqual(result?.attempts, 1)
        XCTAssertEqual(result?.actualFrame, target)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testAppThatSettlesLaterDoesNotNeedARetry() {
        let window = TestWindow()
        window.defersWrites = true
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })

        XCTAssertNotEqual(window.frame, target)
        window.settleAnimation()
        scheduler.runNext()
        XCTAssertEqual(result?.outcome, .verified)
        XCTAssertEqual(result?.attempts, 1)
        XCTAssertEqual(window.frameWriteCount, 3)
    }

    func testSilentlyIgnoredResizeIsCorrectedWithoutAnotherShortcut() {
        let window = TestWindow()
        window.ignoredSizeWrites = 2
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })

        XCTAssertNotEqual(window.frame, target)
        scheduler.runNext()
        XCTAssertNil(result)
        XCTAssertEqual(window.frame, target)
        scheduler.runNext()
        XCTAssertEqual(result?.outcome, .verified)
        XCTAssertEqual(result?.attempts, 2)
        XCTAssertEqual(result?.actualFrame, target)
    }

    func testConstrainedWindowStopsAfterThreeAttemptsAndReportsMismatch() {
        let window = TestWindow()
        window.maximumWidth = 900
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
        for _ in 0..<3 { scheduler.runNext() }

        XCTAssertEqual(result?.outcome, .frameMismatch)
        XCTAssertEqual(result?.actualFrame?.width, 900)
        XCTAssertEqual(result?.attempts, 3)
        XCTAssertEqual(window.frameWriteCount, 9)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testNewActionCancelsOlderRetryAndKeepsTheNewDestination() {
        let window = TestWindow()
        window.ignoredSizeWrites = 2
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var oldResult: WindowFrameAdjuster.Result?
        var newResult: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { oldResult = $0 })
        let rightHalf = CGRect(x: 720, y: 25, width: 720, height: 800)
        adjuster.apply(target: rightHalf, access: window.access, onAttempt: { _, _ in }, completion: { newResult = $0 })

        scheduler.runNext()
        XCTAssertNil(oldResult)
        XCTAssertEqual(window.frameWriteCount, 6)
        scheduler.runNext()
        XCTAssertEqual(newResult?.outcome, .verified)
        XCTAssertEqual(window.frame, rightHalf)
        XCTAssertEqual(window.frameWriteCount, 6)
    }

    func testExplicitCancellationDoesNotWriteAgain() {
        let window = TestWindow()
        window.ignoredSizeWrites = 2
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
        adjuster.cancel()
        scheduler.runNext()

        XCTAssertNil(result)
        XCTAssertEqual(window.frameWriteCount, 3)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testFocusOrDisplayChangeOrDraggingCancelsPendingAdjustment() {
        let window = TestWindow()
        window.ignoredSizeWrites = 2
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
        window.canAdjust = false
        scheduler.runNext()

        XCTAssertEqual(result?.outcome, .cancelled)
        XCTAssertEqual(window.frameWriteCount, 3)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testInvalidWindowIsNotTouched() {
        let window = TestWindow()
        window.canAdjust = false
        window.enhancedUI = true
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })

        XCTAssertEqual(result?.outcome, .cancelled)
        XCTAssertEqual(result?.attempts, 0)
        XCTAssertEqual(window.frameWriteCount, 0)
        XCTAssertTrue(window.enhancedUIChanges.isEmpty)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testUnavailableReadbackDoesNotReportSuccessOrRetryBlindly() {
        let window = TestWindow()
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
        window.readable = false
        scheduler.runNext()

        XCTAssertEqual(result?.outcome, .frameUnavailable)
        XCTAssertNil(result?.actualFrame)
        XCTAssertEqual(window.frameWriteCount, 3)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testDisabledOrUnsupportedEnhancedUIIsLeftUnchanged() {
        for original: Bool? in [false, nil] {
            let window = TestWindow()
            window.enhancedUI = original
            let scheduler = TestScheduler()
            let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
            var result: WindowFrameAdjuster.Result?
            adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
            scheduler.runNext()

            XCTAssertEqual(result?.outcome, .verified)
            XCTAssertEqual(window.enhancedUI, original)
            XCTAssertTrue(window.enhancedUIChanges.isEmpty)
        }
    }

    func testFailedFrameWritesStillRestoreEnhancedUI() {
        let window = TestWindow()
        window.enhancedUI = true
        window.frameWriteError = .cannotComplete
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var writes: WindowFrameAdjuster.WriteResult?
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, value in writes = value },
                       completion: { result = $0 })
        for _ in 0..<3 { scheduler.runNext() }

        XCTAssertEqual(writes?.initialSize, .cannotComplete)
        XCTAssertEqual(writes?.position, .cannotComplete)
        XCTAssertEqual(writes?.finalSize, .cannotComplete)
        XCTAssertEqual(window.enhancedUI, true)
        XCTAssertEqual(window.enhancedUIChanges, [false, true, false, true, false, true])
        XCTAssertEqual(result?.outcome, .frameMismatch)
    }

    func testTimedOutDisableStillRestoresOriginalEnhancedUI() {
        let window = TestWindow()
        window.enhancedUI = true
        window.disableError = .cannotComplete
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var writes: WindowFrameAdjuster.WriteResult?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, value in writes = value }, completion: { _ in })

        XCTAssertEqual(writes?.disableEnhancedUI, .cannotComplete)
        XCTAssertEqual(writes?.restoreEnhancedUI, .success)
        XCTAssertEqual(window.enhancedUI, true)
        XCTAssertEqual(window.enhancedUIChanges, [false, true])
    }

    func testRestorationErrorIsReported() {
        let window = TestWindow()
        window.enhancedUI = true
        window.restoreError = .cannotComplete
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var writes: WindowFrameAdjuster.WriteResult?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, value in writes = value }, completion: { _ in })
        XCTAssertEqual(writes?.restoreEnhancedUI, .cannotComplete)
    }

    func testSubPointRoundingDoesNotCauseRetries() {
        let window = TestWindow()
        let scheduler = TestScheduler()
        let adjuster = WindowFrameAdjuster(scheduleVerification: scheduler.schedule)
        var result: WindowFrameAdjuster.Result?
        adjuster.apply(target: target, access: window.access, onAttempt: { _, _ in }, completion: { result = $0 })
        window.frame.origin.x += 0.5
        window.frame.size.width -= 0.5
        scheduler.runNext()
        XCTAssertEqual(result?.outcome, .verified)
        XCTAssertEqual(window.frameWriteCount, 3)
    }
}

private final class TestScheduler {
    var pending: [() -> Void] = []
    func schedule(_ work: @escaping () -> Void) { pending.append(work) }
    func runNext(file: StaticString = #filePath, line: UInt = #line) {
        guard !pending.isEmpty else {
            XCTFail("No verification scheduled", file: file, line: line)
            return
        }
        pending.removeFirst()()
    }
}

private final class TestWindow {
    var frame = CGRect(x: 360, y: 200, width: 700, height: 500)
    var enhancedUI: Bool? = false
    var enhancedUIChanges: [Bool] = []
    var canAdjust = true
    var readable = true
    var defersWrites = false
    var ignoredSizeWrites = 0
    var maximumWidth: CGFloat = .greatestFiniteMagnitude
    var frameWriteError = AXError.success
    var disableError = AXError.success
    var restoreError = AXError.success
    var frameWriteCount = 0
    private var pendingFrame: CGRect?

    var access: WindowFrameAdjuster.Access {
        WindowFrameAdjuster.Access(
            canAdjust: { self.canAdjust },
            readFrame: { self.readable ? self.frame : nil },
            readEnhancedUI: { self.enhancedUI },
            setEnhancedUI: {
                self.enhancedUIChanges.append($0)
                self.enhancedUI = $0
                return $0 ? self.restoreError : self.disableError
            },
            setSize: { size in
                self.frameWriteCount += 1
                guard self.frameWriteError == .success else { return self.frameWriteError }
                if self.ignoredSizeWrites > 0 {
                    self.ignoredSizeWrites -= 1
                    return .success
                }
                self.updateFrame { $0.size = CGSize(width: min(size.width, self.maximumWidth), height: size.height) }
                return .success
            },
            setPosition: { origin in
                self.frameWriteCount += 1
                guard self.frameWriteError == .success else { return self.frameWriteError }
                self.updateFrame { $0.origin = origin }
                return .success
            }
        )
    }

    func settleAnimation() {
        if let pendingFrame { frame = pendingFrame }
        pendingFrame = nil
    }

    private func updateFrame(_ update: (inout CGRect) -> Void) {
        if enhancedUI == true {
            var next = frame
            update(&next)
            pendingFrame = next
        } else if defersWrites {
            var next = pendingFrame ?? frame
            update(&next)
            pendingFrame = next
        } else {
            update(&frame)
        }
    }
}
