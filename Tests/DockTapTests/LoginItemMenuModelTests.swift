import XCTest
@testable import DockTap

final class LoginItemMenuModelTests: XCTestCase {
    func testRequiresApprovalAddsVisibleHintWithoutCheckmark() {
        let model = LoginItemMenuModel(status: .requiresApproval, failureMessage: nil)

        XCTAssertEqual(model.title, "Launch at Login (Requires Approval)")
        XCTAssertFalse(model.isChecked)
        XCTAssertEqual(model.hintRows, ["Approve in System Settings > General > Login Items"])
    }

    func testEnabledStatusUsesCheckedPlainTitle() {
        let model = LoginItemMenuModel(status: .enabled, failureMessage: nil)

        XCTAssertEqual(model.title, "Launch at Login")
        XCTAssertTrue(model.isChecked)
        XCTAssertTrue(model.hintRows.isEmpty)
    }

    func testFailureRowKeepsCheckmarkFromActualDisabledStatus() {
        let model = LoginItemMenuModel(
            status: .disabled,
            failureMessage: "failed to enable Launch at Login: register failed"
        )

        XCTAssertEqual(model.title, "Launch at Login")
        XCTAssertFalse(model.isChecked)
        XCTAssertEqual(model.hintRows, ["Launch at Login change failed"])
    }
}
