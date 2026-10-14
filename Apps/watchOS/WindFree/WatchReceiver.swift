import Observation
import WatchConnectivity
import WindFreeKit

/// Recebe do iPhone a autorização do relógio (ou o pedido para apagá-la) e a guarda no Keychain do relógio.
@MainActor
@Observable
final class WatchReceiver: NSObject {
    private(set) var lastEvent: String?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func handle(_ received: WatchTransfer.Received) async {
        switch received {
        case .credential(let credential):
            do {
                try await model.installTransferredCredential(credential)
                lastEvent = "Conectado pelo iPhone."
            } catch {
                lastEvent = AppModel.message(for: error)
            }
        case .signOut:
            await model.signOut()
            lastEvent = "Credenciais apagadas."
        }
    }
}

extension WatchReceiver: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void)
    {
        guard let received = WatchTransfer.decode(message) else {
            replyHandler(["ok": false])
            return
        }
        replyHandler(["ok": true])
        Task { @MainActor in await self.handle(received) }
    }
}
