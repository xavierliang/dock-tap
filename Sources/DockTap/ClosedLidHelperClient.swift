import DockTapClosedLidIPC
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
    case failure(String)
}

enum ClosedLidHelperStartResult: Equatable {
    case started(ClosedLidHelperSession)
    case alreadyActive(ClosedLidHelperSession)
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
    case requiresApproval
    case failure(String)
}

protocol ClosedLidHelperClienting: AnyObject {
    func prepareForUse(completion: @escaping (ClosedLidHelperPreparationResult) -> Void)
    func start(duration: TimeInterval?, completion: @escaping (ClosedLidHelperStartResult) -> Void)
    func renewLease(token: String, completion: @escaping (ClosedLidHelperRenewResult) -> Void)
    func stop(token: String?, reason: String, completion: @escaping (ClosedLidHelperStopResult) -> Void)
    func status(completion: @escaping (ClosedLidHelperStatusResult) -> Void)
    func openApprovalSettings()
    func invalidate()
}

final class ClosedLidHelperClient: ClosedLidHelperClienting {
    private static let daemonPlistName = "\(ClosedLidIPCConstants.launchDaemonLabel).plist"
    private static let helperExecutableName = "DockTapClosedLidHelper"
    private static let registeredGenerationKey = "closedLidHelperRegisteredGeneration"

    private let service: SMAppService
    private let defaults: UserDefaults
    private let logStore: LogStore
    private let registrationQueue = DispatchQueue(label: "ai.resopod.docktap.closedlidhelper.registration")

    private var connection: NSXPCConnection?

    init(
        service: SMAppService = .daemon(plistName: ClosedLidHelperClient.daemonPlistName),
        defaults: UserDefaults = .standard,
        logStore: LogStore
    ) {
        self.service = service
        self.defaults = defaults
        self.logStore = logStore
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
        case .notRegistered:
            return registerHelper()
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound("helper LaunchDaemon plist was not found in the app bundle")
        @unknown default:
            return .failure("helper status is unknown")
        }
    }

    private func registerHelper() -> ClosedLidHelperPreparationResult {
        do {
            try service.register()
            rememberRegisteredGeneration()
            return resultAfterRegistration()
        } catch {
            return registrationFailureResult(error)
        }
    }

    private func reregisterHelper() -> ClosedLidHelperPreparationResult {
        do {
            try? service.unregister()
            try service.register()
            rememberRegisteredGeneration()
            logStore.append("closed-lid helper re-registered generation=\(bundledHelperGeneration)")
            return resultAfterRegistration()
        } catch {
            return registrationFailureResult(error)
        }
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

    private func registrationFailureResult(_ error: Error) -> ClosedLidHelperPreparationResult {
        let nsError = error as NSError
        if nsError.code == Int(kSMErrorLaunchDeniedByUser) {
            return .requiresApproval
        }
        if nsError.code == Int(kSMErrorAlreadyRegistered) {
            rememberRegisteredGeneration()
            return resultAfterRegistration()
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
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber
        else {
            return "\(url.lastPathComponent):missing"
        }

        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.lastPathComponent):\(size.int64Value):\(Int(modified))"
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

    private func startResult(from reply: ClosedLidStartReply) -> ClosedLidHelperStartResult {
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

    private func statusResult(from reply: ClosedLidStatusReply) -> ClosedLidHelperStatusResult {
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
            return .failure(reply.errorMessage as String? ?? "helper status failed")
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
