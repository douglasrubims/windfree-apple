import SwiftUI
import WindFreeKit

/// App de iPhone e iPad. Mesma lógica do Mac (`AppModel`, `WindFreeKit`); muda só a apresentação e o ciclo
/// de vida: as consultas acontecem com o app em primeiro plano e param em segundo plano.
@main
struct WindFreeiOSApp: App {
    @State private var model = AppModel()
    @State private var watchLink = WatchLink()
    @Environment(\.scenePhase) private var scenePhase
    @State private var suspended = false

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(watchLink)
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
