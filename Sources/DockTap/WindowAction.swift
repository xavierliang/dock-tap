import CoreGraphics

enum WindowAction: String, CaseIterable, Equatable {
    case leftHalf
    case rightHalf
    case topHalf
    case bottomHalf
    case maximize
    case center

    static let centerScale: CGFloat = 0.75

    var displayName: String {
        switch self {
        case .leftHalf:
            AppText.WindowSnap.leftHalf
        case .rightHalf:
            AppText.WindowSnap.rightHalf
        case .topHalf:
            AppText.WindowSnap.topHalf
        case .bottomHalf:
            AppText.WindowSnap.bottomHalf
        case .maximize:
            AppText.WindowSnap.maximize
        case .center:
            AppText.WindowSnap.center
        }
    }

    var shortcutKeyLabel: String {
        switch self {
        case .leftHalf:
            "←"
        case .rightHalf:
            "→"
        case .topHalf:
            "↑"
        case .bottomHalf:
            "↓"
        case .maximize:
            "Return"
        case .center:
            "Space"
        }
    }

    func targetRect(in visibleFrame: CGRect) -> CGRect {
        switch self {
        case .leftHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .rightHalf:
            return CGRect(
                x: visibleFrame.midX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .topHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.midY,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        case .bottomHalf:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: visibleFrame.height / 2
            )
        case .maximize:
            return visibleFrame
        case .center:
            let width = visibleFrame.width * Self.centerScale
            let height = visibleFrame.height * Self.centerScale
            return CGRect(
                x: visibleFrame.minX + (visibleFrame.width - width) / 2,
                y: visibleFrame.minY + (visibleFrame.height - height) / 2,
                width: width,
                height: height
            )
        }
    }
}
