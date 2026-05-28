import CoreGraphics

enum ScreenCoordinateConverter {
    static func axRectToAppKit(_ axRect: CGRect, in displays: [DisplayFrame]) -> CGRect? {
        guard let anchorTopY = anchorTopY(in: displays) else {
            return nil
        }

        return CGRect(
            x: axRect.minX,
            y: anchorTopY - axRect.minY - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    static func appKitPointToAX(_ point: CGPoint, in displays: [DisplayFrame]) -> CGPoint? {
        guard let anchorTopY = anchorTopY(in: displays) else {
            return nil
        }

        return CGPoint(x: point.x, y: anchorTopY - point.y)
    }

    static func axPointToAppKit(_ point: CGPoint, in displays: [DisplayFrame]) -> CGPoint? {
        guard let anchorTopY = anchorTopY(in: displays) else {
            return nil
        }

        return CGPoint(x: point.x, y: anchorTopY - point.y)
    }

    static func selectDisplay(for axRect: CGRect, in displays: [DisplayFrame]) -> DisplayFrame? {
        guard !displays.isEmpty, let appKitRect = axRectToAppKit(axRect, in: displays) else {
            return nil
        }

        let intersections = displays.map { display in
            (display: display, area: intersectionArea(appKitRect, display.frame))
        }
        let maxArea = intersections.map(\.area).max() ?? 0
        let maxAreaMatches = intersections.filter { approximatelyEqual($0.area, maxArea) }

        if maxArea > 0, maxAreaMatches.count == 1 {
            return maxAreaMatches[0].display
        }

        let center = CGPoint(x: appKitRect.midX, y: appKitRect.midY)
        if let containingDisplay = displays.first(where: { $0.frame.contains(center) }) {
            return containingDisplay
        }

        return displays.first(where: \.isCoordinateAnchor)
    }

    private static func anchorTopY(in displays: [DisplayFrame]) -> CGFloat? {
        guard let coordinateAnchor = displays.first(where: \.isCoordinateAnchor) else {
            return nil
        }

        return coordinateAnchor.frame.maxY
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat) -> Bool {
        abs(lhs - rhs) < 0.0001
    }
}
