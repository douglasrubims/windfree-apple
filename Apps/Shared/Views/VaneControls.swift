import SwiftUI
import WindFreeKit

/// Posição das pás com controles deslizantes, como no app SmartThings: arrastar fixa a posição;
/// "Oscilar" volta a oscilar. Se o aparelho não declarar posições numéricas, usa um menu.
struct VaneControls: View {
    let engine: ACSyncEngine
    let state: ACState
    let caps: ACCapabilities

    var body: some View {
        VStack(spacing: 8) {
            if caps.supports(.verticalAirflow) {
                VaneAxis(engine: engine, setting: .verticalAirflow, title: "Pás verticais", symbol: "arrow.up.and.down",
                         options: caps.verticalAirflowOptions, current: state.verticalAirflow,
                         hint: state.verticalStepHint)
            }
            if caps.supports(.horizontalAirflow) {
                VaneAxis(engine: engine, setting: .horizontalAirflow, title: "Pás laterais",
                         symbol: "arrow.left.and.right", options: caps.horizontalAirflowOptions,
                         current: state.horizontalAirflow, hint: state.horizontalStepHint)
            }
            if caps.supports(.horizontalSwingRange), state.horizontalAirflow == AirFlow.swing {
                SettingRow(engine: engine, setting: .horizontalSwingRange, title: "Alcance lateral",
                           symbol: "arrow.left.and.line.vertical.and.arrow.right") {
                    OptionPicker(options: caps.horizontalSwingRanges, current: state.horizontalSwingRange,
                                 label: Labels.swingRange) {
                        engine.request(.horizontalSwingRange, .text($0))
                    }
                }
            }
        }
    }
}

private struct VaneAxis: View {
    let engine: ACSyncEngine
    let setting: ACSetting
    let title: String
    let symbol: String
    let options: [String]
    let current: String?
    let hint: Int?

    var body: some View {
        let steps = AirFlow.steps(in: options)
        let canSwing = options.contains(AirFlow.swing)
        if steps.count < 2 {
            // Sem posições numeradas: menu simples (oscilar / fixa).
            SettingRow(engine: engine, setting: setting, title: title, symbol: symbol) {
                OptionPicker(options: options, current: current, label: Labels.vanePosition) {
                    engine.request(setting, .text($0))
                }
            }
        } else {
            slider(steps: steps, canSwing: canSwing)
        }
    }

    private func slider(steps: [Int], canSwing: Bool) -> some View {
        let swinging = current == AirFlow.swing
        let position = current.flatMap { Int($0) } ?? hint ?? steps[steps.count / 2]
        let lower = steps.first!
        let upper = steps.last!
        return VStack(alignment: .leading, spacing: 2) {
            SettingRow(engine: engine, setting: setting, title: title, symbol: symbol) {
                HStack(spacing: 8) {
                    Text(swinging ? "Oscilando" : "Posição \(position)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if canSwing {
                        Toggle("Oscilar", isOn: Binding(
                            get: { swinging },
                            set: { on in
                                engine.request(setting, .text(on ? AirFlow.swing : String(clamped(position, lower, upper))))
                            }
                        ))
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .help(swinging ? "Parar na posição atual" : "Oscilar as pás")
                    }
                }
            }
            Slider(
                value: Binding(
                    get: { Double(position) },
                    set: { value in
                        let step = clamped(Int(value.rounded()), lower, upper)
                        // Arrastar sempre fixa a posição (e para a oscilação).
                        if swinging || step != position { engine.request(setting, .text(String(step))) }
                    }
                ),
                in: Double(lower)...Double(upper),
                step: 1
            ) {
                Text(title)
            } minimumValueLabel: {
                Text("\(lower)").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("\(upper)").font(.caption2).foregroundStyle(.secondary)
            }
            .labelsHidden()
            .controlSize(.small)
            .opacity(swinging ? 0.45 : 1)
            .padding(.leading, 26)
            .accessibilityValue(swinging ? "Oscilando" : "Posição \(position) de \(upper)")
        }
    }

    private func clamped(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }
}
