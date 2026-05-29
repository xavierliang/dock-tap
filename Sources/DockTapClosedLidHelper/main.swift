import DockTapClosedLidHelperCore
import DockTapClosedLidIPC
import Foundation

final class ClosedLidHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: ClosedLidHelperService
    private let logger: LaunchDaemonLogger

    init(service: ClosedLidHelperService, logger: LaunchDaemonLogger) {
        self.service = service
        self.logger = logger
        super.init()
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("accepted client pid=\(newConnection.processIdentifier) euid=\(newConnection.effectiveUserIdentifier)")
        newConnection.exportedInterface = ClosedLidXPCInterfaceFactory.makeHelperInterface()
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [logger] in
            logger.info("client connection invalidated")
        }
        newConnection.interruptionHandler = { [logger] in
            logger.info("client connection interrupted")
        }
        newConnection.activate()
        return true
    }
}

let logger = LaunchDaemonLogger()
let commandRunner = FixedPmsetCommandRunner()
let journalStore = ClosedLidFileJournalStore()
let core = ClosedLidHelperCore(commandRunner: commandRunner, journalStore: journalStore)
let service = ClosedLidHelperService(core: core, logger: logger)
let listener = NSXPCListener(machServiceName: ClosedLidIPCConstants.machServiceName)
let listenerDelegate = ClosedLidHelperListenerDelegate(service: service, logger: logger)

listener.setConnectionCodeSigningRequirement(ClientCodeSigningRequirement.dockTapApplicationRequirement)
listener.delegate = listenerDelegate
listener.activate()
logger.info("listening machService=\(ClosedLidIPCConstants.machServiceName)")
RunLoop.current.run()
