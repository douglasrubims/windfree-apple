import SwiftUI
import WindFreeKit

@main
struct WindFreeApp: App {
    @State private var model: AppModel
    @State private var loginItem = LoginItemController()
    private let systemEvents: MacSystemEvents

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        systemEvents = MacSystemEvents(model: model)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(model)
                .environment(loginItem)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(loginItem)
        }
        .windowResizability(.contentSize)
    }
}

/// Temperatura na barra de menus. Fica de fora da observação do painel para redesenhar o mínimo.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let state = model.engine?.displayed
        let value = model.preferences.menuBarTemperature == .ambient ? state?.ambientTemperature : state?.targetTemperature
        HStack(spacing: 3) {
            Image(systemName: symbol(isOn: state?.isOn == true))
            if model.phase == .ready {
                Text("\(Format.temperature(value))°")
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityText(value))
        #if DEBUG
        .task {
            if SnapshotRenderer.isKeychainCheckRequested { SnapshotRenderer.runKeychainCheck() }
            if SnapshotRenderer.isRequested { await SnapshotRenderer.run(model: model) }
        }
        #endif
    }

    private func symbol(isOn: Bool) -> String {
        switch (model.phase, model.engine?.issue) {
        case (.sessionExpired, _), (.needsSetup, _), (.failed, _), (_, .sessionExpired):
            "exclamationmark.triangle"
        default:
            isOn ? "air.conditioner.horizontal.fill" : "air.conditioner.horizontal"
        }
    }

    private func accessibilityText(_ value: Double?) -> String {
        guard model.phase == .ready else { return "WindFree" }
        return "WindFree, \(Format.temperature(value)) graus"
    }
}
