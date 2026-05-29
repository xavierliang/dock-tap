import Foundation

public enum ClosedLidIPCConstants {
    public static let machServiceName = "ai.resopod.docktap.closedlidhelper.xpc"
    public static let launchDaemonLabel = "ai.resopod.docktap.closedlidhelper"
    public static let appBundleIdentifier = "ai.resopod.docktap"
    public static let helperCodeSigningIdentifier = "ai.resopod.docktap.closedlidhelper"
    public static let teamIdentifier = "88DYM3N4W8"
    public static let renewalIntervalSeconds: TimeInterval = 30
    public static let leaseTimeToLiveSeconds: TimeInterval = 90
}

public enum ClosedLidCodeSigningRequirements {
    public static var dockTapApplication: String {
        #"identifier "\#(ClosedLidIPCConstants.appBundleIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(ClosedLidIPCConstants.teamIdentifier)""#
    }

    public static var helperExecutable: String {
        #"identifier "\#(ClosedLidIPCConstants.helperCodeSigningIdentifier)" and anchor apple generic and certificate leaf[subject.OU] = "\#(ClosedLidIPCConstants.teamIdentifier)""#
    }
}

public struct ClosedLidResponseOutcome: RawRepresentable, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let success = Self(rawValue: "success")
    public static let alreadyActive = Self(rawValue: "alreadyActive")
    public static let inactive = Self(rawValue: "inactive")
    public static let invalidToken = Self(rawValue: "invalidToken")
    public static let expired = Self(rawValue: "expired")
    public static let pmsetFailed = Self(rawValue: "pmsetFailed")
    public static let restoreFailed = Self(rawValue: "restoreFailed")
    public static let requiresApproval = Self(rawValue: "requiresApproval")
    public static let error = Self(rawValue: "error")
}

public struct ClosedLidSessionMode: RawRepresentable, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let timed = Self(rawValue: "timed")
    public static let indefinite = Self(rawValue: "indefinite")
}

public struct ClosedLidStatusState: RawRepresentable, Equatable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let off = Self(rawValue: "off")
    public static let activeTimed = Self(rawValue: "activeTimed")
    public static let activeIndefinite = Self(rawValue: "activeIndefinite")
    public static let requiresApproval = Self(rawValue: "requiresApproval")
    public static let error = Self(rawValue: "error")
}

@objc(DTClosedLidHelperXPCProtocol)
public protocol ClosedLidHelperXPCProtocol {
    @objc(startWithDurationSeconds:completion:)
    func start(durationSeconds: NSNumber?, completion: @escaping (ClosedLidStartReply) -> Void)

    @objc(renewLeaseWithTokenString:completion:)
    func renewLease(tokenString: NSString, completion: @escaping (ClosedLidLeaseReply) -> Void)

    @objc(stopWithTokenString:reasonString:completion:)
    func stop(tokenString: NSString, reasonString: NSString, completion: @escaping (ClosedLidStopReply) -> Void)

    @objc(statusWithCompletion:)
    func status(completion: @escaping (ClosedLidStatusReply) -> Void)
}

public enum ClosedLidXPCInterfaceFactory {
    public static func makeHelperInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: ClosedLidHelperXPCProtocol.self)
        let replyClasses = NSSet(objects:
            ClosedLidStartReply.self,
            ClosedLidLeaseReply.self,
            ClosedLidStopReply.self,
            ClosedLidStatusReply.self,
            NSString.self,
            NSNumber.self,
            NSDate.self,
            NSData.self,
            NSNull.self
        ) as! Set<AnyHashable>

        interface.setClasses(
            replyClasses,
            for: #selector(ClosedLidHelperXPCProtocol.start(durationSeconds:completion:)),
            argumentIndex: 0,
            ofReply: true
        )
        interface.setClasses(
            replyClasses,
            for: #selector(ClosedLidHelperXPCProtocol.renewLease(tokenString:completion:)),
            argumentIndex: 0,
            ofReply: true
        )
        interface.setClasses(
            replyClasses,
            for: #selector(ClosedLidHelperXPCProtocol.stop(tokenString:reasonString:completion:)),
            argumentIndex: 0,
            ofReply: true
        )
        interface.setClasses(
            replyClasses,
            for: #selector(ClosedLidHelperXPCProtocol.status(completion:)),
            argumentIndex: 0,
            ofReply: true
        )

        return interface
    }
}

@objcMembers
public final class ClosedLidStartReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let outcome: NSString
    public let tokenString: NSString?
    public let modeString: NSString?
    public let hardExpiryDate: NSDate?
    public let leaseDeadlineDate: NSDate?
    public let lastRenewalDate: NSDate?
    public let alreadyActive: NSNumber
    public let errorMessage: NSString?

    public init(
        outcome: NSString,
        tokenString: NSString? = nil,
        modeString: NSString? = nil,
        hardExpiryDate: NSDate? = nil,
        leaseDeadlineDate: NSDate? = nil,
        lastRenewalDate: NSDate? = nil,
        alreadyActive: NSNumber = false,
        errorMessage: NSString? = nil
    ) {
        self.outcome = outcome
        self.tokenString = tokenString
        self.modeString = modeString
        self.hardExpiryDate = hardExpiryDate
        self.leaseDeadlineDate = leaseDeadlineDate
        self.lastRenewalDate = lastRenewalDate
        self.alreadyActive = alreadyActive
        self.errorMessage = errorMessage
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        let outcome = coder.decodeObject(of: NSString.self, forKey: CodingKeys.outcome) ?? ClosedLidResponseOutcome.error.rawValue as NSString
        self.init(
            outcome: outcome,
            tokenString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.tokenString),
            modeString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.modeString),
            hardExpiryDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.hardExpiryDate),
            leaseDeadlineDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.leaseDeadlineDate),
            lastRenewalDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.lastRenewalDate),
            alreadyActive: coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.alreadyActive) ?? false,
            errorMessage: coder.decodeObject(of: NSString.self, forKey: CodingKeys.errorMessage)
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(outcome, forKey: CodingKeys.outcome)
        coder.encode(tokenString, forKey: CodingKeys.tokenString)
        coder.encode(modeString, forKey: CodingKeys.modeString)
        coder.encode(hardExpiryDate, forKey: CodingKeys.hardExpiryDate)
        coder.encode(leaseDeadlineDate, forKey: CodingKeys.leaseDeadlineDate)
        coder.encode(lastRenewalDate, forKey: CodingKeys.lastRenewalDate)
        coder.encode(alreadyActive, forKey: CodingKeys.alreadyActive)
        coder.encode(errorMessage, forKey: CodingKeys.errorMessage)
    }
}

@objcMembers
public final class ClosedLidLeaseReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let outcome: NSString
    public let tokenString: NSString?
    public let hardExpiryDate: NSDate?
    public let leaseDeadlineDate: NSDate?
    public let lastRenewalDate: NSDate?
    public let errorMessage: NSString?

    public init(
        outcome: NSString,
        tokenString: NSString? = nil,
        hardExpiryDate: NSDate? = nil,
        leaseDeadlineDate: NSDate? = nil,
        lastRenewalDate: NSDate? = nil,
        errorMessage: NSString? = nil
    ) {
        self.outcome = outcome
        self.tokenString = tokenString
        self.hardExpiryDate = hardExpiryDate
        self.leaseDeadlineDate = leaseDeadlineDate
        self.lastRenewalDate = lastRenewalDate
        self.errorMessage = errorMessage
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        let outcome = coder.decodeObject(of: NSString.self, forKey: CodingKeys.outcome) ?? ClosedLidResponseOutcome.error.rawValue as NSString
        self.init(
            outcome: outcome,
            tokenString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.tokenString),
            hardExpiryDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.hardExpiryDate),
            leaseDeadlineDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.leaseDeadlineDate),
            lastRenewalDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.lastRenewalDate),
            errorMessage: coder.decodeObject(of: NSString.self, forKey: CodingKeys.errorMessage)
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(outcome, forKey: CodingKeys.outcome)
        coder.encode(tokenString, forKey: CodingKeys.tokenString)
        coder.encode(hardExpiryDate, forKey: CodingKeys.hardExpiryDate)
        coder.encode(leaseDeadlineDate, forKey: CodingKeys.leaseDeadlineDate)
        coder.encode(lastRenewalDate, forKey: CodingKeys.lastRenewalDate)
        coder.encode(errorMessage, forKey: CodingKeys.errorMessage)
    }
}

@objcMembers
public final class ClosedLidStopReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let outcome: NSString
    public let tokenString: NSString?
    public let stoppedAtDate: NSDate?
    public let pmsetRestoreConfirmed: NSNumber
    public let errorMessage: NSString?

    public init(
        outcome: NSString,
        tokenString: NSString? = nil,
        stoppedAtDate: NSDate? = nil,
        pmsetRestoreConfirmed: NSNumber = false,
        errorMessage: NSString? = nil
    ) {
        self.outcome = outcome
        self.tokenString = tokenString
        self.stoppedAtDate = stoppedAtDate
        self.pmsetRestoreConfirmed = pmsetRestoreConfirmed
        self.errorMessage = errorMessage
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        let outcome = coder.decodeObject(of: NSString.self, forKey: CodingKeys.outcome) ?? ClosedLidResponseOutcome.error.rawValue as NSString
        self.init(
            outcome: outcome,
            tokenString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.tokenString),
            stoppedAtDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.stoppedAtDate),
            pmsetRestoreConfirmed: coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.pmsetRestoreConfirmed) ?? false,
            errorMessage: coder.decodeObject(of: NSString.self, forKey: CodingKeys.errorMessage)
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(outcome, forKey: CodingKeys.outcome)
        coder.encode(tokenString, forKey: CodingKeys.tokenString)
        coder.encode(stoppedAtDate, forKey: CodingKeys.stoppedAtDate)
        coder.encode(pmsetRestoreConfirmed, forKey: CodingKeys.pmsetRestoreConfirmed)
        coder.encode(errorMessage, forKey: CodingKeys.errorMessage)
    }
}

@objcMembers
public final class ClosedLidStatusReply: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    public let stateString: NSString
    public let tokenString: NSString?
    public let modeString: NSString?
    public let hardExpiryDate: NSDate?
    public let leaseDeadlineDate: NSDate?
    public let lastRenewalDate: NSDate?
    public let isActive: NSNumber
    public let errorMessage: NSString?

    public init(
        stateString: NSString,
        tokenString: NSString? = nil,
        modeString: NSString? = nil,
        hardExpiryDate: NSDate? = nil,
        leaseDeadlineDate: NSDate? = nil,
        lastRenewalDate: NSDate? = nil,
        isActive: NSNumber = false,
        errorMessage: NSString? = nil
    ) {
        self.stateString = stateString
        self.tokenString = tokenString
        self.modeString = modeString
        self.hardExpiryDate = hardExpiryDate
        self.leaseDeadlineDate = leaseDeadlineDate
        self.lastRenewalDate = lastRenewalDate
        self.isActive = isActive
        self.errorMessage = errorMessage
        super.init()
    }

    public convenience init?(coder: NSCoder) {
        let state = coder.decodeObject(of: NSString.self, forKey: CodingKeys.stateString) ?? ClosedLidStatusState.error.rawValue as NSString
        self.init(
            stateString: state,
            tokenString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.tokenString),
            modeString: coder.decodeObject(of: NSString.self, forKey: CodingKeys.modeString),
            hardExpiryDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.hardExpiryDate),
            leaseDeadlineDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.leaseDeadlineDate),
            lastRenewalDate: coder.decodeObject(of: NSDate.self, forKey: CodingKeys.lastRenewalDate),
            isActive: coder.decodeObject(of: NSNumber.self, forKey: CodingKeys.isActive) ?? false,
            errorMessage: coder.decodeObject(of: NSString.self, forKey: CodingKeys.errorMessage)
        )
    }

    public func encode(with coder: NSCoder) {
        coder.encode(stateString, forKey: CodingKeys.stateString)
        coder.encode(tokenString, forKey: CodingKeys.tokenString)
        coder.encode(modeString, forKey: CodingKeys.modeString)
        coder.encode(hardExpiryDate, forKey: CodingKeys.hardExpiryDate)
        coder.encode(leaseDeadlineDate, forKey: CodingKeys.leaseDeadlineDate)
        coder.encode(lastRenewalDate, forKey: CodingKeys.lastRenewalDate)
        coder.encode(isActive, forKey: CodingKeys.isActive)
        coder.encode(errorMessage, forKey: CodingKeys.errorMessage)
    }
}

private enum CodingKeys {
    static let outcome = "outcome"
    static let tokenString = "tokenString"
    static let modeString = "modeString"
    static let hardExpiryDate = "hardExpiryDate"
    static let leaseDeadlineDate = "leaseDeadlineDate"
    static let lastRenewalDate = "lastRenewalDate"
    static let alreadyActive = "alreadyActive"
    static let errorMessage = "errorMessage"
    static let stoppedAtDate = "stoppedAtDate"
    static let pmsetRestoreConfirmed = "pmsetRestoreConfirmed"
    static let stateString = "stateString"
    static let isActive = "isActive"
}
