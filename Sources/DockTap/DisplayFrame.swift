import CoreGraphics

struct DisplayFrame: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
    let identifier: String?
    let scaleFactor: CGFloat?

    init(
        frame: CGRect,
        visibleFrame: CGRect,
        isMain: Bool,
        identifier: String? = nil,
        scaleFactor: CGFloat? = nil
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.identifier = identifier
        self.scaleFactor = scaleFactor
    }
}
