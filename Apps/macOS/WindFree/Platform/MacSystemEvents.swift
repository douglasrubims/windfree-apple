import AppKit

/// Liga eventos do Mac ao ciclo de vida do modelo: com o Mac suspenso ou a tela apagada ninguém vê a barra
/// de menus, então as consultas param; ao acordar, voltam.
@MainActor
final class MacSystemEvents {
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.resume() }
            })
        }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak model] _ in
                MainActor.assumeIsolated { model?.suspend() }
            })
        }
    }
}
