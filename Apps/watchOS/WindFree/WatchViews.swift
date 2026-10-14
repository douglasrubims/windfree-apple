import SwiftUI
import WindFreeKit

/// Raiz do app do relógio: controles do aparelho ou a tela de configuração.
struct WatchRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.phase == .ready, let engine = model.engine {
                WatchControlsView(engine: engine)
            } else {
                WatchPlaceholder(phase: model.phase)
            }
        }
    }
}

/// Tela principal: temperatura pela Digital Crown, liga/desliga, modo e "mais".
struct WatchControlsView: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine
    @State private var crown: Double = 0
    @State private var showingMore = false

    var body: some View {
        Group {
            if let state = engine.displayed {
                content(state)
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(WatchStatus.text(for: engine).text).font(.footnote).multilineTextAlignment(.center)
                }
            }
        }
        // No relógio o cômodo identifica melhor que o nome, que costuma se repetir.
        .navigationTitle(model.selectedDevice.map { $0.roomName ?? model.title(for: $0) } ?? "WindFree")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingMore) { WatchMoreView(engine: engine) }
        #if DEBUG
        // Verificação visual sem toque: `-showMore YES` abre "mais" ao iniciar.
        .task { if UserDefaults.standard.bool(forKey: "showMore") { showingMore = true } }
        #endif
    }

    @ViewBuilder
    private func content(_ state: ACState) -> some View {
        let caps = engine.capabilities
        let range = caps.targetTemperature ?? TemperatureRange(minimum: 16, maximum: 30, isAssumed: true)
        let isOn = state.isOn == true
        let status = WatchStatus.text(for: engine)

        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: Labels.modeSymbol(state.mode))
                Text(isOn ? Labels.mode(state.mode) : "Desligado")
            }
            .font(.footnote)
            .foregroundStyle(isOn ? Labels.modeColor(state.mode) : .secondary)

            HStack {
                Button { step(-range.step, range: range) } label: { Image(systemName: "minus") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.mini)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("\(Format.temperature(state.targetTemperature))°")
                        .font(.system(size: 46, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: state.targetTemperature ?? 0))
                        .foregroundStyle(isOn ? Color.primary : Color.secondary)
                    if let tag = pendingTag(.targetTemperature) {
                        Text(tag).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button { step(range.step, range: range) } label: { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .controlSize(.mini)
            }

            if let ambient = state.ambientTemperature {
                Text("Ambiente \(Format.temperature(ambient))°" + (state.humidity.map { " · \(Int($0))%" } ?? ""))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Text(status.text)
                .font(.system(size: 11))
                .foregroundStyle(status.warning ? Color.orange : Color.secondary)
                .lineLimit(1)
        }
        .focusable()
        .digitalCrownRotation($crown, from: range.minimum, through: range.maximum, by: range.step,
                              sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear { crown = state.targetTemperature ?? range.minimum }
        .onChange(of: crown) { _, value in set(range.clamp(value)) }
        .onChange(of: engine.displayed?.targetTemperature) { _, value in
            // Mudanças vindas do aparelho (ou de outro app) acompanham a coroa.
            if let value, abs(value - crown) >= range.step / 2 { crown = value }
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    engine.request(.power, .bool(!isOn))
                } label: {
                    Image(systemName: "power")
                }
                .tint(isOn ? .accentColor : .gray)
                .accessibilityLabel(isOn ? "Desligar" : "Ligar")

                NavigationLink {
                    WatchOptionList(title: "Modo", options: caps.modes, current: state.mode, label: Labels.mode) {
                        engine.request(.mode, .text($0))
                    }
                } label: {
                    Image(systemName: Labels.modeSymbol(state.mode))
                }
                .accessibilityLabel("Modo")

                Button {
                    showingMore = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Mais ajustes")
            }
        }
    }

    private func step(_ delta: Double, range: TemperatureRange) {
        let current = engine.displayed?.targetTemperature ?? crown
        crown = range.clamp(current + delta)
    }

    private func set(_ value: Double) {
        guard !ACValue.number(value).matches(engine.displayed?.value(for: .targetTemperature)) else { return }
        engine.request(.targetTemperature, .number(value))
    }

    private func pendingTag(_ setting: ACSetting) -> String? {
        if engine.held.contains(setting) { return "ao ligar" }
        if engine.unconfirmed.contains(setting) { return "não confirmado" }
        if engine.isAwaiting(setting) { return "enviando…" }
        return nil
    }
}

/// Lista de opções declaradas pelo aparelho.
struct WatchOptionList: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let options: [String]
    let current: String?
    let label: (String?) -> String
    let select: (String) -> Void

    var body: some View {
        List(options, id: \.self) { option in
            Button {
                if option != current { select(option) }
                dismiss()
            } label: {
                HStack {
                    Text(label(option))
                    Spacer()
                    if option == current { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                }
            }
        }
        .navigationTitle(title)
    }
}

/// Todos os recursos do aparelho que não cabem na tela principal, só os que o aparelho declara.
struct WatchMoreView: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine
    @State private var confirmingFilterReset = false
    @State private var filterMessage: String?
    @State private var showingVanes = false

    var body: some View {
        List {
            if let state = engine.displayed {
                let caps = engine.capabilities
                climateSection(state, caps)
                vanesSection(state, caps)
                deviceSection(state, caps)
                infoSection(state, caps)
            }
            accountSection
        }
        .navigationTitle("Ajustes")
        #if DEBUG
        // Verificação visual sem toque: `-showVanes YES` abre as pás verticais.
        .navigationDestination(isPresented: $showingVanes) {
            WatchVaneView(engine: engine, setting: .verticalAirflow, title: "Pás verticais")
        }
        .task { if UserDefaults.standard.bool(forKey: "showVanes") { showingVanes = true } }
        #endif
        .confirmationDialog("Zerar o contador do filtro?", isPresented: $confirmingFilterReset) {
            Button("Zerar contador", role: .destructive) { resetFilter() }
        } message: {
            Text("Faça isso depois de lavar o filtro.")
        }
    }

    // MARK: Seções

    @ViewBuilder
    private func climateSection(_ state: ACState, _ caps: ACCapabilities) -> some View {
        Section("Clima") {
            if !caps.fanModes.isEmpty {
                optionLink("Vento", .fanMode, options: caps.fanModes, current: state.fanMode, label: Labels.fan)
            }
            if caps.oscillationModes.count > 1 {
                optionLink("Direção", .oscillation, options: caps.oscillationModes, current: state.oscillation,
                           label: Labels.oscillation)
            }
            if caps.supportsWindFree {
                Toggle(isOn: optionalBinding(state, caps, changed: .windFree)) { title("WindFree", .optionalMode) }
            }
            if caps.supportsSleep {
                Toggle(isOn: optionalBinding(state, caps, changed: .sleep)) { title("Sono", .optionalMode) }
            }
            if caps.optionalModes.count > 1 {
                optionLink("Modo especial", .optionalMode, options: caps.optionalModes, current: state.optionalMode,
                           label: Labels.optionalMode)
            }
        }
    }

    @ViewBuilder
    private func vanesSection(_ state: ACState, _ caps: ACCapabilities) -> some View {
        if caps.supports(.verticalAirflow) || caps.supports(.horizontalAirflow) {
            Section("Pás") {
                if caps.supports(.verticalAirflow) {
                    NavigationLink {
                        WatchVaneView(engine: engine, setting: .verticalAirflow, title: "Pás verticais")
                    } label: {
                        LabeledContent { Text(Labels.vanePosition(state.verticalAirflow)) } label: {
                            title("Verticais", .verticalAirflow)
                        }
                    }
                }
                if caps.supports(.horizontalAirflow) {
                    NavigationLink {
                        WatchVaneView(engine: engine, setting: .horizontalAirflow, title: "Pás laterais")
                    } label: {
                        LabeledContent { Text(Labels.vanePosition(state.horizontalAirflow)) } label: {
                            title("Laterais", .horizontalAirflow)
                        }
                    }
                }
                if caps.supports(.horizontalSwingRange), state.horizontalAirflow == AirFlow.swing {
                    optionLink("Alcance lateral", .horizontalSwingRange, options: caps.horizontalSwingRanges,
                               current: state.horizontalSwingRange, label: Labels.swingRange)
                }
            }
        }
    }

    @ViewBuilder
    private func deviceSection(_ state: ACState, _ caps: ACCapabilities) -> some View {
        if caps.display || caps.beep || caps.autoClean {
            Section("Aparelho") {
                if caps.display { toggle("Luz do display", .display, isOn: state.displayOn == true) }
                if caps.beep { toggle("Bipe", .beep, isOn: state.beepOn == true) }
                if caps.autoClean { toggle("Limpeza automática", .autoClean, isOn: state.autoCleanOn == true) }
            }
        }
    }

    @ViewBuilder
    private func infoSection(_ state: ACState, _ caps: ACCapabilities) -> some View {
        if caps.filter || caps.energy {
            Section("Informações") {
                if caps.filter {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filtro")
                        Text(Labels.filterNote(state)).font(.footnote).foregroundStyle(.secondary)
                        ProgressView(value: min(max(state.filterUsage ?? 0, 0), 100), total: 100)
                            .tint(state.filterStatus == "normal" || state.filterStatus == nil ? Color.accentColor : .orange)
                        if let filterMessage {
                            Text(filterMessage).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !caps.filterAlarmThresholds.isEmpty {
                        optionLink("Avisar após", .filterAlarmThreshold,
                                   options: caps.filterAlarmThresholds.map { String(Int($0)) },
                                   current: state.filterAlarmThreshold.map { String(Int($0)) },
                                   label: { $0.map { "\($0) h" } ?? "—" },
                                   value: { .number(Double($0) ?? 0) })
                    }
                    if caps.filterReset {
                        Button("Zerar filtro…") { confirmingFilterReset = true }
                    }
                }
                if caps.energy {
                    let power = Labels.powerReading(state)
                    LabeledContent {
                        Text(power.value).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading) {
                            Text("Consumo")
                            if let energy = state.energyKWh {
                                Text("\(Format.decimal(energy, digits: 0)) kWh").font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var accountSection: some View {
        Section("Conta") {
            if model.devices.count > 1 {
                NavigationLink {
                    WatchOptionList(title: "Aparelho", options: model.devices.map(\.id), current: engine.deviceID,
                                    label: { id in model.devices.first { $0.id == id }.map(model.title(for:)) ?? "" }) {
                        model.select($0)
                    }
                } label: {
                    LabeledContent("Aparelho", value: model.selectedDevice.map(model.title(for:)) ?? "")
                }
            }
            Button("Atualizar agora") { model.refreshNow() }
            WatchAccountSection()
        }
    }

    // MARK: Componentes

    /// Título com indicação de envio pendente, retido ou não confirmado.
    private func title(_ text: String, _ setting: ACSetting) -> some View {
        HStack(spacing: 4) {
            Text(text)
            if engine.unconfirmed.contains(setting) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if engine.held.contains(setting) {
                Image(systemName: "clock").foregroundStyle(.secondary)
            } else if engine.isAwaiting(setting) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .imageScale(.small)
    }

    private func toggle(_ text: String, _ setting: ACSetting, isOn: Bool) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { engine.request(setting, .bool($0)) })) { title(text, setting) }
    }

    private func optionLink(_ text: String, _ setting: ACSetting, options: [String], current: String?,
                            label: @escaping (String?) -> String,
                            value: @escaping (String) -> ACValue = { .text($0) }) -> some View
    {
        NavigationLink {
            WatchOptionList(title: text, options: options, current: current, label: label) {
                engine.request(setting, value($0))
            }
        } label: {
            LabeledContent { Text(label(current)) } label: { title(text, setting) }
        }
    }

    private func optionalBinding(_ state: ACState, _ caps: ACCapabilities, changed: OptionalMode.Changed) -> Binding<Bool> {
        Binding(
            get: { changed == .windFree ? state.windFreeOn : state.sleepOn },
            set: { value in
                let windFree = changed == .windFree ? value : state.windFreeOn
                let sleep = changed == .sleep ? value : state.sleepOn
                if let mode = OptionalMode.compose(windFree: windFree, sleep: sleep, changed: changed,
                                                   supported: caps.optionalModes)
                {
                    engine.request(.optionalMode, .text(mode))
                }
            }
        )
    }

    private func resetFilter() {
        filterMessage = "Zerando…"
        Task {
            let ok = await engine.perform(.resetFilter)
            filterMessage = ok ? "Contador zerado." : "O aparelho não confirmou."
        }
    }
}

/// Posição das pás com a Digital Crown: girar fixa a posição; "Oscilar" volta a oscilar.
struct WatchVaneView: View {
    let engine: ACSyncEngine
    let setting: ACSetting
    let title: String
    @State private var crown: Double = 0

    /// Lidas do estado observado, para acompanhar a leitura do aparelho.
    private var options: [String] {
        setting == .verticalAirflow ? engine.capabilities.verticalAirflowOptions
            : engine.capabilities.horizontalAirflowOptions
    }

    var body: some View {
        let options = options
        let steps = AirFlow.steps(in: options)
        let current = engine.displayed?.value(for: setting)?.text
        let hint = setting == .verticalAirflow ? engine.displayed?.verticalStepHint : engine.displayed?.horizontalStepHint
        let swinging = current == AirFlow.swing
        let position = current.flatMap { Int($0) } ?? hint ?? steps.first ?? 1

        VStack(spacing: 6) {
            if steps.count >= 2 {
                HStack {
                    Button { move(-1, steps: steps, from: position) } label: { Image(systemName: "minus") }
                        .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.mini)
                        .disabled(position <= steps.first! && !swinging)
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        Text(swinging ? "Oscilando" : "Posição")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text("\(position)")
                            .font(.system(size: 44, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .opacity(swinging ? 0.4 : 1)
                        Text("de \(steps.first!) a \(steps.last!)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button { move(1, steps: steps, from: position) } label: { Image(systemName: "plus") }
                        .buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.mini)
                        .disabled(position >= steps.last! && !swinging)
                }
                .focusable()
                .digitalCrownRotation($crown, from: Double(steps.first!), through: Double(steps.last!), by: 1,
                                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .onAppear { crown = Double(position) }
                .onChange(of: position) { _, value in crown = Double(value) }
                .onChange(of: crown) { _, value in
                    // Girar fixa a posição; ao abrir a tela a coroa só acompanha o valor atual.
                    let step = Int(value.rounded())
                    if step != position { engine.request(setting, .text(String(step))) }
                }
            } else if options.isEmpty {
                ProgressView()
            } else {
                // Sem posições numeradas: oscilar ou fixa.
                ForEach(options, id: \.self) { option in
                    Button {
                        engine.request(setting, .text(option))
                    } label: {
                        HStack {
                            Text(Labels.vanePosition(option))
                            Spacer()
                            if option == current { Image(systemName: "checkmark") }
                        }
                    }
                }
            }

            if options.contains(AirFlow.swing), steps.count >= 2 {
                Toggle("Oscilar", isOn: Binding(
                    get: { swinging },
                    set: { engine.request(setting, .text($0 ? AirFlow.swing : String(position))) }
                ))
            }
        }
        .padding(.horizontal, 6)
        .navigationTitle(title)
    }

    private func move(_ delta: Int, steps: [Int], from position: Int) {
        let next = min(max(position + delta, steps.first!), steps.last!)
        crown = Double(next)
        engine.request(setting, .text(String(next)))
    }
}

/// Desconexão e, em "Avançado", dados simulados.
struct WatchAccountSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.credentialSummary != nil, !model.isSimulated {
            Button("Desconectar", role: .destructive) { Task { await model.signOut() } }
        }
        NavigationLink("Avançado") {
            List {
                Toggle("Dados simulados", isOn: Binding(
                    get: { model.preferences.useSimulation },
                    set: { value in Task { await model.setSimulation(value) } }
                ))
                Text("Aparelhos fictícios, para demonstração.").font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Avançado")
        }
    }
}

/// Antes de haver um aparelho: conectar pelo iPhone, carregar ou erro.
struct WatchPlaceholder: View {
    @Environment(AppModel.self) private var model
    @Environment(WatchReceiver.self) private var receiver
    let phase: AppModel.Phase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                switch phase {
                case .starting, .loadingDevices:
                    ProgressView()
                    Text("Procurando aparelhos…").font(.footnote).foregroundStyle(.secondary)
                case .needsSetup, .sessionExpired:
                    Image(systemName: phase == .sessionExpired ? "key.slash" : "iphone.and.arrow.forward")
                        .font(.title2).foregroundStyle(phase == .sessionExpired ? .orange : .secondary)
                    Text(phase == .sessionExpired ? "Sessão expirada" : "Conectar")
                        .font(.headline)
                    Text("No iPhone: WindFree › Ajustes › Apple Watch › Autorizar o relógio. Mantenha este app aberto.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .noDevices:
                    Text("Nenhum ar-condicionado encontrado.").font(.footnote).multilineTextAlignment(.center)
                    Button("Procurar de novo") { model.refreshNow() }
                case .failed(let message):
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(.orange)
                    Text(message).font(.footnote).multilineTextAlignment(.center)
                    Button("Tentar de novo") { model.refreshNow() }
                case .ready:
                    EmptyView()
                }
                if let event = receiver.lastEvent {
                    Text(event).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("WindFree")
    }
}

/// Status da sincronização em poucas palavras.
enum WatchStatus {
    @MainActor
    static func text(for engine: ACSyncEngine) -> (text: String, warning: Bool) {
        switch engine.issue {
        case .sessionExpired, .notAuthenticated: return ("Sessão expirada", true)
        case .deviceOffline: return ("Aparelho offline", true)
        case .rateLimited: return ("Limite da API", true)
        case .failure: return ("Sem resposta", true)
        case .rejected: return ("Comando recusado", true)
        case .unconfirmed(let settings): return ("Não confirmou: \(Labels.settings(settings))", true)
        case nil:
            if engine.isSyncing { return ("Sincronizando…", false) }
            if !engine.held.isEmpty { return ("Aguardando ligar", false) }
            return (engine.lastUpdated == nil ? "Conectando…" : "Atualizado", false)
        }
    }
}
