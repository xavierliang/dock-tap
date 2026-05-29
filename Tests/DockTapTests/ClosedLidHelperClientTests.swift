import DockTapClosedLidIPC
import ServiceManagement
import XCTest
@testable import DockTap

final class ClosedLidHelperClientTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var service: FakeClosedLidService!
    private var client: ClosedLidHelperClient!

    override func setUp() {
        super.setUp()
        suiteName = "DockTapTests.ClosedLidHelperClient.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        service = FakeClosedLidService(status: .enabled)
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore()
        )
    }

    override func tearDown() {
        client.invalidate()
        defaults.removePersistentDomain(forName: suiteName)
        client = nil
        service = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testStartRestoreFailedWithLeasePreservesActiveSession() {
        let reply = ClosedLidStartReply(
            outcome: ClosedLidResponseOutcome.restoreFailed.rawValue as NSString,
            tokenString: "restore-token",
            modeString: ClosedLidSessionMode.indefinite.rawValue as NSString,
            errorMessage: "pmset disablesleep 1 succeeded but restore failed"
        )

        XCTAssertEqual(
            client.startResult(from: reply),
            .failedWithActiveSession(
                ClosedLidHelperSession(token: "restore-token", mode: .indefinite, endDate: nil),
                "pmset disablesleep 1 succeeded but restore failed"
            )
        )
    }

    func testStatusErrorWithActiveLeasePreservesActiveSession() {
        let endDate = Date(timeIntervalSinceReferenceDate: 42_000)
        let reply = ClosedLidStatusReply(
            stateString: ClosedLidStatusState.error.rawValue as NSString,
            tokenString: "status-token",
            modeString: ClosedLidSessionMode.timed.rawValue as NSString,
            hardExpiryDate: endDate as NSDate,
            isActive: true,
            errorMessage: "helper reports restore failed"
        )

        XCTAssertEqual(
            client.statusResult(from: reply),
            .failureWithActiveSession(
                ClosedLidHelperSession(token: "status-token", mode: .timed, endDate: endDate),
                "helper reports restore failed"
            )
        )
    }

    func testReregisterFailsWhenUnregisterFails() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        service.unregisterError = NSError(domain: "DockTapTests", code: 47)

        let result = prepareForUse()

        guard case .failure(let message) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("unregistering old helper"))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testReregisterDoesNotRememberBundledGenerationWhenRegisterReportsAlreadyRegistered() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        service.registerError = NSError(domain: "DockTapTests", code: Int(kSMErrorAlreadyRegistered))

        let result = prepareForUse()

        guard case .failure(let message) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("still registered"))
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    private func prepareForUse(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ClosedLidHelperPreparationResult {
        let exp = expectation(description: "prepareForUse completes")
        var result: ClosedLidHelperPreparationResult?

        client.prepareForUse {
            result = $0
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        guard let result else {
            XCTFail("prepareForUse did not complete", file: file, line: line)
            return .failure("missing test result")
        }
        return result
    }
}

private final class FakeClosedLidService: ClosedLidServiceManaging {
    var status: SMAppService.Status
    var registerError: Error?
    var unregisterError: Error?

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        status = .enabled
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}
