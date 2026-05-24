import Foundation
import ServiceManagement

enum LoginItemServiceStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

enum LoginItemStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case notFound
    case error(String)

    var displayValue: String {
        switch self {
        case .disabled:
            "disabled"
        case .enabled:
            "enabled"
        case .requiresApproval:
            "requires approval"
        case .notFound:
            "not found"
        case .error(let message):
            "error: \(message)"
        }
    }

    var isEnabled: Bool {
        self == .enabled
    }
}

struct LoginItemOperationResult: Equatable {
    let status: LoginItemStatus
    let failureMessage: String?

    var succeeded: Bool {
        failureMessage == nil
    }
}

protocol LoginItemServiceAdapter {
    func status() throws -> LoginItemServiceStatus
    func register() throws
    func unregister() throws
}

struct SMAppServiceLoginItemAdapter: LoginItemServiceAdapter {
    func status() throws -> LoginItemServiceStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .notFound
        @unknown default:
            .notFound
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

final class LoginItemController {
    private let adapter: LoginItemServiceAdapter

    init(adapter: LoginItemServiceAdapter = SMAppServiceLoginItemAdapter()) {
        self.adapter = adapter
    }

    func status() -> LoginItemStatus {
        currentStatus()
    }

    func enable() -> LoginItemOperationResult {
        perform(
            actionName: "enable Launch at Login",
            action: adapter.register
        )
    }

    func disable() -> LoginItemOperationResult {
        perform(
            actionName: "disable Launch at Login",
            action: adapter.unregister
        )
    }

    private func perform(
        actionName: String,
        action: () throws -> Void
    ) -> LoginItemOperationResult {
        do {
            try action()
            return LoginItemOperationResult(status: currentStatus(), failureMessage: nil)
        } catch {
            return LoginItemOperationResult(
                status: currentStatus(),
                failureMessage: "failed to \(actionName): \(error.localizedDescription)"
            )
        }
    }

    private func currentStatus() -> LoginItemStatus {
        do {
            switch try adapter.status() {
            case .notRegistered:
                return .disabled
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notFound:
                return .notFound
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
