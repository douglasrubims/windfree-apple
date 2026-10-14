import SwiftUI
import WindFreeKit

/// Controles principais, comuns ao painel do Mac e à tela do iPhone/iPad: liga/desliga, temperatura, modo,
/// vento, direção, WindFree e sono. O rodapé (status e botões) fica a cargo de cada plataforma.
struct ControlsView: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(engine: engine)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            if let state = engine.displayed {
                content(state)
            } else {
                LoadingBody(engine: engine)
            }
        }
    }

    @ViewBuilder
    private func content(_ state: ACState) -> some View {
        let caps = engine.capabilities
        let isOn = state.isOn == true

        AirflowView(isOn: isOn, mode: state.mode, fan: state.fanMode, oscillation: state.swingSummary,
                    windFree: state.windFreeOn, animate: model.panelVisible)
            .frame(height: 74)
            .padding(.horizontal, 14)
            .accessibilityHidden(true)

        Readings(state: state, caps: caps)
            .padding(.horizontal, 14)
            .padding(.top, 2)

        if let range = caps.targetTemperature {
            TemperatureControl(engine: engine, state: state, range: range)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .opacity(isOn ? 1 : 0.75)
        }

        Divider().padding(.horizontal, 14)

        VStack(spacing: 6) {
            if caps.supports(.mode) || state.mode != nil {
                SettingRow(engine: engine, setting: .mode, title: "Modo", symbol: Labels.modeSymbol(state.mode)) {
                    OptionPicker(options: caps.modes, current: state.mode, label: Labels.mode) {
                        engine.request(.mode, .text($0))
                    }
                }
            }
            if caps.supports(.fanMode) || state.fanMode != nil {
                SettingRow(engine: engine, setting: .fanMode, title: "Vento", symbol: "wind") {
                    OptionPicker(options: caps.fanModes, current: state.fanMode, label: Labels.fan) {
                        engine.request(.fanMode, .text($0))
                    }
                }
            }
            if caps.supports(.oscillation) {
                SettingRow(engine: engine, setting: .oscillation, title: "Direção",
                           symbol: "arrow.up.and.down.and.arrow.left.and.right") {
                    OptionPicker(options: caps.oscillationModes, current: state.oscillation,
                                 label: Labels.oscillation) {
                        engine.request(.oscillation, .text($0))
                    }
                }
            }
            if caps.supports(.verticalAirflow) || caps.supports(.horizontalAirflow) {
                VaneControls(engine: engine, state: state, caps: caps)
            }
            if caps.supportsWindFree {
                SettingRow(engine: engine, setting: .optionalMode, title: "WindFree", symbol: "aqi.low") {
                    optionalToggle(state: state, caps: caps, changed: .windFree)
                }
            }
            if caps.supportsSleep {
                SettingRow(engine: engine, setting: .optionalMode, title: "Sono", symbol: "moon") {
                    optionalToggle(state: state, caps: caps, changed: .sleep)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func optionalToggle(state: ACState, caps: ACCapabilities, changed: OptionalMode.Changed) -> some View {
        let isOn = changed == .windFree ? state.windFreeOn : state.sleepOn
        return Toggle("", isOn: Binding(
            get: { isOn },
            set: { newValue in
                let windFree = changed == .windFree ? newValue : state.windFreeOn
                let sleep = changed == .sleep ? newValue : state.sleepOn
                if let mode = OptionalMode.compose(windFree: windFree, sleep: sleep, changed: changed,
                                                   supported: caps.optionalModes)
                {
                    engine.request(.optionalMode, .text(mode))
                }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
    }
}

/// Botões redondos: compactos com ponteiro, 44 pt (mínimo recomendado) no toque.
enum TouchTarget {
    #if os(iOS)
    static let round: CGFloat = 44
    #else
    static let round: CGFloat = 34
    #endif
}

// MARK: - Cabeçalho

struct PanelHeader: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine

    var body: some View {
        let state = engine.displayed
        let isOn = state?.isOn == true
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                deviceTitle
                let subtitle = [model.selectedDevice?.roomName, model.isSimulated ? "Dados simulados" : nil]
                    .compactMap { $0 }.joined(separator: " · ")
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if engine.capabilities.power || state?.isOn != nil {
                PowerButton(isOn: isOn, awaiting: engine.isAwaiting(.power),
                            unconfirmed: engine.unconfirmed.contains(.power))
                {
                    engine.request(.power, .bool(!isOn))
                }
                .disabled(state == nil)
            }
        }
    }

    @ViewBuilder
    private var deviceTitle: some View {
        // Com cômodo, o nome fica curto e o cômodo vai na linha de baixo; sem ele, nomes repetidos ganham número.
        let name = model.selectedDevice.map { $0.roomName == nil ? model.title(for: $0) : $0.displayName }
            ?? "Ar-condicionado"
        if model.devices.count > 1 {
            Menu {
                ForEach(model.devices) { device in
                    Button {
                        model.select(device.id)
                    } label: {
                        if device.id == engine.deviceID {
                            Label(model.title(for: device), systemImage: "checkmark")
                        } else {
                            Text(model.title(for: device))
                        }
                    }
                }
            } label: {
                Text(name).font(.headline)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            #endif
            .fixedSize()
            .help("Escolher aparelho")
        } else {
            Text(name).font(.headline).lineLimit(1)
        }
    }
}

struct PowerButton: View {
    let isOn: Bool
    let awaiting: Bool
    let unconfirmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "power")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: TouchTarget.round, height: TouchTarget.round)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.18)))
                .overlay(alignment: .bottomTrailing) {
                    if awaiting || unconfirmed {
                        Circle()
                            .fill(unconfirmed ? Color.orange : Color.secondary)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.background, lineWidth: 1.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .help(isOn ? "Desligar" : "Ligar")
        .accessibilityLabel(isOn ? "Desligar o ar" : "Ligar o ar")
    }
}

// MARK: - Leituras e temperatura

struct Readings: View {
    let state: ACState
    let caps: ACCapabilities

    var body: some View {
        HStack(spacing: 14) {
            if caps.ambientTemperature, let ambient = state.ambientTemperature {
                Label {
                    Text("Ambiente ") + Text("\(Format.temperature(ambient))°").bold()
                } icon: {
                    Image(systemName: "thermometer.medium")
                }
            }
            if caps.humidity, let humidity = state.humidity {
                Label {
                    Text("\(Int(humidity.rounded()))%").bold()
                } icon: {
                    Image(systemName: "humidity")
                }
                .help("Umidade relativa")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

struct TemperatureControl: View {
    let engine: ACSyncEngine
    let state: ACState
    let range: TemperatureRange

    var body: some View {
        let value = state.targetTemperature ?? range.minimum
        VStack(spacing: 6) {
            HStack {
                StepButton(symbol: "minus", enabled: value > range.minimum) { change(by: -range.step, from: value) }
                Spacer()
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(Format.temperature(state.targetTemperature))
                            .font(.system(size: 46, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: value))
                        Text(state.temperatureUnit.symbol)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    StatusTag(engine: engine, setting: .targetTemperature)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Temperatura desejada \(Format.temperature(state.targetTemperature)) graus")
                Spacer()
                StepButton(symbol: "plus", enabled: value < range.maximum) { change(by: range.step, from: value) }
            }
            Slider(
                value: Binding(get: { value }, set: { set(range.clamp($0)) }),
                in: range.minimum...range.maximum
            ) {
                Text("Temperatura")
            } minimumValueLabel: {
                Text("\(Format.temperature(range.minimum))°").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(Format.temperature(range.maximum))°").font(.caption2).foregroundStyle(.secondary)
            }
            .labelsHidden()
            .controlSize(.small)
            if range.isAssumed {
                Text("Faixa não informada pelo aparelho; limites estimados.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func change(by delta: Double, from value: Double) {
        set(range.clamp(value + delta))
    }

    private func set(_ value: Double) {
        guard !value.isNaN, !ACValue.number(value).matches(engine.displayed?.value(for: .targetTemperature)) else {
            return
        }
        engine.request(.targetTemperature, .number(value))
    }
}

struct StepButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: TouchTarget.round, height: TouchTarget.round)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(symbol == "plus" ? "Aumentar temperatura" : "Diminuir temperatura")
    }
}

/// Indica se o valor exibido ainda aguarda envio, confirmação ou o ar ligar.
struct StatusTag: View {
    let engine: ACSyncEngine
    let setting: ACSetting

    var body: some View {
        Group {
            if engine.held.contains(setting) {
                Label("Aplicado ao ligar", systemImage: "clock")
            } else if engine.unconfirmed.contains(setting) {
                Label("Não confirmado", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if engine.isAwaiting(setting) {
                Label("Enviando…", systemImage: "arrow.triangle.2.circlepath")
            } else {
                Label("Confirmado", systemImage: "checkmark").hidden()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Linhas de ajuste

struct SettingRow<Control: View>: View {
    let engine: ACSyncEngine
    let setting: ACSetting
    let title: String
    let symbol: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(title)
            indicator
            Spacer(minLength: 8)
            control()
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var indicator: some View {
        if engine.held.contains(setting) {
            Image(systemName: "clock").font(.caption).foregroundStyle(.secondary)
                .help("Será aplicado quando o ar ligar")
        } else if engine.unconfirmed.contains(setting) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                .help("O aparelho não confirmou este ajuste")
        } else if engine.isAwaiting(setting) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                .help("Enviando ao aparelho")
        }
    }
}

/// Menu com as opções declaradas pelo aparelho. Se o valor atual não estiver na lista, ele aparece também.
struct OptionPicker: View {
    let options: [String]
    let current: String?
    let label: (String?) -> String
    let select: (String) -> Void

    var body: some View {
        let all = options.isEmpty || (current.map { options.contains($0) } ?? true)
            ? options : options + [current!]
        if all.isEmpty {
            Text(label(current)).foregroundStyle(.secondary)
        } else {
            Picker("", selection: Binding(get: { current ?? "" }, set: { if $0 != current { select($0) } })) {
                ForEach(all, id: \.self) { Text(label($0)).tag($0) }
                if current == nil { Text("—").tag("") }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

// MARK: - Rodapé e carregamento

/// Situação da sincronização em uma linha: erros, sessão, offline, envio pendente ou última atualização.
struct SyncStatusView: View {
    let engine: ACSyncEngine
    let onReconnect: () -> Void

    var body: some View {
        switch engine.issue {
        case .sessionExpired, .notAuthenticated:
            HStack(spacing: 6) {
                Label("Sessão expirada", systemImage: "key.slash").foregroundStyle(.orange)
                Button("Reconectar", action: onReconnect)
                    .buttonStyle(.borderless)
            }
        case .deviceOffline:
            Label(engine.pending.isEmpty ? "Aparelho offline" : "Aparelho offline · ajustes aguardam conexão",
                  systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        case .rateLimited(let until):
            Label {
                Text("Limite da API · nova tentativa \(until, style: .relative)")
            } icon: {
                Image(systemName: "hourglass")
            }
            .foregroundStyle(.orange)
        case .failure(let error):
            Label(error.userMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .rejected(let settings):
            Label("Comando recusado: \(Labels.settings(settings))", systemImage: "xmark.octagon")
                .foregroundStyle(.orange)
        case .unconfirmed(let settings):
            Label("O ar não confirmou: \(Labels.settings(settings))", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case nil:
            if engine.isSyncing {
                Label("Sincronizando…", systemImage: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
            } else if !engine.held.isEmpty {
                Label("Ajustes aguardam o ar ligar", systemImage: "clock").foregroundStyle(.secondary)
            } else if let updated = engine.lastUpdated {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    Label {
                        Text("Atualizado \(relative(updated, now: context.date))")
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .foregroundStyle(.secondary)
            } else {
                Label("Conectando…", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.secondary)
            }
        }
    }

    private func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 15 { return "agora" }
        return date.formatted(.relative(presentation: .named).locale(Locale(identifier: "pt_BR")))
    }
}

struct LoadingBody: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine

    var body: some View {
        VStack(spacing: 10) {
            if let issue = engine.issue {
                Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                Text(message(issue)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Tentar de novo") { model.refreshNow() }
            } else {
                ProgressView().controlSize(.small)
                Text("Lendo o estado do aparelho…").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.horizontal, 14)
    }

    private func message(_ issue: SyncIssue) -> String {
        switch issue {
        case .sessionExpired, .notAuthenticated: "Sessão expirada. Conecte a conta de novo nos ajustes."
        case .failure(let error): error.userMessage
        case .rateLimited: "Limite de consultas do SmartThings. Aguarde um pouco."
        case .deviceOffline: "Aparelho offline."
        default: "Não foi possível ler o aparelho."
        }
    }
}
