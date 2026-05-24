import XCTest
@testable import DockTap

final class LoginItemControllerTests: XCTestCase {
    func testStatusMapping() {
        XCTAssertEqual(LoginItemController(adapter: FakeLoginItemAdapter(status: .notRegistered)).status(), .disabled)
        XCTAssertEqual(LoginItemController(adapter: FakeLoginItemAdapter(status: .enabled)).status(), .enabled)
        XCTAssertEqual(LoginItemController(adapter: FakeLoginItemAdapter(status: .requiresApproval)).status(), .requiresApproval)
        XCTAssertEqual(LoginItemController(adapter: FakeLoginItemAdapter(status: .notFound)).status(), .notFound)
    }

    func testStatusThrowMapsToErrorDisplay() {
        let controller = LoginItemController(adapter: FakeLoginItemAdapter(statusError: TestError("status failed")))

        XCTAssertEqual(controller.status(), .error("status failed"))
        XCTAssertEqual(controller.status().displayValue, "error: status failed")
    }

    func testRegisterSuccessReportsActualStatus() {
        let adapter = FakeLoginItemAdapter(status: .notRegistered)
        adapter.statusAfterRegister = .enabled
        let controller = LoginItemController(adapter: adapter)

        let result = controller.enable()

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.status, .enabled)
        XCTAssertEqual(adapter.registerCallCount, 1)
    }

    func testRegisterThrowReportsFailureAndActualStatus() {
        let adapter = FakeLoginItemAdapter(status: .notRegistered)
        adapter.registerError = TestError("register failed")
        let controller = LoginItemController(adapter: adapter)

        let result = controller.enable()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, .disabled)
        XCTAssertEqual(result.failureMessage, "failed to enable Launch at Login: register failed")
        XCTAssertEqual(adapter.registerCallCount, 1)
    }

    func testUnregisterThrowReportsFailureAndActualStatus() {
        let adapter = FakeLoginItemAdapter(status: .enabled)
        adapter.unregisterError = TestError("unregister failed")
        let controller = LoginItemController(adapter: adapter)

        let result = controller.disable()

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.status, .enabled)
        XCTAssertEqual(result.failureMessage, "failed to disable Launch at Login: unregister failed")
        XCTAssertEqual(adapter.unregisterCallCount, 1)
    }
}

private final class FakeLoginItemAdapter: LoginItemServiceAdapter {
    var currentStatus: LoginItemServiceStatus
    var statusError: Error?
    var registerError: Error?
    var unregisterError: Error?
    var statusAfterRegister: LoginItemServiceStatus?
    var statusAfterUnregister: LoginItemServiceStatus?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: LoginItemServiceStatus = .notRegistered, statusError: Error? = nil) {
        self.currentStatus = status
        self.statusError = statusError
    }

    func status() throws -> LoginItemServiceStatus {
        if let statusError {
            throw statusError
        }
        return currentStatus
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        if let statusAfterRegister {
            currentStatus = statusAfterRegister
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        if let statusAfterUnregister {
            currentStatus = statusAfterUnregister
        }
    }
}

private struct TestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
