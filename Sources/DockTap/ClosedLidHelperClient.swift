import DockTapClosedLidIPC
import CryptoKit
import Foundation
import ServiceManagement

enum ClosedLidHelperSessionMode: Equatable {
    case timed
    case indefinite
}

struct ClosedLidHelperSession: Equatable {
    let token: String
    let mode: ClosedLidHelperSessionMode
    let endDate: Date?
}

enum ClosedLidHelperPreparationResult: Equatable {
    case ready
    case requiresApproval
    case notFound(String)
    case unsafeActiveSession(String)
    case failure(String)
}

enum ClosedLidHelperStartResult: Equatable {
    case started(ClosedLidHelperSession)
    case alreadyActive(ClosedLidHelperSession)
    case failedWithActiveSession(ClosedLidHelperSession, String)
    case requiresApproval
    case failure(String)
}

enum ClosedLidHelperRenewResult: Equatable {
    case renewed
    case inactive
    case requiresApproval
    case failure(String)
}

enum ClosedLidHelperStopResult: Equatable {
    case stopped
    case requiresApproval
    case failure(String)
}

enum ClosedLidHelperStatusResult: Equatable {
    case inactive
    case active(ClosedLidHelperSession)
    case failureWithActiveSession(ClosedLidHelperSession, String)
    case requiresApproval
    case failure(String)
}

protocol ClosedLidServiceManaging: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: ClosedLidServiceManaging {}

protocol ClosedLidHelperClienting: AnyObject {
    func prepareForUse(completion: @escaping (ClosedLidHelperPreparationResult) -> Void)
    func start(duration: TimeInterval?, completion: @escaping (ClosedLidHelperStartResult) -> Void)
    func renewLease(token: String, completion: @escaping (ClosedLidHelperRenewResult) -> Void)
    func stop(token: String?, reason: String, completion: @escaping (ClosedLidHelperStopResult) -> Void)
    func status(completion: @escaping (ClosedLidHelperStatusResult) -> Void)
    func openApprovalSettings()
    func invalidate()
}

private enum ReregistrationReadiness {
    case inactiveOrRestored
    case blocked(ClosedLidHelperPreparationResult)
}

final class ClosedLidHelperClient: ClosedLidHelperClienting {
    private static let daemonPlistName = "\(ClosedLidIPCConstants.launchDaemonLabel).plist"
    private static let helperExecutableName = "DockTapClosedLidHelper"
    private static let registeredGenerationKey = "closedLidHelperRegisteredGeneration"

    private let service: any ClosedLidServiceManaging
    private let defaults: UserDefaults
    private let logStore: LogStore
    private let reregistrationStatusProvider: ((@escaping (ClosedLidHelperStatusResult) -> Void) -> Void)?
    private let reregistrationStopper: ((String, String, @escaping (ClosedLidHelperStopResult) -> Void) -> Void)?
    private let reregistrationWaitTimeout: TimeInterval
    private let registrationQueue = DispatchQueue(label: "ai.resopod.docktap.closedlidhelper.registration")

    private var connection: NSXPCConnection?

    init(
        service: any ClosedLidServiceManaging = SMAppService.daemon(plistName: ClosedLidHelperClient.daemonPlistName),
        defaults: UserDefaults = .standard,
        logStore: LogStore,
        reregistrationStatusProvider: ((@escaping (ClosedLidHelperStatusResult) -> Void) -> Void)? = nil,
        reregistrationStopper: ((String, String, @escaping (ClosedLidHelperStopResult) -> Void) -> Void)? = nil,
        reregistrationWaitTimeout: TimeInterval = 5
    ) {
        self.service = service
        self.defaults = defaults
        self.logStore = logStore
        self.reregistrationStatusProvider = reregistrationStatusProvider
        self.reregistrationStopper = reregistrationStopper
        self.reregistrationWaitTimeout = reregistrationWaitTimeout
    }

    func prepareForUse(completion: @escaping (ClosedLidHelperPreparationResult) -> Void) {
        registrationQueue.async { [weak self] in
            guard let self else { return }
            let result = self.prepareForUseOnRegistrationQueue()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func start(duration: TimeInterval?, completion: @escaping (ClosedLidHelperStartResult) -> Void) {
        guard let proxy = helperProxy(errorHandler: { error in
            completion(.failure("helper start failed: \(error.localizedDescription)"))
        }) else {
            completion(.failure("helper connection is unavailable"))
            return
        }

        let durationNumber = duration.map { NSNumber(value: Int($0)) }
        proxy.start(durationSeconds: durationNumber) { [weak self] reply in
            DispatchQueue.main.async {
                completion(self?.startResult(from: reply) ?? .failure("helper client was released"))
            }
        }
    }

    func renewLease(token: String, completion: @escaping (ClosedLidHelperRenewResult) -> Void) {
        guard let proxy = helperProxy(errorHandler: { error in
            completion(.failure("helper renewal failed: \(error.localizedDescription)"))
        }) else {
            completion(.failure("helper connection is unavailable"))
            return
        }

        proxy.renewLease(tokenString: token as NSString) { [weak self] reply in
            DispatchQueue.main.async {
                completion(self?.renewResult(from: reply) ?? .failure("helper client was released"))
            }
        }
    }

    func stop(token: String?, reason: String, completion: @escaping (ClosedLidHelperStopResult) -> Void) {
        guard let token, !token.isEmpty else {
            status { [weak self] result in
                switch result {
                case .inactive:
                    completion(.stopped)
                case .active(let session):
                    self?.stop(token: session.token, reason: reason, completion: completion)
                case .failureWithActiveSession(let session, _):
                    self?.stop(token: session.token, reason: reason, completion: completion)
                case .requiresApproval:
                    completion(.requiresApproval)
                case .failure(let message):
                    completion(.failure(message))
                }
            }
            return
        }

        guard let proxy = helperProxy(errorHandler: { error in
            completion(.failure("helper stop failed: \(error.localizedDescription)"))
        }) else {
            completion(.failure("helper connection is unavailable"))
            return
        }

        proxy.stop(tokenString: token as NSString, reasonString: reason as NSString) { [weak self] reply in
            DispatchQueue.main.async {
                completion(self?.stopResult(from: reply) ?? .failure("helper client was released"))
            }
        }
    }

    func status(completion: @escaping (ClosedLidHelperStatusResult) -> Void) {
        switch service.status {
        case .notRegistered, .notFound:
            completion(.inactive)
            return
        case .requiresApproval:
            completion(.requiresApproval)
            return
        case .enabled:
            break
        @unknown default:
            completion(.failure("helper status is unknown"))
            return
        }

        guard let proxy = helperProxy(errorHandler: { error in
            completion(.failure("helper status failed: \(error.localizedDescription)"))
        }) else {
            completion(.failure("helper connection is unavailable"))
            return
        }

        proxy.status { [weak self] reply in
            DispatchQueue.main.async {
                completion(self?.statusResult(from: reply) ?? .failure("helper client was released"))
            }
        }
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func invalidate() {
        connection?.invalidate()
        connection = nil
    }

    private func prepareForUseOnRegistrationQueue() -> ClosedLidHelperPreparationResult {
        switch service.status {
        case .enabled:
            guard registeredHelperGenerationMatches else {
                return reregisterHelper()
            }
            return .ready
        case .notRegistered, .notFound:
            return registerHelper()
        case .requiresApproval:
            return .requiresApproval
        @unknown default:
            return .failure("helper status is unknown")
        }
    }

    private func registerHelper() -> ClosedLidHelperPreparationResult {
        do {
            try service.register()
            return confirmedRegistrationResult()
        } catch {
            return registrationFailureResult(error)
        }
    }

    private func reregisterHelper() -> ClosedLidHelperPreparationResult {
        switch proveOldHelperInactiveOrRestored() {
        case .inactiveOrRestored:
            invalidate()
        case .blocked(let result):
            return result
        }

        do {
            try service.unregister()
        } catch {
            return .failure("helper re-registration failed while unregistering old helper: \(error.localizedDescription)")
        }

        do {
            try service.register()
            let result = confirmedRegistrationResult()
            if case .ready = result {
                logStore.append("closed-lid helper re-registered generation=\(bundledHelperGeneration)")
            }
            return result
        } catch {
            return registrationFailureResult(error, shouldAcceptAlreadyRegistered: false)
        }
    }

    private func proveOldHelperInactiveOrRestored() -> ReregistrationReadiness {
        guard let status = waitForOldHelperStatus() else {
            return reregistrationBlocked("helper re-registration blocked: old helper status timed out")
        }

        switch status {
        case .inactive:
            return .inactiveOrRestored
        case .active(let session):
            return stopOldHelperBeforeReregistration(session)
        case .failureWithActiveSession(let session, let message):
            logStore.append("closed-lid helper re-registration status failed with active session: \(message)")
            return stopOldHelperBeforeReregistration(session)
        case .requiresApproval:
            return reregistrationBlocked("helper re-registration blocked: old helper requires approval before it can be stopped")
        case .failure(let message):
            return reregistrationBlocked("helper re-registration blocked: could not verify old helper status: \(message)")
        }
    }

    private func stopOldHelperBeforeReregistration(_ session: ClosedLidHelperSession) -> ReregistrationReadiness {
        guard let result = waitForOldHelperStop(token: session.token) else {
            return reregistrationBlocked("helper re-registration blocked: old helper stop timed out")
        }

        switch result {
        case .stopped:
            logStore.append("closed-lid helper old generation stopped before re-registration")
            return .inactiveOrRestored
        case .requiresApproval:
            return reregistrationBlocked("helper re-registration blocked: old helper requires approval before it can be stopped")
        case .failure(let message):
            return reregistrationBlocked("helper re-registration blocked: old helper stop failed: \(message)")
        }
    }

    private func waitForOldHelperStatus() -> ClosedLidHelperStatusResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ClosedLidHelperStatusResult?

        let provider: (@escaping (ClosedLidHelperStatusResult) -> Void) -> Void
        if let reregistrationStatusProvider {
            provider = reregistrationStatusProvider
        } else {
            provider = { [weak self] (completion: @escaping (ClosedLidHelperStatusResult) -> Void) in
                guard let self else {
                    completion(.failure("helper client was released"))
                    return
                }
                self.status(completion: completion)
            }
        }
        provider {
            result = $0
            semaphore.signal()
        }

        guard semaphore.wait(timeout: reregistrationTimeout) == .success else {
            return nil
        }
        return result
    }

    private func waitForOldHelperStop(token: String) -> ClosedLidHelperStopResult? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: ClosedLidHelperStopResult?

        let stopper: (String, String, @escaping (ClosedLidHelperStopResult) -> Void) -> Void
        if let reregistrationStopper {
            stopper = reregistrationStopper
        } else {
            stopper = { [weak self] token, reason, completion in
                guard let self else {
                    completion(.failure("helper client was released"))
                    return
                }
                self.stop(token: token, reason: reason, completion: completion)
            }
        }
        stopper(token, "helperReregistration") {
            result = $0
            semaphore.signal()
        }

        guard semaphore.wait(timeout: reregistrationTimeout) == .success else {
            return nil
        }
        return result
    }

    private var reregistrationTimeout: DispatchTime {
        .now() + .milliseconds(Int(reregistrationWaitTimeout * 1_000))
    }

    private func reregistrationBlocked(_ message: String) -> ReregistrationReadiness {
        .blocked(.unsafeActiveSession(message))
    }

    private func resultAfterRegistration() -> ClosedLidHelperPreparationResult {
        switch service.status {
        case .enabled:
            return .ready
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .failure("helper registration did not remain registered")
        case .notFound:
            return .notFound("helper LaunchDaemon plist was not found in the app bundle")
        @unknown default:
            return .failure("helper status is unknown after registration")
        }
    }

    private func confirmedRegistrationResult() -> ClosedLidHelperPreparationResult {
        let result = resultAfterRegistration()
        switch result {
        case .ready, .requiresApproval:
            rememberRegisteredGeneration()
        case .notFound, .unsafeActiveSession, .failure:
            break
        }
        return result
    }

    private func registrationFailureResult(
        _ error: Error,
        shouldAcceptAlreadyRegistered: Bool = true
    ) -> ClosedLidHelperPreparationResult {
        let nsError = error as NSError
        if nsError.code == Int(kSMErrorLaunchDeniedByUser) {
            rememberRegisteredGeneration()
            return .requiresApproval
        }
        if nsError.code == Int(kSMErrorAlreadyRegistered) {
            guard shouldAcceptAlreadyRegistered else {
                return .failure("helper re-registration failed: helper was still registered after unregister")
            }
            return confirmedRegistrationResult()
        }
        return .failure("helper registration failed: \(error.localizedDescription)")
    }

    private var registeredHelperGenerationMatches: Bool {
        defaults.string(forKey: Self.registeredGenerationKey) == bundledHelperGeneration
    }

    private func rememberRegisteredGeneration() {
        defaults.set(bundledHelperGeneration, forKey: Self.registeredGenerationKey)
    }

    private var bundledHelperGeneration: String {
        [
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown-build",
            fingerprint(
                Bundle.main.bundleURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Library")
                    .appendingPathComponent("LaunchDaemons")
                    .appendingPathComponent(Self.daemonPlistName)
            ),
            fingerprint(
                Bundle.main.bundleURL
                    .appendingPathComponent("Contents")
                    .appendingPathComponent("Library")
                    .appendingPathComponent("LaunchDaemons")
                    .appendingPathComponent(Self.helperExecutableName)
            )
        ].joined(separator: "|")
    }

    private func fingerprint(_ url: URL) -> String {
        guard
            let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else {
            return "\(url.lastPathComponent):missing"
        }

        let digest = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(url.lastPathComponent):sha256:\(digest)"
    }

    private func helperProxy(errorHandler: @escaping (Error) -> Void) -> ClosedLidHelperXPCProtocol? {
        if connection == nil {
            connectToHelper()
        }

        return connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            self?.logStore.append("closed-lid helper xpc error=\(error.localizedDescription)")
            DispatchQueue.main.async {
                errorHandler(error)
            }
        } as? ClosedLidHelperXPCProtocol
    }

    private func connectToHelper() {
        let newConnection = NSXPCConnection(
            machServiceName: ClosedLidIPCConstants.machServiceName,
            options: .privileged
        )
        newConnection.remoteObjectInterface = ClosedLidXPCInterfaceFactory.makeHelperInterface()
        newConnection.setCodeSigningRequirement(ClosedLidCodeSigningRequirements.helperExecutable)
        newConnection.interruptionHandler = { [weak self] in
            self?.logStore.append("closed-lid helper xpc interrupted")
        }
        newConnection.invalidationHandler = { [weak self] in
            self?.logStore.append("closed-lid helper xpc invalidated")
            self?.connection = nil
        }
        newConnection.resume()
        connection = newConnection
    }

    func startResult(from reply: ClosedLidStartReply) -> ClosedLidHelperStartResult {
        let outcome = ClosedLidResponseOutcome(rawValue: reply.outcome as String)
        switch outcome {
        case .success:
            guard let session = session(from: reply) else {
                return .failure("helper start reply did not include an active lease")
            }
            return .started(session)
        case .alreadyActive:
            guard let session = session(from: reply) else {
                return .failure("helper already-active reply did not include an active lease")
            }
            return .alreadyActive(session)
        case .requiresApproval:
            return .requiresApproval
        case .restoreFailed:
            guard let session = session(from: reply) else {
                return .failure(reply.errorMessage as String? ?? "helper start failed and normal sleep restore was not confirmed")
            }
            return .failedWithActiveSession(
                session,
                reply.errorMessage as String? ?? "helper start failed and normal sleep restore was not confirmed"
            )
        default:
            return .failure(reply.errorMessage as String? ?? "helper start failed")
        }
    }

    private func renewResult(from reply: ClosedLidLeaseReply) -> ClosedLidHelperRenewResult {
        let outcome = ClosedLidResponseOutcome(rawValue: reply.outcome as String)
        switch outcome {
        case .success:
            return .renewed
        case .inactive, .invalidToken, .expired:
            return .inactive
        case .requiresApproval:
            return .requiresApproval
        default:
            return .failure(reply.errorMessage as String? ?? "helper renewal failed")
        }
    }

    private func stopResult(from reply: ClosedLidStopReply) -> ClosedLidHelperStopResult {
        let outcome = ClosedLidResponseOutcome(rawValue: reply.outcome as String)
        switch outcome {
        case .success where reply.pmsetRestoreConfirmed.boolValue:
            return .stopped
        case .inactive:
            return .stopped
        case .requiresApproval:
            return .requiresApproval
        default:
            return .failure(reply.errorMessage as String? ?? "helper did not confirm pmset disablesleep 0")
        }
    }

    func statusResult(from reply: ClosedLidStatusReply) -> ClosedLidHelperStatusResult {
        let state = ClosedLidStatusState(rawValue: reply.stateString as String)
        switch state {
        case .off:
            return .inactive
        case .activeTimed, .activeIndefinite:
            guard let session = session(from: reply) else {
                return .failure("helper status did not include an active lease")
            }
            return .active(session)
        case .requiresApproval:
            return .requiresApproval
        case .error:
            let message = reply.errorMessage as String? ?? "helper status failed"
            if reply.isActive.boolValue, let session = session(from: reply) {
                return .failureWithActiveSession(session, message)
            }
            return .failure(message)
        default:
            return .failure(reply.errorMessage as String? ?? "helper status was not recognized")
        }
    }

    private func session(from reply: ClosedLidStartReply) -> ClosedLidHelperSession? {
        session(
            tokenString: reply.tokenString,
            modeString: reply.modeString,
            hardExpiryDate: reply.hardExpiryDate
        )
    }

    private func session(from reply: ClosedLidStatusReply) -> ClosedLidHelperSession? {
        session(
            tokenString: reply.tokenString,
            modeString: reply.modeString,
            hardExpiryDate: reply.hardExpiryDate
        )
    }

    private func session(
        tokenString: NSString?,
        modeString: NSString?,
        hardExpiryDate: NSDate?
    ) -> ClosedLidHelperSession? {
        guard let token = tokenString as String? else {
            return nil
        }

        let mode: ClosedLidHelperSessionMode
        switch modeString as String? {
        case ClosedLidSessionMode.timed.rawValue:
            mode = .timed
        case ClosedLidSessionMode.indefinite.rawValue:
            mode = .indefinite
        default:
            mode = hardExpiryDate == nil ? .indefinite : .timed
        }

        return ClosedLidHelperSession(token: token, mode: mode, endDate: hardExpiryDate as Date?)
    }
}
