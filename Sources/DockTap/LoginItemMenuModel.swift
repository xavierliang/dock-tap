struct LoginItemMenuModel: Equatable {
    let title: String
    let isChecked: Bool
    let hintRows: [String]

    init(status: LoginItemStatus, failureMessage: String?) {
        title = Self.title(for: status)
        isChecked = status.isEnabled

        var hints: [String] = []
        if failureMessage != nil {
            hints.append(AppText.LoginItem.failureHint)
        }
        if status == .requiresApproval {
            hints.append(AppText.LoginItem.approveHint)
        }
        hintRows = hints
    }

    private static func title(for status: LoginItemStatus) -> String {
        switch status {
        case .enabled, .disabled:
            AppText.LoginItem.launchAtLogin
        case .requiresApproval:
            AppText.LoginItem.requiresApproval
        case .notFound:
            AppText.LoginItem.notFound
        case .error:
            AppText.LoginItem.statusError
        }
    }
}
