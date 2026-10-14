import SwiftUI
import WindFreeKit

/// Layout adaptável: no iPhone (e no iPad estreito) uma pilha com o aparelho escolhido; no iPad com espaço
/// e mais de um aparelho, lista de aparelhos ao lado dos controles.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(WatchLink.self) private var watch
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showingSettings = false

    var body: some View {
        Group {
            if sizeClass == .regular, model.devices.count > 1, model.phase == .ready {
                NavigationSplitView {
                    DeviceList()
                        .navigationTitle("Aparelhos")
                } detail: {
                    NavigationStack { content }
                }
            } else {
                NavigationStack { content }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsSheet(startAtAccount: model.phase == .needsSetup || model.phase == .sessionExpired)
                .environment(model)
                .environment(watch)
        }
        #if DEBUG
        // Verificação visual sem toque: `-showSettings YES` abre os ajustes ao iniciar.
        .task {
            guard UserDefaults.standard.bool(forKey: "showSettings") else { return }
            while model.phase == .starting || model.phase == .loadingDevices {
                try? await Task.sleep(for: .milliseconds(200))
            }
            showingSettings = true
        }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if model.phase == .ready, let engine = model.engine {
                DeviceScreen(engine: engine, openSettings: { showingSettings = true })
            } else {
                PhasePlaceholder(phase: model.phase, openSettings: { showingSettings = true })
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape")
                }
            }
        }
    }
}

/// Controles do aparelho, recursos extras e status da sincronização.
struct DeviceScreen: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine
    let openSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ControlsView(engine: engine)
                    .padding(.bottom, 8)
                    .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))

                SyncStatusView(engine: engine, onReconnect: openSettings)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                DeviceFeaturesView(engine: engine)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("WindFree")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            model.refreshNow()
            try? await Task.sleep(for: .milliseconds(600))
        }
    }
}

/// Lista de aparelhos para a coluna lateral do iPad.
struct DeviceList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.devices, selection: Binding(
            get: { model.engine?.deviceID },
            set: { if let id = $0 { model.select(id) } }
        )) { device in
            Label {
                VStack(alignment: .leading) {
                    Text(device.roomName == nil ? model.title(for: device) : device.displayName)
                    if let room = device.roomName {
                        Text(room).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "air.conditioner.horizontal")
            }
            .tag(device.id)
        }
    }
}

/// Telas antes de haver um aparelho: configuração, carregamento e erros.
struct PhasePlaceholder: View {
    @Environment(AppModel.self) private var model
    let phase: AppModel.Phase
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            switch phase {
            case .starting, .loadingDevices:
                ProgressView()
                Text(phase == .starting ? "Iniciando…" : "Procurando aparelhos…").foregroundStyle(.secondary)
            case .needsSetup:
                Image(systemName: "air.conditioner.horizontal").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Conecte sua conta SmartThings").font(.headline)
                Text("Autorize o WindFree com o seu app OAuth do SmartThings para ver e controlar o ar-condicionado.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Conectar conta", action: openSettings)
                    .buttonStyle(.borderedProminent)
            case .noDevices:
                Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Nenhum ar-condicionado encontrado").font(.headline)
                Text("Confira se o aparelho aparece no app SmartThings na mesma conta.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Procurar de novo") { model.refreshNow() }
            case .sessionExpired:
                Image(systemName: "key.slash").font(.system(size: 40)).foregroundStyle(.orange)
                Text("Sessão expirada").font(.headline)
                Text("O SmartThings não aceita mais o acesso. Conecte a conta de novo.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Reconectar", action: openSettings)
                    .buttonStyle(.borderedProminent)
            case .failed(let message):
                Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundStyle(.orange)
                Text(message).font(.headline).multilineTextAlignment(.center)
                Button("Tentar de novo") { model.refreshNow() }
            case .ready:
                EmptyView()
            }
        }
        .padding(32)
        .frame(maxWidth: 480)
        .navigationTitle("WindFree")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Ajustes: conta, diagnóstico e informações.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(WatchLink.self) private var watch
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticFile: URL?
    @State private var showingAccount: Bool

    init(startAtAccount: Bool = false) {
        _showingAccount = State(initialValue: startAtAccount)
    }
    @State private var diagnosticError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountSettings()
                            .navigationTitle("Conta SmartThings")
                    } label: {
                        Label("Conta SmartThings", systemImage: "person.crop.circle")
                    }
                    if watch.isPaired {
                        NavigationLink {
                            WatchSetupView()
                        } label: {
                            Label("Apple Watch", systemImage: "applewatch")
                        }
                    }
                }
                if model.engine?.isLoaded == true {
                    Section {
                        if let diagnosticFile {
                            ShareLink(item: diagnosticFile) {
                                Label("Compartilhar diagnóstico", systemImage: "square.and.arrow.up")
                            }
                        } else {
                            Button {
                                export()
                            } label: {
                                Label("Gerar diagnóstico", systemImage: "doc.text.magnifyingglass")
                            }
                        }
                        if let diagnosticError {
                            Text(diagnosticError).font(.footnote).foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("Capacidades e status do aparelho, sem identificadores pessoais. Revise antes de compartilhar.")
                    }
                }
                Section {
                    Text("""
                    As consultas acontecem com o app aberto: a cada 15 s, ou 30 s no modo de baixo consumo. \
                    Em segundo plano o app não consulta o aparelho.
                    """)
                    .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Sobre")
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $showingAccount) {
                AccountSettings().navigationTitle("Conta SmartThings")
            }
            #if DEBUG
            .task { if UserDefaults.standard.bool(forKey: "showAccount") { showingAccount = true } }
            #endif
        }
    }

    private func export() {
        do {
            diagnosticFile = try model.exportDiagnostics()
            diagnosticError = nil
        } catch {
            diagnosticError = "Ainda não há status lido para exportar."
        }
    }
}
