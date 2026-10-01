import ApplicationServices
import Foundation

/// Runs on the main queue. Each request keeps its original window and target frame.
final class WindowFrameAdjuster {
    struct Access {
        let canAdjust: () -> Bool
        let readFrame: () -> CGRect?
        let readEnhancedUI: () -> Bool?
        let setEnhancedUI: (Bool) -> AXError
        let setSize: (CGSize) -> AXError
        let setPosition: (CGPoint) -> AXError
    }

    struct WriteResult {
        let initialSize: AXError
        let position: AXError
        let finalSize: AXError
        let enhancedUIWasEnabled: Bool?
        let disableEnhancedUI: AXError?
        let restoreEnhancedUI: AXError?
    }

    enum Outcome: Equatable {
        case verified
        case frameMismatch
        case frameUnavailable
        case cancelled
    }

    struct Result {
        let outcome: Outcome
        let attempts: Int
        let actualFrame: CGRect?
    }

    private static let maximumAttempts = 3
    private let scheduleVerification: (@escaping () -> Void) -> Void
    private var generation: UInt64 = 0

    init(scheduleVerification: @escaping (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }) {
        self.scheduleVerification = scheduleVerification
    }

    func cancel() {
        generation &+= 1
    }

    func apply(
        target: CGRect,
        access: Access,
        onAttempt: @escaping (Int, WriteResult) -> Void,
        completion: @escaping (Result) -> Void
    ) {
        cancel()
        attempt(target: target, access: access, number: 1, generation: generation,
                onAttempt: onAttempt, completion: completion)
    }

    private func attempt(
        target: CGRect,
        access: Access,
        number: Int,
        generation requestGeneration: UInt64,
        onAttempt: @escaping (Int, WriteResult) -> Void,
        completion: @escaping (Result) -> Void
    ) {
        guard generation == requestGeneration else { return }
        guard access.canAdjust() else {
            completion(Result(outcome: .cancelled, attempts: number - 1, actualFrame: nil))
            return
        }

        onAttempt(number, writeFrame(target, access: access))
        // AX success only acknowledges the write. Let the app settle before reading
        // back; a tight retry loop can interrupt an in-flight window animation.
        scheduleVerification { [weak self] in
            guard let self, self.generation == requestGeneration else { return }
            guard access.canAdjust() else {
                completion(Result(outcome: .cancelled, attempts: number, actualFrame: nil))
                return
            }
            guard let actual = access.readFrame() else {
                completion(Result(outcome: .frameUnavailable, attempts: number, actualFrame: nil))
                return
            }
            if Self.matches(actual, target) {
                completion(Result(outcome: .verified, attempts: number, actualFrame: actual))
            } else if number < Self.maximumAttempts {
                self.attempt(target: target, access: access, number: number + 1,
                             generation: requestGeneration, onAttempt: onAttempt, completion: completion)
            } else {
                completion(Result(outcome: .frameMismatch, attempts: number, actualFrame: actual))
            }
        }
    }

    private func writeFrame(_ target: CGRect, access: Access) -> WriteResult {
        let enhancedUI = access.readEnhancedUI()
        let disableResult = enhancedUI == true ? access.setEnhancedUI(false) : nil
        var restoreResult: AXError?
        let writes: (AXError, AXError, AXError) = {
            // Restore even after a failed disable: a timed-out AX call may still
            // have changed the app. Always attempt to restore the original mode.
            defer {
                if enhancedUI == true {
                    restoreResult = access.setEnhancedUI(true)
                }
            }
            let initialSize = access.setSize(target.size)
            let position = access.setPosition(target.origin)
            // The first size write can be clamped at the old origin.
            let finalSize = access.setSize(target.size)
            return (initialSize, position, finalSize)
        }()
        return WriteResult(initialSize: writes.0, position: writes.1, finalSize: writes.2,
                           enhancedUIWasEnabled: enhancedUI, disableEnhancedUI: disableResult,
                           restoreEnhancedUI: restoreResult)
    }

    private static func matches(_ actual: CGRect, _ target: CGRect) -> Bool {
        // AX frames are in points; tolerate sub-point/whole-point rounding.
        abs(actual.origin.x - target.origin.x) <= 1
            && abs(actual.origin.y - target.origin.y) <= 1
            && abs(actual.width - target.width) <= 1
            && abs(actual.height - target.height) <= 1
    }
}
