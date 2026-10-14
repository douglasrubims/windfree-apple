import Foundation
import Testing
@testable import WindFreeKit

/// Estrutura de capacidades observada num WindFree 2026 real (diagnóstico de 11/10/2026), reduzida ao que
/// importa e sem identificadores.
enum RealDeviceFixture {
    static let json = """
    {"components":{"main":{
      "switch":{"switch":{"value":"on"}},
      "thermostatCoolingSetpoint":{"coolingSetpoint":{"value":22,"unit":"C"},
        "coolingSetpointRange":{"value":{"minimum":16,"maximum":30,"step":1},"unit":"C"}},
      "temperatureMeasurement":{"temperature":{"value":21,"unit":"C"}},
      "relativeHumidityMeasurement":{"humidity":{"value":69,"unit":"%"}},
      "airConditionerMode":{"airConditionerMode":{"value":"cool"},
        "supportedAcModes":{"value":["auto","cool","dry","fan","heat"]}},
      "airConditionerFanMode":{"fanMode":{"value":"turbo"},
        "supportedAcFanModes":{"value":["auto","low","medium","high","turbo"]}},
      "fanOscillationMode":{"fanOscillationMode":{"value":null},"supportedFanOscillationModes":{"value":null}},
      "samsungce.airConditionerAirFlowDirection":{
        "verticalDirection":{"value":"swing"},"verticalAngleStep":{"value":"6"},
        "horizontalDirection":{"value":"fixed"},"horizontalAngleStep":{"value":"2"},
        "horizontalSwingRange":{"value":"all"},
        "supportedVerticalDirections":{"value":["swing","fixed"]},
        "supportedHorizontalDirections":{"value":["swing","fixed"]},
        "supportedVerticalAngleSteps":{"value":["1","2","3","4","5","6"]},
        "supportedHorizontalAngleSteps":{"value":["1","2","3","4","5"]},
        "supportedHorizontalSwingRanges":{"value":["all","left","right"]}},
      "custom.airConditionerOptionalMode":{"acOptionalMode":{"value":"off"},
        "supportedAcOptionalMode":{"value":["off","sleep","quiet","smart","speed","windFree","windFreeSleep","dryComfort"]}},
      "samsungce.airConditionerLighting":{"lighting":{"value":"on"},"supportedLightingLevels":{"value":["on","off"]}},
      "execute":{"data":{"value":null}},
      "audioVolume":{"volume":{"value":0,"unit":"%"}},
      "samsungce.airConditionerBeep":{"beep":{"value":"off"}},
      "custom.autoCleaningMode":{"autoCleaningMode":{"value":"on"}},
      "custom.dustFilter":{"dustFilterUsage":{"value":77},"dustFilterStatus":{"value":"normal"}},
      "samsungce.dustFilterAlarm":{"alarmThreshold":{"value":500,"unit":"Hour"},
        "supportedAlarmThresholds":{"value":[180,300,500,700],"unit":"Hour"}},
      "powerConsumptionReport":{"powerConsumption":{"value":{"deltaEnergy":37,"energy":221324,"power":0,
        "start":"2026-10-12T00:56:36Z","end":"2026-10-12T01:09:18Z"}}},
      "samsungce.softwareUpdate":{"otnDUID":{"value":"ABCDEFGHIJKLM"}},
      "custom.disabledCapabilities":{"disabledCapabilities":{"value":["fanOscillationMode","audioNotification"]}},
      "samsungce.unavailableCapabilities":{"unavailableCommands":{"value":["custom.spiMode.setSpiMode"]}}
    }}}
    """

    static func status(_ text: String = json) throws -> DeviceStatus {
        DeviceStatus(json: try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)))
    }
}

@Suite("Perfil do aparelho real (WindFree 2026)")
struct RealDeviceProfileTests {
    @Test func usesSamsungSpecificControls() throws {
        let caps = ACInterpreter.capabilities(from: try RealDeviceFixture.status())
        #expect(caps.modes == ["auto", "cool", "dry", "fan", "heat"])
        // Direção padrão desativada: as pás substituem o seletor de oscilação.
        #expect(caps.oscillationModes.isEmpty)
        #expect(caps.verticalAirflowOptions == ["swing", "1", "2", "3", "4", "5", "6"])
        #expect(caps.horizontalAirflowOptions == ["swing", "1", "2", "3", "4", "5"])
        #expect(caps.horizontalSwingRanges == ["all", "left", "right"])
        #expect(caps.display && caps.displayControl == .lightingLevel)
        #expect(caps.beep && caps.beepControl == .beepSwitch)
        #expect(caps.supportsWindFree && caps.supportsSleep)
        #expect(caps.targetTemperature == TemperatureRange(minimum: 16, maximum: 30))
    }

    @Test func interpretsStateFromSamsungCapabilities() throws {
        let state = ACInterpreter.state(from: try RealDeviceFixture.status())
        #expect(state.verticalAirflow == "swing")
        #expect(state.horizontalAirflow == "2")
        #expect(state.horizontalSwingRange == "all")
        #expect(state.swingSummary == "vertical")
        // Posição informada mesmo oscilando, para o controle deslizante.
        #expect(state.verticalStepHint == 6)
        #expect(state.horizontalStepHint == 2)
        #expect(AirFlow.steps(in: ["swing", "1", "2", "3"]) == [1, 2, 3])
        #expect(state.displayOn == true)
        #expect(state.beepOn == false)
        #expect(state.powerWatts == 0)
        // 37 Wh em 12 min 42 s ≈ 175 W.
        #expect(abs((state.averagePowerWatts ?? 0) - 174.8) < 0.5)
    }

    @Test func buildsSamsungCommands() throws {
        let caps = ACInterpreter.capabilities(from: try RealDeviceFixture.status())
        // Posição exata: para a oscilação e depois define o passo (argumentos em texto, como na definição).
        let fixedPosition = ACCommandBuilder.commands(for: .verticalAirflow, value: .text("4"), capabilities: caps)
        #expect(fixedPosition.map(\.command) == ["setVerticalDirection", "setVerticalAngleStep"])
        #expect(fixedPosition.map { $0.arguments } == [["fixed"], ["4"]])
        let swing = ACCommandBuilder.commands(for: .horizontalAirflow, value: .text("swing"), capabilities: caps)
        #expect(swing.map(\.command) == ["setHorizontalDirection"])
        #expect(swing.first?.arguments == ["swing"])
        let range = ACCommandBuilder.commands(for: .horizontalSwingRange, value: .text("left"), capabilities: caps)
        #expect(range.first?.command == "setHorizontalSwingRange")

        let display = try #require(ACCommandBuilder.commands(for: .display, value: .bool(false), capabilities: caps).first)
        #expect(display.capability == "samsungce.airConditionerLighting")
        #expect(display.command == "setLightingLevel")
        #expect(display.arguments == ["off"])

        let beep = try #require(ACCommandBuilder.commands(for: .beep, value: .bool(true), capabilities: caps).first)
        #expect(beep.capability == "samsungce.airConditionerBeep")
        #expect(beep.command == "on")
        #expect(beep.arguments.isEmpty)
    }

    @Test func fallsBackWhenSamsungCommandIsUnavailable() throws {
        let json = RealDeviceFixture.json.replacingOccurrences(
            of: #"["custom.spiMode.setSpiMode"]"#,
            with: #"["samsungce.airConditionerLighting.setLightingLevel","samsungce.airConditionerAirFlowDirection.setHorizontalDirection"]"#
        )
        let caps = ACInterpreter.capabilities(from: try RealDeviceFixture.status(json))
        #expect(caps.displayControl == .samsungExecute)
        // Sem `setHorizontalDirection`, as pás laterais só aceitariam posição sem poder parar a oscilação:
        // o controle lateral some e o vertical continua.
        #expect(caps.horizontalAirflowOptions.isEmpty)
        #expect(caps.verticalAirflowOptions.count == 7)
    }

    @Test func diagnosticRemovesUpdateIdentifier() throws {
        let status = try RealDeviceFixture.status()
        let data = try DiagnosticReport.make(status: status, health: .online,
                                             capabilities: ACInterpreter.capabilities(from: status),
                                             state: ACInterpreter.state(from: status))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("ABCDEFGHIJKLM"))
        #expect(text.contains("pasVerticais"))
        #expect(text.contains("samsungce.airConditionerAirFlowDirection"))
    }

    @MainActor
    @Test func vanePositionsAreConfirmedOnSimulator() async {
        let api = SimulatedSmartThings(latency: .milliseconds(2))
        let engine = ACSyncEngine(deviceID: "sim-sala", api: api, configuration: .fast)
        await engine.refresh()
        #expect(engine.capabilities.verticalAirflowOptions.contains("6"))
        engine.request(.verticalAirflow, .text("2"))
        engine.request(.horizontalAirflow, .text("swing"))
        engine.request(.horizontalSwingRange, .text("left"))
        engine.request(.display, .bool(false))
        engine.request(.beep, .bool(true))
        #expect(await waitUntil { engine.activity == .idle && engine.sendable.isEmpty && engine.inflight.isEmpty })
        #expect(engine.confirmed?.verticalAirflow == "2")
        #expect(engine.confirmed?.horizontalAirflow == "swing")
        #expect(engine.confirmed?.horizontalSwingRange == "left")
        #expect(engine.confirmed?.displayOn == false)
        #expect(engine.confirmed?.beepOn == true)
        #expect(engine.unconfirmed.isEmpty)

        // Voltar a uma posição fixa depois de oscilar.
        engine.request(.horizontalAirflow, .text("5"))
        #expect(await waitUntil { engine.activity == .idle && engine.sendable.isEmpty && engine.inflight.isEmpty })
        #expect(engine.confirmed?.horizontalAirflow == "5")
    }

    @MainActor
    @Test func vanePositionsAreHeldWhileOff() async {
        let api = SimulatedSmartThings(latency: .milliseconds(2))
        let engine = ACSyncEngine(deviceID: "sim-sala", api: api, configuration: .fast)
        await engine.refresh()
        engine.request(.power, .bool(false))
        #expect(await waitUntil { engine.activity == .idle && engine.sendable.isEmpty && engine.inflight.isEmpty })
        engine.request(.verticalAirflow, .text("1"))
        #expect(engine.held == [.verticalAirflow])
    }
}
