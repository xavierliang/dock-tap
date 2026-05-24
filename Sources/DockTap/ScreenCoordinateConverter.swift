import CoreGraphics

enum ScreenCoordinateConverter {
    static func axRectToAppKit(_ axRect: CGRect, in displays: [DisplayFrame]) -> CGRect? {
        guard let mainTopY = mainTopY(in: displays) else {
            return nil
        }

        return CGRect(
            x: axRect.minX,
            y: mainTopY - axRect.minY - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    static func appKitPointToAX(_ point: CGPoint, in displays: [DisplayFrame]) -> CGPoint? {
        guard let mainTopY = mainTopY(in: displays) else {
            return nil
        }

        return CGPoint(x: point.x, y: mainTopY - point.y)
    }

    static func axPointToAppKit(_ point: CGPoint, in displays: [DisplayFrame]) -> CGPoint? {
        guard let mainTopY = mainTopY(in: displays) else {
            return nil
        }

        return CGPoint(x: point.x, y: mainTopY - point.y)
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

        return displays.first(where: \.isMain)
    }

    private static func mainTopY(in displays: [DisplayFrame]) -> CGFloat? {
        guard let mainDisplay = displays.first(where: \.isMain) else {
            return nil
        }

        return mainDisplay.frame.maxY
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
