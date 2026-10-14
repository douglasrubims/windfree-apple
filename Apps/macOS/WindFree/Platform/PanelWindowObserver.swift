import AppKit
import SwiftUI

/// Acompanha a janela do painel da barra de menus: informa quando ela está visível
/// e fecha o painel com Esc.
struct PanelWindowObserver: NSViewRepresentable {
    let onVisibilityChange: (Bool) -> Void

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onVisibilityChange = onVisibilityChange
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onVisibilityChange = onVisibilityChange
    }

    final class ObserverView: NSView {
        var onVisibilityChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var keyMonitor: Any?
        private var lastReported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeObservers()
            guard let window else {
                report(false)
                return
            }
            let center = NotificationCenter.default
            for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification,
                         NSWindow.didResignKeyNotification, NSWindow.willCloseNotification]
            {
                let closing = name == NSWindow.willCloseNotification
                observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.evaluate(forceHidden: closing)
                    }
                })
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
                // Esc fecha o painel; menus abertos (outras janelas) tratam o próprio Esc.
                guard event.keyCode == 53, let window, event.window === window else { return event }
                window.close()
                return nil
            }
            evaluate(forceHidden: false)
        }

        private func evaluate(forceHidden: Bool) {
            guard let window, !forceHidden else {
                report(false)
                return
            }
            report(window.isVisible && window.occlusionState.contains(.visible))
        }

        private func report(_ visible: Bool) {
            guard visible != lastReported else { return }
            lastReported = visible
            onVisibilityChange?(visible)
        }

        private func removeObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }

        deinit {
            MainActor.assumeIsolated { removeObservers() }
        }
    }
}
