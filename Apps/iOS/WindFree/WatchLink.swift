import Observation
import WatchConnectivity
import WindFreeKit

/// Comunicação com o app do Apple Watch. A credencial só é enviada com o app do relógio aberto (mensagem
/// direta e criptografada entre aparelhos pareados), e o relógio a guarda no próprio Keychain.
@MainActor
@Observable
final class WatchLink: NSObject {
    private(set) var isSupported = WCSession.isSupported()
    private(set) var isPaired = false
    private(set) var isAppInstalled = false
    private(set) var isReachable = false

    enum Failure: Error {
        case notReachable
        case rejected
    }

    override init() {
        super.init()
        guard isSupported else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ credential: StoredCredential) async throws {
        try await deliver(try WatchTransfer.message(for: credential))
    }

    func signOutWatch() async throws {
        try await deliver(WatchTransfer.signOutMessage)
    }

    private func deliver(_ message: [String: Any]) async throws {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { throw Failure.notReachable }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.sendMessage(message, replyHandler: { reply in
                if reply["ok"] as? Bool == true {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Failure.rejected)
                }
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    fileprivate func apply(paired: Bool, installed: Bool, reachable: Bool) {
        isPaired = paired
        isAppInstalled = installed
        isReachable = reachable
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?)
    {
        update(from: session)
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Troca de relógio: reativa para o novo.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        update(from: session)
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        update(from: session)
    }

    private nonisolated func update(from session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in self.apply(paired: paired, installed: installed, reachable: reachable) }
    }
}
