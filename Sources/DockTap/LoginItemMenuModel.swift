struct LoginItemMenuModel: Equatable {
    let title: String
    let isChecked: Bool
    let hintRows: [String]

    init(status: LoginItemStatus, failureMessage: String?) {
        title = Self.title(for: status)
        isChecked = status.isEnabled

        var hints: [String] = []
        if let failureMessage {
            hints.append("Login item: \(failureMessage)")
        }
        if status == .requiresApproval {
            hints.append("Approve in System Settings > General > Login Items")
        }
        hintRows = hints
    }

    private static func title(for status: LoginItemStatus) -> String {
        switch status {
        case .enabled, .disabled:
            "Launch at Login"
        case .requiresApproval:
            "Launch at Login (Requires Approval)"
        case .notFound:
            "Launch at Login (Not Found)"
        case .error:
            "Launch at Login (Status Error)"
        }
    }
}
