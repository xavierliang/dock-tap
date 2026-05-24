import CoreGraphics
import XCTest
@testable import DockTap

final class ScreenCoordinateConverterTests: XCTestCase {
    func testSinglePrimaryDisplayRoundTripsPointsAndRects() {
        let displays = [primary()]
        let points = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 900),
            CGPoint(x: 720, y: 450),
            CGPoint(x: 1440, y: 900)
        ]

        assertRoundTrips(points: points, displays: displays)
        assertPoint(ScreenCoordinateConverter.appKitPointToAX(CGPoint(x: 0, y: 900), in: displays), equals: CGPoint(x: 0, y: 0))
        assertPoint(ScreenCoordinateConverter.appKitPointToAX(CGPoint(x: 1440, y: 0), in: displays), equals: CGPoint(x: 1440, y: 900))
        assertRect(
            ScreenCoordinateConverter.axRectToAppKit(CGRect(x: 100, y: 200, width: 300, height: 250), in: displays),
            equals: CGRect(x: 100, y: 450, width: 300, height: 250)
        )
    }

    func testSecondaryBelowPrimaryConvertsIntoLowerAppKitBand() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 0, y: -900, width: 1440, height: 900))
        ]
        let secondaryRect = CGRect(x: 100, y: -700, width: 200, height: 100)
        let axRect = axRect(fromAppKitRect: secondaryRect, displays: displays)

        XCTAssertEqual(axRect.origin.y, 1500, accuracy: 0.0001)
        assertRect(ScreenCoordinateConverter.axRectToAppKit(axRect, in: displays), equals: secondaryRect)
        XCTAssertEqual(ScreenCoordinateConverter.selectDisplay(for: axRect, in: displays), displays[1])
    }

    func testSecondaryAbovePrimaryConvertsToNegativeAXY() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 0, y: 900, width: 1440, height: 900))
        ]
        let secondaryRect = CGRect(x: 100, y: 1000, width: 200, height: 100)
        let axRect = axRect(fromAppKitRect: secondaryRect, displays: displays)

        XCTAssertEqual(axRect.origin.y, -200, accuracy: 0.0001)
        assertRect(ScreenCoordinateConverter.axRectToAppKit(axRect, in: displays), equals: secondaryRect)
        XCTAssertEqual(ScreenCoordinateConverter.selectDisplay(for: axRect, in: displays), displays[1])
    }

    func testSecondaryToTheRightPreservesPureXOffset() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        ]
        let secondaryRect = CGRect(x: 1500, y: 100, width: 200, height: 100)
        let axRect = axRect(fromAppKitRect: secondaryRect, displays: displays)

        XCTAssertEqual(axRect.origin.x, 1500, accuracy: 0.0001)
        XCTAssertEqual(axRect.origin.y, 700, accuracy: 0.0001)
        assertRect(ScreenCoordinateConverter.axRectToAppKit(axRect, in: displays), equals: secondaryRect)
        XCTAssertEqual(ScreenCoordinateConverter.selectDisplay(for: axRect, in: displays), displays[1])
    }

    func testScaleFactorDoesNotAffectConversionOrSize() {
        let oneXDisplays = [
            primary(scaleFactor: 1),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900), scaleFactor: 1)
        ]
        let mixedScaleDisplays = [
            primary(scaleFactor: 2),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900), scaleFactor: 1)
        ]
        let rect = CGRect(x: 1500, y: 100, width: 300, height: 200)

        let oneXAXRect = axRect(fromAppKitRect: rect, displays: oneXDisplays)
        let mixedAXRect = axRect(fromAppKitRect: rect, displays: mixedScaleDisplays)

        assertRect(oneXAXRect, equals: mixedAXRect)
        assertRect(ScreenCoordinateConverter.axRectToAppKit(mixedAXRect, in: mixedScaleDisplays), equals: rect)
    }

    func testSelectDisplayUsesMaximumIntersection() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        ]
        let straddlingRect = CGRect(x: 1300, y: 100, width: 320, height: 200)
        let axRect = axRect(fromAppKitRect: straddlingRect, displays: displays)

        XCTAssertEqual(ScreenCoordinateConverter.selectDisplay(for: axRect, in: displays), displays[1])
    }

    func testSelectDisplayFallsBackToCenterOnTieOrZeroIntersection() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        ]
        let tiedRect = CGRect(x: 1300, y: 100, width: 280, height: 200)
        let zeroSizeRect = CGRect(x: 200, y: 200, width: 0, height: 0)

        XCTAssertEqual(
            ScreenCoordinateConverter.selectDisplay(for: axRect(fromAppKitRect: tiedRect, displays: displays), in: displays),
            displays[1]
        )
        XCTAssertEqual(
            ScreenCoordinateConverter.selectDisplay(for: axRect(fromAppKitRect: zeroSizeRect, displays: displays), in: displays),
            displays[0]
        )
    }

    func testSelectDisplayFallsBackToMainForOffscreenWindow() {
        let displays = [
            primary(),
            display(frame: CGRect(x: 1440, y: 0, width: 1440, height: 900))
        ]
        let offscreenRect = CGRect(x: 5000, y: 5000, width: 100, height: 100)

        XCTAssertEqual(
            ScreenCoordinateConverter.selectDisplay(for: axRect(fromAppKitRect: offscreenRect, displays: displays), in: displays),
            displays[0]
        )
    }

    func testMissingMainDisplayReturnsNil() {
        let displays = [
            display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMain: false)
        ]

        XCTAssertNil(ScreenCoordinateConverter.appKitPointToAX(CGPoint(x: 0, y: 0), in: displays))
        XCTAssertNil(ScreenCoordinateConverter.axPointToAppKit(CGPoint(x: 0, y: 0), in: displays))
        XCTAssertNil(ScreenCoordinateConverter.axRectToAppKit(CGRect(x: 0, y: 0, width: 100, height: 100), in: displays))
        XCTAssertNil(ScreenCoordinateConverter.selectDisplay(for: CGRect(x: 0, y: 0, width: 100, height: 100), in: displays))
    }

    func testEmptyDisplaysReturnNil() {
        XCTAssertNil(ScreenCoordinateConverter.appKitPointToAX(CGPoint(x: 0, y: 0), in: []))
        XCTAssertNil(ScreenCoordinateConverter.axPointToAppKit(CGPoint(x: 0, y: 0), in: []))
        XCTAssertNil(ScreenCoordinateConverter.axRectToAppKit(CGRect(x: 0, y: 0, width: 100, height: 100), in: []))
        XCTAssertNil(ScreenCoordinateConverter.selectDisplay(for: CGRect(x: 0, y: 0, width: 100, height: 100), in: []))
    }

    private func assertRoundTrips(points: [CGPoint], displays: [DisplayFrame], file: StaticString = #filePath, line: UInt = #line) {
        for point in points {
            let axPoint = ScreenCoordinateConverter.appKitPointToAX(point, in: displays)
            let appKitPoint = axPoint.flatMap { ScreenCoordinateConverter.axPointToAppKit($0, in: displays) }
            assertPoint(appKitPoint, equals: point, file: file, line: line)
        }
    }

    private func axRect(fromAppKitRect rect: CGRect, displays: [DisplayFrame]) -> CGRect {
        guard let origin = ScreenCoordinateConverter.appKitPointToAX(CGPoint(x: rect.minX, y: rect.maxY), in: displays) else {
            XCTFail("expected AppKit-to-AX conversion")
            return .zero
        }
        return CGRect(origin: origin, size: rect.size)
    }

    private func primary(scaleFactor: CGFloat? = nil) -> DisplayFrame {
        display(frame: CGRect(x: 0, y: 0, width: 1440, height: 900), isMain: true, scaleFactor: scaleFactor)
    }

    private func display(
        frame: CGRect,
        isMain: Bool = false,
        scaleFactor: CGFloat? = nil
    ) -> DisplayFrame {
        DisplayFrame(
            frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 20),
            isMain: isMain,
            scaleFactor: scaleFactor
        )
    }

    private func assertRect(_ actual: CGRect?, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            return XCTFail("expected rect", file: file, line: line)
        }
        assertRect(actual, equals: expected, file: file, line: line)
    }

    private func assertRect(_ actual: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
    }

    private func assertPoint(_ actual: CGPoint?, equals expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        guard let actual else {
            return XCTFail("expected point", file: file, line: line)
        }
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.0001, file: file, line: line)
    }
}
