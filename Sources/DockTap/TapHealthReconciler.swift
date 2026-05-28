enum TapInstallAttempt: Equatable {
    case none
    case succeeded
    case failed
}

struct TapHealthReconcileDecision: Equatable {
    let isAccessibilityTrusted: Bool
    let isEventTapReady: Bool
    let shouldStopTap: Bool
    let shouldUpdateSlotSnapshot: Bool
    let shouldInstallTap: Bool
    let shouldRetryInstall: Bool
}

enum TapHealthReconciler {
    static func evaluate(
        isAccessibilityTrusted: Bool,
        isEventTapReady: Bool,
        installAttempt: TapInstallAttempt = .none
    ) -> TapHealthReconcileDecision {
        guard isAccessibilityTrusted else {
            return TapHealthReconcileDecision(
                isAccessibilityTrusted: false,
                isEventTapReady: false,
                shouldStopTap: true,
                shouldUpdateSlotSnapshot: false,
                shouldInstallTap: false,
                shouldRetryInstall: false
            )
        }

        if isEventTapReady {
            return TapHealthReconcileDecision(
                isAccessibilityTrusted: true,
                isEventTapReady: true,
                shouldStopTap: false,
                shouldUpdateSlotSnapshot: false,
                shouldInstallTap: false,
                shouldRetryInstall: false
            )
        }

        return TapHealthReconcileDecision(
            isAccessibilityTrusted: true,
            isEventTapReady: false,
            shouldStopTap: false,
            shouldUpdateSlotSnapshot: installAttempt == .none,
            shouldInstallTap: installAttempt == .none,
            shouldRetryInstall: true
        )
    }
}
