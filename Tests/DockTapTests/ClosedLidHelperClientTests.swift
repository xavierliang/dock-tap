import DockTapClosedLidIPC
import ServiceManagement
import XCTest
@testable import DockTap

final class ClosedLidHelperClientTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var service: FakeClosedLidService!
    private var client: ClosedLidHelperClient!
    private var reregistrationStatusResults: [ClosedLidHelperStatusResult]!
    private var reregistrationStopResults: [ClosedLidHelperStopResult]!
    private var reregistrationStopTokens: [String]!
    private var reregistrationStopReasons: [String]!
    private var reregistrationEvents: [String]!

    override func setUp() {
        super.setUp()
        suiteName = "DockTapTests.ClosedLidHelperClient.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        service = FakeClosedLidService(status: .enabled)
        reregistrationStatusResults = [.inactive]
        reregistrationStopResults = [.stopped]
        reregistrationStopTokens = []
        reregistrationStopReasons = []
        reregistrationEvents = []
        service.eventRecorder = { [weak self] event in
            self?.reregistrationEvents.append(event)
        }
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore(),
            reregistrationStatusProvider: { [weak self] completion in
                self?.reregistrationEvents.append("status")
                guard let self else {
                    completion(.failure("test client released"))
                    return
                }
                completion(self.reregistrationStatusResults.removeFirstOrDefault(.inactive))
            },
            reregistrationStopper: { [weak self] token, reason, completion in
                self?.reregistrationEvents.append("stop")
                self?.reregistrationStopTokens.append(token)
                self?.reregistrationStopReasons.append(reason)
                guard let self else {
                    completion(.failure("test client released"))
                    return
                }
                completion(self.reregistrationStopResults.removeFirstOrDefault(.stopped))
            }
        )
    }

    override func tearDown() {
        client.invalidate()
        defaults.removePersistentDomain(forName: suiteName)
        client = nil
        service = nil
        defaults = nil
        suiteName = nil
        reregistrationStatusResults = nil
        reregistrationStopResults = nil
        reregistrationStopTokens = nil
        reregistrationStopReasons = nil
        reregistrationEvents = nil
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

    func testPrepareRegistersWhenServiceStatusIsNotFound() {
        service.status = .notFound

        let result = prepareForUse()

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertNotNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
    }

    func testPrepareReturnsNotFoundAfterRegisterWhenStatusRemainsNotFound() {
        service.status = .notFound
        service.statusAfterRegister = .notFound

        let result = prepareForUse()

        guard case .notFound(let message) = result else {
            XCTFail("Expected notFound, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("helper LaunchDaemon plist"))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
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

    func testReregisterStopsActiveOldHelperBeforeUnregistering() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.active(.indefinite(token: "old-token"))]

        let result = prepareForUse()

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(reregistrationStopTokens, ["old-token"])
        XCTAssertEqual(reregistrationStopReasons, ["helperReregistration"])
        XCTAssertEqual(reregistrationEvents, ["status", "stop", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testReregisterReturnsUnsafeActiveSessionWhenOldHelperStatusFails() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]

        let result = prepareForUse()

        guard case .unsafeActiveSession(let message) = result else {
            XCTFail("Expected unsafe active session, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("could not verify old helper status"))
        XCTAssertEqual(reregistrationEvents, ["status"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testReregisterReturnsUnsafeActiveSessionWhenActiveOldHelperCannotStop() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.active(.indefinite(token: "old-token"))]
        reregistrationStopResults = [.failure("restore failed")]

        let result = prepareForUse()

        guard case .unsafeActiveSession(let message) = result else {
            XCTFail("Expected unsafe active session, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("old helper stop failed"))
        XCTAssertEqual(reregistrationStopTokens, ["old-token"])
        XCTAssertEqual(reregistrationEvents, ["status", "stop"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
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
    var statusAfterRegister: SMAppService.Status = .enabled
    var registerError: Error?
    var unregisterError: Error?
    var eventRecorder: ((String) -> Void)?

    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        eventRecorder?("register")
        if let registerError {
            throw registerError
        }
        status = statusAfterRegister
    }

    func unregister() throws {
        unregisterCallCount += 1
        eventRecorder?("unregister")
        if let unregisterError {
            throw unregisterError
        }
        status = .notRegistered
    }
}

private extension Array {
    mutating func removeFirstOrDefault(_ defaultValue: Element) -> Element {
        isEmpty ? defaultValue : removeFirst()
    }
}

private extension ClosedLidHelperSession {
    static func indefinite(token: String) -> ClosedLidHelperSession {
        ClosedLidHelperSession(token: token, mode: .indefinite, endDate: nil)
    }
}
