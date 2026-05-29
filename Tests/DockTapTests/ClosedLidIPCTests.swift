import DockTapClosedLidIPC
import Foundation
import XCTest

final class ClosedLidIPCTests: XCTestCase {
    func testCodeSigningRequirementsUsePinnedIdentifiersAndTeam() {
        XCTAssertEqual(
            ClosedLidCodeSigningRequirements.dockTapApplication,
            #"identifier "ai.resopod.docktap" and anchor apple generic and certificate leaf[subject.OU] = "88DYM3N4W8""#
        )
        XCTAssertEqual(
            ClosedLidCodeSigningRequirements.helperExecutable,
            #"identifier "ai.resopod.docktap.closedlidhelper" and anchor apple generic and certificate leaf[subject.OU] = "88DYM3N4W8""#
        )
    }

    func testClientAndListenerInstallCodeSigningRequirements() throws {
        let clientSource = try sourceFile("Sources/DockTap/ClosedLidHelperClient.swift")
        XCTAssertTrue(
            clientSource.contains("newConnection.setCodeSigningRequirement(ClosedLidCodeSigningRequirements.helperExecutable)")
        )

        let helperMainSource = try sourceFile("Sources/DockTapClosedLidHelper/main.swift")
        XCTAssertTrue(
            helperMainSource.contains(
                "listener.setConnectionCodeSigningRequirement(ClientCodeSigningRequirement.dockTapApplicationRequirement)"
            )
        )
    }

    func testHelperInterfaceWhitelistsOnlySecureReplyClasses() {
        let interface = ClosedLidXPCInterfaceFactory.makeHelperInterface()
        let expectedClasses = Set([
            NSStringFromClass(ClosedLidStartReply.self),
            NSStringFromClass(ClosedLidLeaseReply.self),
            NSStringFromClass(ClosedLidStopReply.self),
            NSStringFromClass(ClosedLidStatusReply.self),
            NSStringFromClass(NSString.self),
            NSStringFromClass(NSNumber.self),
            NSStringFromClass(NSDate.self),
            NSStringFromClass(NSData.self),
            NSStringFromClass(NSNull.self)
        ])

        let selectors = [
            #selector(ClosedLidHelperXPCProtocol.start(durationSeconds:completion:)),
            #selector(ClosedLidHelperXPCProtocol.renewLease(tokenString:completion:)),
            #selector(ClosedLidHelperXPCProtocol.stop(tokenString:reasonString:completion:)),
            #selector(ClosedLidHelperXPCProtocol.status(completion:))
        ]

        for selector in selectors {
            XCTAssertEqual(replyClassNames(for: selector, in: interface), expectedClasses)
        }
    }

    func testRepliesRoundTripWithSecureCodingWhitelist() throws {
        XCTAssertTrue(ClosedLidStartReply.supportsSecureCoding)
        XCTAssertTrue(ClosedLidLeaseReply.supportsSecureCoding)
        XCTAssertTrue(ClosedLidStopReply.supportsSecureCoding)
        XCTAssertTrue(ClosedLidStatusReply.supportsSecureCoding)

        let date = Date(timeIntervalSinceReferenceDate: 12_345) as NSDate
        let replies: [NSObject] = [
            ClosedLidStartReply(
                outcome: ClosedLidResponseOutcome.success.rawValue as NSString,
                tokenString: "start-token",
                modeString: ClosedLidSessionMode.timed.rawValue as NSString,
                hardExpiryDate: date,
                leaseDeadlineDate: date,
                lastRenewalDate: date,
                alreadyActive: false
            ),
            ClosedLidLeaseReply(
                outcome: ClosedLidResponseOutcome.success.rawValue as NSString,
                tokenString: "lease-token",
                hardExpiryDate: date,
                leaseDeadlineDate: date,
                lastRenewalDate: date
            ),
            ClosedLidStopReply(
                outcome: ClosedLidResponseOutcome.success.rawValue as NSString,
                tokenString: "stop-token",
                stoppedAtDate: date,
                pmsetRestoreConfirmed: true
            ),
            ClosedLidStatusReply(
                stateString: ClosedLidStatusState.activeIndefinite.rawValue as NSString,
                tokenString: "status-token",
                modeString: ClosedLidSessionMode.indefinite.rawValue as NSString,
                leaseDeadlineDate: date,
                lastRenewalDate: date,
                isActive: true
            )
        ]

        for reply in replies {
            let data = try NSKeyedArchiver.archivedData(withRootObject: reply, requiringSecureCoding: true)
            let decoded = try NSKeyedUnarchiver.unarchivedObject(
                ofClasses: secureCodingAllowedClasses,
                from: data
            ) as? NSObject
            XCTAssertTrue(decoded?.isKind(of: type(of: reply)) == true)
        }
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceFile(_ path: String) throws -> String {
        try String(contentsOf: packageRoot.appendingPathComponent(path), encoding: .utf8)
    }

    private func replyClassNames(for selector: Selector, in interface: NSXPCInterface) -> Set<String> {
        let classes = interface.classes(for: selector, argumentIndex: 0, ofReply: true)
        return Set(classes.compactMap { item in
            guard let objectClass = item.base as? AnyClass else {
                return nil
            }
            return NSStringFromClass(objectClass)
        })
    }

    private var secureCodingAllowedClasses: [AnyClass] {
        [
            ClosedLidStartReply.self,
            ClosedLidLeaseReply.self,
            ClosedLidStopReply.self,
            ClosedLidStatusReply.self,
            NSString.self,
            NSNumber.self,
            NSDate.self,
            NSData.self,
            NSNull.self
        ]
    }
}
