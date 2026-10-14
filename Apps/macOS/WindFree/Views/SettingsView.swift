import SwiftUI
import WindFreeKit

/// Janela de ajustes: conta SmartThings, origem dos dados e opções gerais.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            AccountSettings()
                .tabItem { Label("Conta", systemImage: "person.crop.circle") }
            GeneralSettings()
                .tabItem { Label("Geral", systemImage: "gearshape") }
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(LoginItemController.self) private var loginItem

    var body: some View {
        Form {
            Section {
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    Button("Aprovar nos Ajustes do Sistema…") { loginItem.openSystemSettings() }
                }
                Picker("Temperatura na barra de menus", selection: Binding(
                    get: { model.preferences.menuBarTemperature },
                    set: { model.preferences.menuBarTemperature = $0 }
                )) {
                    ForEach(Preferences.MenuBarTemperature.allCases) { Text($0.title).tag($0) }
                }
            }
            Section("Consultas") {
                Text("""
                Com o painel aberto, o estado é lido a cada 15 s; fechado, a cada 2 min (5 min no modo \
                de baixo consumo). Com a tela apagada as consultas param e voltam ao acordar. Depois de \
                falhas, as tentativas são espaçadas progressivamente.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
    }
}
