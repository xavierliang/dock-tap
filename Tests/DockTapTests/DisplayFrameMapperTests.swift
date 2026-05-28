import CoreGraphics
import XCTest
@testable import DockTap

final class DisplayFrameMapperTests: XCTestCase {
    func testOriginZeroScreenWinsCoordinateAnchor() {
        let snapshots = [
            snapshot(name: "First", frame: CGRect(x: -1440, y: 0, width: 1440, height: 900)),
            snapshot(name: "Anchor", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), scaleFactor: 2),
            snapshot(name: "Right", frame: CGRect(x: 1920, y: 200, width: 1440, height: 900))
        ]

        let displays = DisplayFrameMapper.displayFrames(from: snapshots)

        XCTAssertEqual(displays.map(\.isCoordinateAnchor), [false, true, false])
        XCTAssertEqual(displays[1].identifier, "Anchor")
        XCTAssertEqual(displays[1].frame, snapshots[1].frame)
        XCTAssertEqual(displays[1].visibleFrame, snapshots[1].visibleFrame)
        XCTAssertEqual(displays[1].scaleFactor, 2)
        XCTAssertFalse(DisplayFrameMapper.usesFallbackAnchor(in: snapshots))
    }

    func testFallsBackToFirstScreenWhenNoOriginZeroScreenExists() {
        let snapshots = [
            snapshot(name: "Fallback", frame: CGRect(x: 10, y: 20, width: 1440, height: 900)),
            snapshot(name: "Second", frame: CGRect(x: 1450, y: 20, width: 1440, height: 900))
        ]

        let displays = DisplayFrameMapper.displayFrames(from: snapshots)

        XCTAssertEqual(displays.map(\.isCoordinateAnchor), [true, false])
        XCTAssertEqual(displays[0].identifier, "Fallback")
        XCTAssertTrue(DisplayFrameMapper.usesFallbackAnchor(in: snapshots))
    }

    func testMappingDoesNotCacheCoordinateAnchorAcrossCalls() {
        let firstDisplays = DisplayFrameMapper.displayFrames(from: [
            snapshot(name: "First", frame: CGRect(x: 10, y: 0, width: 1440, height: 900)),
            snapshot(name: "Second", frame: CGRect(x: 1450, y: 0, width: 1440, height: 900))
        ])
        let secondDisplays = DisplayFrameMapper.displayFrames(from: [
            snapshot(name: "First", frame: CGRect(x: 10, y: 0, width: 1440, height: 900)),
            snapshot(name: "Second", frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        ])

        XCTAssertEqual(anchorIdentifiers(in: firstDisplays), ["First"])
        XCTAssertEqual(anchorIdentifiers(in: secondDisplays), ["Second"])
    }

    private func snapshot(
        name: String,
        frame: CGRect,
        visibleFrame: CGRect? = nil,
        scaleFactor: CGFloat? = nil
    ) -> WindowScreenSnapshot {
        WindowScreenSnapshot(
            frame: frame,
            visibleFrame: visibleFrame ?? frame.insetBy(dx: 0, dy: 20),
            name: name,
            scaleFactor: scaleFactor
        )
    }

    private func anchorIdentifiers(in displays: [DisplayFrame]) -> [String] {
        displays
            .filter(\.isCoordinateAnchor)
            .compactMap(\.identifier)
    }
}
