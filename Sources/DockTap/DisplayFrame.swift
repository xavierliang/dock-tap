import CoreGraphics

struct DisplayFrame: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isCoordinateAnchor: Bool
    let identifier: String?
    let scaleFactor: CGFloat?

    init(
        frame: CGRect,
        visibleFrame: CGRect,
        isCoordinateAnchor: Bool,
        identifier: String? = nil,
        scaleFactor: CGFloat? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isCoordinateAnchor = isCoordinateAnchor
        self.identifier = identifier
        self.scaleFactor = scaleFactor
    }
}
