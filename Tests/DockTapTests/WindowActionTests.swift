import CoreGraphics
import XCTest
@testable import DockTap

final class WindowActionTests: XCTestCase {
    func testTargetRectsInZeroOriginVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)

        assertRect(WindowAction.leftHalf.targetRect(in: visibleFrame), equals: CGRect(x: 0, y: 0, width: 720, height: 900))
        assertRect(WindowAction.rightHalf.targetRect(in: visibleFrame), equals: CGRect(x: 720, y: 0, width: 720, height: 900))
        assertRect(WindowAction.topHalf.targetRect(in: visibleFrame), equals: CGRect(x: 0, y: 450, width: 1440, height: 450))
        assertRect(WindowAction.bottomHalf.targetRect(in: visibleFrame), equals: CGRect(x: 0, y: 0, width: 1440, height: 450))
        assertRect(WindowAction.maximize.targetRect(in: visibleFrame), equals: visibleFrame)
        assertRect(WindowAction.center.targetRect(in: visibleFrame), equals: CGRect(x: 180, y: 112.5, width: 1080, height: 675))
    }

    func testTargetRectsPreserveNonZeroVisibleFrameOrigin() {
        let visibleFrame = CGRect(x: 1440, y: 28, width: 1200, height: 800)

        assertRect(WindowAction.leftHalf.targetRect(in: visibleFrame), equals: CGRect(x: 1440, y: 28, width: 600, height: 800))
        assertRect(WindowAction.rightHalf.targetRect(in: visibleFrame), equals: CGRect(x: 2040, y: 28, width: 600, height: 800))
        assertRect(WindowAction.topHalf.targetRect(in: visibleFrame), equals: CGRect(x: 1440, y: 428, width: 1200, height: 400))
        assertRect(WindowAction.bottomHalf.targetRect(in: visibleFrame), equals: CGRect(x: 1440, y: 28, width: 1200, height: 400))
        assertRect(WindowAction.maximize.targetRect(in: visibleFrame), equals: visibleFrame)
        assertRect(WindowAction.center.targetRect(in: visibleFrame), equals: CGRect(x: 1590, y: 128, width: 900, height: 600))
    }

    func testCenterUsesLockedSeventyFivePercentScale() {
        let visibleFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let rect = WindowAction.center.targetRect(in: visibleFrame)

        XCTAssertEqual(WindowAction.centerScale, 0.75, accuracy: 0.0001)
        XCTAssertEqual(rect.width, visibleFrame.width * 0.75, accuracy: 0.0001)
        XCTAssertEqual(rect.height, visibleFrame.height * 0.75, accuracy: 0.0001)
        XCTAssertEqual(rect.midX, visibleFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(rect.midY, visibleFrame.midY, accuracy: 0.0001)
    }

    func testHalfRectsPreserveOddWidthBoundaries() {
        let visibleFrame = CGRect(x: 10, y: 20, width: 1441, height: 901)
        let leftRect = WindowAction.leftHalf.targetRect(in: visibleFrame)
        let rightRect = WindowAction.rightHalf.targetRect(in: visibleFrame)

        XCTAssertEqual(leftRect.width, 720.5, accuracy: 0.0001)
        XCTAssertEqual(rightRect.width, 720.5, accuracy: 0.0001)
        XCTAssertEqual(leftRect.minX, visibleFrame.minX, accuracy: 0.0001)
        XCTAssertEqual(leftRect.maxX, visibleFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(rightRect.minX, visibleFrame.midX, accuracy: 0.0001)
        XCTAssertEqual(rightRect.maxX, visibleFrame.maxX, accuracy: 0.0001)
    }

    func testDisplayNamesAndShortcutKeyLabels() {
        XCTAssertEqual(WindowAction.allCases.map(\.displayName), [
            "Left Half",
            "Right Half",
            "Top Half",
            "Bottom Half",
            "Maximize",
            "Center"
        ])
        XCTAssertEqual(WindowAction.allCases.map(\.shortcutKeyLabel), ["←", "→", "↑", "↓", "Return", "Space"])
    }

    private func assertRect(_ actual: CGRect, equals expected: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.size.width, expected.size.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.size.height, expected.size.height, accuracy: 0.0001, file: file, line: line)
    }
}
