import SwiftUI
import WindFreeKit

/// Página de ajustes dentro do painel do Mac: recursos do aparelho e opções do app.
struct DeviceSettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LoginItemController.self) private var loginItem
    @Environment(\.openSettings) private var openAppSettings
    let engine: ACSyncEngine
    let close: () -> Void

    @State private var diagnosticMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: close) {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("[", modifiers: .command)
                .help("Voltar")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ajustes").font(.headline)
                    Text(model.selectedDevice.map(model.title(for:)) ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()

            // Sem rolagem: o painel cresce até caber tudo (cerca de 600 pt com todos os recursos).
            VStack(spacing: 12) {
                DeviceFeaturesView(engine: engine)
                appSection
            }
            .padding(14)
        }
    }

    private var appSection: some View {
        Card {
            HStack {
                Label("Abrir ao iniciar sessão", systemImage: "power.circle")
                Spacer()
                Toggle("Abrir ao iniciar sessão", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            if loginItem.needsApproval {
                Button("Aprovar nos Ajustes do Sistema…") { loginItem.openSystemSettings() }
                    .buttonStyle(.link).font(.caption)
            }
            if let error = loginItem.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Label("Na barra de menus", systemImage: "menubar.rectangle")
                Spacer()
                Picker("Na barra de menus", selection: Binding(
                    get: { model.preferences.menuBarTemperature },
                    set: { model.preferences.menuBarTemperature = $0 }
                )) {
                    ForEach(Preferences.MenuBarTemperature.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }

            Divider()
            HStack {
                Button("Conta e conexão…") {
                    NSApp.activate()
                    openAppSettings()
                }
                Spacer()
                Button("Exportar diagnóstico") { exportDiagnostics() }
                    .help("Gera um arquivo sem identificadores pessoais com as capacidades do aparelho")
            }
            .controlSize(.small)
            if let diagnosticMessage {
                Text(diagnosticMessage).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Sair do WindFree") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .onAppear { loginItem.refresh() }
    }

    private func exportDiagnostics() {
        do {
            let file = try model.exportDiagnostics()
            NSWorkspace.shared.activateFileViewerSelecting([file])
            diagnosticMessage = "Salvo em \(file.lastPathComponent). Revise antes de compartilhar."
        } catch {
            diagnosticMessage = "Ainda não há status lido para exportar."
        }
    }
}
