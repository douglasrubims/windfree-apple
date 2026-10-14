import SwiftUI
import WindFreeKit

/// Conteúdo do painel da barra de menus.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @State private var page: Page = .controls

    enum Page { case controls, settings }

    var body: some View {
        Group {
            switch model.phase {
            case .ready:
                if let engine = model.engine {
                    switch page {
                    case .controls:
                        VStack(spacing: 0) {
                            ControlsView(engine: engine)
                            Divider()
                            PanelFooter(engine: engine, openSettings: { page = .settings })
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                    case .settings: DeviceSettingsView(engine: engine, close: { page = .controls })
                    }
                }
            default:
                StatusPlaceholder(phase: model.phase)
            }
        }
        .frame(width: 330)
        .background(PanelWindowObserver { visible in
            model.panelVisible = visible
            if !visible { page = .controls }
        })
    }
}

/// Telas antes de haver um aparelho: configuração, carregamento e erros.
struct StatusPlaceholder: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    let phase: AppModel.Phase

    var body: some View {
        VStack(spacing: 14) {
            switch phase {
            case .starting, .loadingDevices:
                ProgressView().controlSize(.small)
                Text(phase == .starting ? "Iniciando…" : "Procurando aparelhos…")
                    .foregroundStyle(.secondary)
            case .needsSetup:
                Image(systemName: "air.conditioner.horizontal").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Conecte sua conta SmartThings").font(.headline)
                Text("Autorize o WindFree com o seu app OAuth do SmartThings para ver e controlar o ar-condicionado.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Conectar conta…") { showSettings() }
                    .buttonStyle(.borderedProminent)
            case .noDevices:
                Image(systemName: "magnifyingglass").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Nenhum ar-condicionado encontrado").font(.headline)
                Text("Confira se o aparelho aparece no app SmartThings na mesma conta.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Procurar de novo") { model.refreshNow() }
            case .sessionExpired:
                Image(systemName: "key.slash").font(.system(size: 30)).foregroundStyle(.orange)
                Text("Sessão expirada").font(.headline)
                Text("O token não é mais aceito pelo SmartThings. Conecte a conta de novo.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Reconectar…") { showSettings() }
                    .buttonStyle(.borderedProminent)
            case .failed(let message):
                Image(systemName: "wifi.exclamationmark").font(.system(size: 30)).foregroundStyle(.orange)
                Text(message).font(.headline).multilineTextAlignment(.center)
                Button("Tentar de novo") { model.refreshNow() }
            case .ready:
                EmptyView()
            }
            Divider().padding(.top, 4)
            HStack {
                Button("Ajustes…") { showSettings() }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(18)
    }

    private func showSettings() {
        NSApp.activate()
        openSettings()
    }
}

/// Rodapé do painel no Mac: status da sincronização, atualizar e ajustes.
struct PanelFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openAppSettings
    let engine: ACSyncEngine
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            SyncStatusView(engine: engine) {
                NSApp.activate()
                openAppSettings()
            }
            .font(.caption)
            .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                model.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Atualizar agora")
            .disabled(engine.activity != .idle)
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Ajustes")
        }
        .buttonStyle(.borderless)
    }
}
