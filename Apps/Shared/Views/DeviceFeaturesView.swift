import SwiftUI
import WindFreeKit

/// Recursos do aparelho além dos controles principais (modo especial, display, bipe, limpeza, filtro e
/// consumo). Comum ao painel do Mac e aos ajustes do iPhone/iPad. Só mostra o que o
/// aparelho declara.
struct DeviceFeaturesView: View {
    @Environment(AppModel.self) private var model
    let engine: ACSyncEngine

    @State private var confirmingFilterReset = false
    @State private var filterMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            if let state = engine.displayed, engine.capabilities.hasExtras || engine.capabilities.optionalModes.count > 1 {
                featuresSection(state: state, caps: engine.capabilities)
            }
        }
        .confirmationDialog("Zerar o contador do filtro?", isPresented: $confirmingFilterReset) {
            Button("Zerar contador") { resetFilter() }
        } message: {
            Text("Faça isso depois de lavar o filtro.")
        }
    }

    @ViewBuilder
    private func featuresSection(state: ACState, caps: ACCapabilities) -> some View {
        if caps.optionalModes.count > 1 {
            Card {
                HStack {
                    Label("Modo especial", systemImage: "sparkles")
                    if engine.unconfirmed.contains(.optionalMode) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    OptionPicker(options: caps.optionalModes, current: state.optionalMode, label: Labels.optionalMode) {
                        engine.request(.optionalMode, .text($0))
                    }
                }
            }
        }
        if caps.display || caps.beep || caps.autoClean {
            togglesCard(state: state, caps: caps)
        }
        if caps.filter || caps.energy {
            usageCard(state: state, caps: caps)
        }
    }

    private func togglesCard(state: ACState, caps: ACCapabilities) -> some View {
        Card {
            if caps.display {
                ToggleRow(engine: engine, setting: .display, title: "Luz do display", symbol: "sun.max",
                          note: caps.displayControl == .samsungExecute
                              ? "Comando alternativo da Samsung; confira se o aparelho obedece." : nil,
                          isOn: state.displayOn == true)
            }
            if caps.beep {
                ToggleRow(engine: engine, setting: .beep, title: "Bipe", symbol: "speaker.wave.2",
                          note: "Som ao receber comandos", isOn: state.beepOn == true)
            }
            if caps.autoClean {
                ToggleRow(engine: engine, setting: .autoClean, title: "Limpeza automática", symbol: "wind",
                          note: "Seca o aparelho por dentro ao desligar", isOn: state.autoCleanOn == true)
            }
        }
    }

    private func usageCard(state: ACState, caps: ACCapabilities) -> some View {
        Card {
            if caps.filter { filterRow(state: state, caps: caps) }
            if caps.energy {
                let power = Labels.powerReading(state)
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "bolt").frame(width: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Consumo")
                        Text([power.note, state.energyKWh.map { "\(Format.decimal($0, digits: 0)) kWh no total" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(power.value).font(.body.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder
    private func filterRow(state: ACState, caps: ACCapabilities) -> some View {
        let usage = state.filterUsage ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "air.purifier").frame(width: 18).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Filtro")
                    Text(Labels.filterNote(state)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if caps.filterReset {
                    Button("Zerar…") { confirmingFilterReset = true }
                        .controlSize(.small)
                }
            }
            ProgressView(value: min(max(usage, 0), 100), total: 100)
                .tint(state.filterStatus == "normal" || state.filterStatus == nil ? Color.accentColor : .orange)
                .controlSize(.small)
            if !caps.filterAlarmThresholds.isEmpty {
                HStack {
                    Text("Avisar após")
                    Spacer()
                    Picker("Avisar após", selection: Binding(
                        get: { state.filterAlarmThreshold ?? caps.filterAlarmThresholds[0] },
                        set: { engine.request(.filterAlarmThreshold, .number($0)) }
                    )) {
                        ForEach(caps.filterAlarmThresholds, id: \.self) { Text("\(Int($0)) h de uso").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                .controlSize(.small)
            }
            if let filterMessage {
                Text(filterMessage).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func resetFilter() {
        filterMessage = "Zerando…"
        Task {
            let ok = await engine.perform(.resetFilter)
            filterMessage = ok ? "Contador zerado." : "O aparelho não confirmou a ação."
        }
    }

}

struct ToggleRow: View {
    let engine: ACSyncEngine
    let setting: ACSetting
    let title: String
    let symbol: String
    let note: String?
    let isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                    if engine.unconfirmed.contains(setting) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    } else if engine.isAwaiting(setting) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { engine.request(setting, .bool($0)) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

/// Grupo com fundo discreto, no estilo dos ajustes do sistema.
struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(iOS)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemGroupedBackground)))
        #else
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 0.5))
        #endif
    }
}
