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
    private var sleepDisabledResult: Bool?
    private var sleepDisabledReadCount: Int!

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
        sleepDisabledResult = nil
        sleepDisabledReadCount = 0
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
            },
            sleepDisabledReader: { [weak self] in
                guard let self else {
                    return nil
                }
                self.sleepDisabledReadCount += 1
                return self.sleepDisabledResult
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
        sleepDisabledResult = nil
        sleepDisabledReadCount = nil
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

    func testPrepareRemembersGenerationWhenNotFoundRegistrationRequiresApprovalThenApproved() {
        assertPrepareRemembersGenerationWhenRegistrationRequiresApprovalThenApproved(initialStatus: .notFound)
    }

    func testPrepareRemembersGenerationWhenNotRegisteredRegistrationRequiresApprovalThenApproved() {
        assertPrepareRemembersGenerationWhenRegistrationRequiresApprovalThenApproved(initialStatus: .notRegistered)
    }

    func testPrepareRemembersGenerationWhenNotFoundRegistrationThrowsLaunchDeniedThenApproved() {
        assertPrepareRemembersGenerationWhenRegistrationThrowsLaunchDeniedThenApproved(initialStatus: .notFound)
    }

    func testPrepareRemembersGenerationWhenNotRegisteredRegistrationThrowsLaunchDeniedThenApproved() {
        assertPrepareRemembersGenerationWhenRegistrationThrowsLaunchDeniedThenApproved(initialStatus: .notRegistered)
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
        XCTAssertNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
    }

    func testPrepareReturnsFailureWhenNotFoundServiceRegisterThrows() {
        service.status = .notFound
        service.registerError = NSError(domain: "DockTapTests", code: 48)

        let result = prepareForUse()

        guard case .failure(let message) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("helper registration failed"))
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
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

    func testStatusRepairsStaleGenerationWhenOldHelperStatusFailsAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = false

        let result = status()

        XCTAssertEqual(result, .inactive)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
        XCTAssertNotNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
    }

    func testPrepareRepairsStaleGenerationWhenOldHelperStatusFailsAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = false

        let result = prepareForUse()

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
        XCTAssertNotNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
    }

    func testStopWithoutTokenRepairsStaleGenerationWhenOldHelperStatusFailsAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = false

        let result = stop(token: nil)

        XCTAssertEqual(result, .stopped)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testStopWithTokenRepairsStaleGenerationWhenOldHelperStatusFailsAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = false

        let result = stop(token: "old-token")

        XCTAssertEqual(result, .stopped)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testStopWithTokenReturnsFailureWhenStaleRegistrationCannotBeProvenSafe() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = true

        let result = stop(token: "old-token")

        guard case .failure(let message) = result else {
            XCTFail("Expected failure, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("could not verify old helper status"))
        XCTAssertTrue(message.contains("SleepDisabled is still on"))
        XCTAssertEqual(reregistrationEvents, ["status"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testStatusRepairReturnsUnsafeActiveSessionWhenStaleRegistrationCannotBeProvenSafeWithoutKnownSession() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = true

        let result = status()

        guard case .unsafeActiveSession(let message) = result else {
            XCTFail("Expected unsafeActiveSession, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("could not verify old helper status"))
        XCTAssertTrue(message.contains("SleepDisabled is still on"))
        XCTAssertEqual(reregistrationEvents, ["status"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testStatusRepairPreservesKnownActiveSessionWhenReregistrationIsUnsafe() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        let session = ClosedLidHelperSession.indefinite(token: "old-token")
        reregistrationStatusResults = [.active(session)]
        reregistrationStopResults = [.failure("restore failed")]

        let result = status()

        guard case .failureWithActiveSession(let activeSession, let message) = result else {
            XCTFail("Expected failureWithActiveSession, got \(result)")
            return
        }
        XCTAssertEqual(activeSession, session)
        XCTAssertTrue(message.contains("old helper stop failed"))
        XCTAssertEqual(reregistrationStopTokens, ["old-token"])
        XCTAssertEqual(reregistrationEvents, ["status", "stop"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testStatusRepairDefaultProviderUsesRawStatusWithoutRecursiveDeadlock() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.inactive]
        client.invalidate()
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore(),
            rawStatusProvider: { [weak self] completion in
                self?.reregistrationEvents.append("rawStatus")
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
            },
            sleepDisabledReader: { [weak self] in
                guard let self else {
                    return nil
                }
                self.sleepDisabledReadCount += 1
                return self.sleepDisabledResult
            }
        )

        let result = status()

        XCTAssertEqual(result, .inactive)
        XCTAssertEqual(reregistrationEvents, ["rawStatus", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
    }

    func testStatusRepairDefaultStopperUsesRawStopWithoutInjectedReregistrationStopper() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        let session = ClosedLidHelperSession.indefinite(token: "old-token")
        client.invalidate()
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore(),
            rawStatusProvider: { [weak self] completion in
                self?.reregistrationEvents.append("rawStatus")
                completion(.active(session))
            },
            rawStopProvider: { [weak self] token, reason, completion in
                self?.reregistrationEvents.append("rawStop")
                self?.reregistrationStopTokens.append(token)
                self?.reregistrationStopReasons.append(reason)
                guard let self else {
                    completion(.failure("test client released"))
                    return
                }
                completion(self.reregistrationStopResults.removeFirstOrDefault(.stopped))
            },
            sleepDisabledReader: { [weak self] in
                guard let self else {
                    return nil
                }
                self.sleepDisabledReadCount += 1
                return self.sleepDisabledResult
            }
        )

        let result = status()

        XCTAssertEqual(result, .inactive)
        XCTAssertEqual(reregistrationStopTokens, ["old-token"])
        XCTAssertEqual(reregistrationStopReasons, ["helperReregistration"])
        XCTAssertEqual(reregistrationEvents, ["rawStatus", "rawStop", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testPrepareRepairsStaleGenerationWhenOldHelperStatusTimesOutAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        sleepDisabledResult = false
        client.invalidate()
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore(),
            reregistrationStatusProvider: { [weak self] _ in
                self?.reregistrationEvents.append("status")
            },
            sleepDisabledReader: { [weak self] in
                guard let self else {
                    return nil
                }
                self.sleepDisabledReadCount += 1
                return self.sleepDisabledResult
            },
            reregistrationWaitTimeout: 0.01
        )

        let result = prepareForUse()

        XCTAssertEqual(result, .ready)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
        XCTAssertNotNil(defaults.string(forKey: "closedLidHelperRegisteredGeneration"))
    }

    func testStopWithTokenRepairsStaleGenerationWhenOldHelperStatusTimesOutAndSleepDisabledIsOff() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        sleepDisabledResult = false
        client.invalidate()
        client = ClosedLidHelperClient(
            service: service,
            defaults: defaults,
            logStore: LogStore(),
            reregistrationStatusProvider: { [weak self] _ in
                self?.reregistrationEvents.append("status")
            },
            sleepDisabledReader: { [weak self] in
                guard let self else {
                    return nil
                }
                self.sleepDisabledReadCount += 1
                return self.sleepDisabledResult
            },
            reregistrationWaitTimeout: 0.01
        )

        let result = stop(token: "old-token")

        XCTAssertEqual(result, .stopped)
        XCTAssertEqual(reregistrationEvents, ["status", "unregister", "register"])
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertNotEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testReregisterReturnsUnsafeActiveSessionWhenOldHelperStatusFailsAndSleepDisabledIsOn() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]
        sleepDisabledResult = true

        let result = prepareForUse()

        guard case .unsafeActiveSession(let message) = result else {
            XCTFail("Expected unsafe active session, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("could not verify old helper status"))
        XCTAssertTrue(message.contains("SleepDisabled is still on"))
        XCTAssertEqual(reregistrationEvents, ["status"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(sleepDisabledReadCount, 1)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), "old-generation")
    }

    func testReregisterReturnsUnsafeActiveSessionWhenOldHelperStatusFailsAndSleepDisabledIsUnknown() {
        defaults.set("old-generation", forKey: "closedLidHelperRegisteredGeneration")
        reregistrationStatusResults = [.failure("xpc unavailable")]

        let result = prepareForUse()

        guard case .unsafeActiveSession(let message) = result else {
            XCTFail("Expected unsafe active session, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("could not verify old helper status"))
        XCTAssertTrue(message.contains("Could not verify SleepDisabled is off"))
        XCTAssertEqual(reregistrationEvents, ["status"])
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(sleepDisabledReadCount, 1)
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

    private func assertPrepareRemembersGenerationWhenRegistrationRequiresApprovalThenApproved(
        initialStatus: SMAppService.Status,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        service.status = initialStatus
        service.statusAfterRegister = .requiresApproval

        let firstResult = prepareForUse(file: file, line: line)

        XCTAssertEqual(firstResult, .requiresApproval, file: file, line: line)
        XCTAssertEqual(service.registerCallCount, 1, file: file, line: line)
        XCTAssertEqual(service.unregisterCallCount, 0, file: file, line: line)
        let rememberedGeneration = defaults.string(forKey: "closedLidHelperRegisteredGeneration")
        XCTAssertNotNil(rememberedGeneration, file: file, line: line)

        service.status = .enabled
        reregistrationEvents = []

        let secondResult = prepareForUse(file: file, line: line)

        XCTAssertEqual(secondResult, .ready, file: file, line: line)
        XCTAssertEqual(service.registerCallCount, 1, file: file, line: line)
        XCTAssertEqual(service.unregisterCallCount, 0, file: file, line: line)
        XCTAssertEqual(reregistrationEvents, [], file: file, line: line)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), rememberedGeneration, file: file, line: line)
    }

    private func assertPrepareRemembersGenerationWhenRegistrationThrowsLaunchDeniedThenApproved(
        initialStatus: SMAppService.Status,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        service.status = initialStatus
        service.registerError = NSError(domain: "DockTapTests", code: Int(kSMErrorLaunchDeniedByUser))

        let firstResult = prepareForUse(file: file, line: line)

        XCTAssertEqual(firstResult, .requiresApproval, file: file, line: line)
        XCTAssertEqual(service.registerCallCount, 1, file: file, line: line)
        XCTAssertEqual(service.unregisterCallCount, 0, file: file, line: line)
        let rememberedGeneration = defaults.string(forKey: "closedLidHelperRegisteredGeneration")
        XCTAssertNotNil(rememberedGeneration, file: file, line: line)

        service.registerError = nil
        service.status = .enabled
        reregistrationEvents = []

        let secondResult = prepareForUse(file: file, line: line)

        XCTAssertEqual(secondResult, .ready, file: file, line: line)
        XCTAssertEqual(service.registerCallCount, 1, file: file, line: line)
        XCTAssertEqual(service.unregisterCallCount, 0, file: file, line: line)
        XCTAssertEqual(reregistrationEvents, [], file: file, line: line)
        XCTAssertEqual(defaults.string(forKey: "closedLidHelperRegisteredGeneration"), rememberedGeneration, file: file, line: line)
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

    private func status(
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ClosedLidHelperStatusResult {
        let exp = expectation(description: "status completes")
        var result: ClosedLidHelperStatusResult?

        client.status {
            result = $0
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        guard let result else {
            XCTFail("status did not complete", file: file, line: line)
            return .failure("missing test result")
        }
        return result
    }

    private func stop(
        token: String?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> ClosedLidHelperStopResult {
        let exp = expectation(description: "stop completes")
        var result: ClosedLidHelperStopResult?

        client.stop(token: token, reason: "test") {
            result = $0
            exp.fulfill()
        }

        wait(for: [exp], timeout: 2)
        guard let result else {
            XCTFail("stop did not complete", file: file, line: line)
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
