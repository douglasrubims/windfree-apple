import SwiftUI
import WindFreeKit

/// App do Apple Watch, independente do iPhone: tem a própria autorização (recebida do iPhone uma vez) e fala
/// direto com o SmartThings. Consulta só com o app em primeiro plano.
@main
struct WindFreeWatchApp: App {
    @State private var model: AppModel
    @State private var receiver: WatchReceiver
    @Environment(\.scenePhase) private var scenePhase
    @State private var suspended = false

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _receiver = State(initialValue: WatchReceiver(model: model))
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(model)
                .environment(receiver)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active:
                        model.panelVisible = true
                        if suspended {
                            suspended = false
                            model.resume()
                        }
                    case .background:
                        model.panelVisible = false
                        model.suspend()
                        suspended = true
                    default:
                        break
                    }
                }
        }
    }
}
