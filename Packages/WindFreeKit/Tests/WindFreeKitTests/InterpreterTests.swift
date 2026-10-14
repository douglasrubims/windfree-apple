import Foundation
import Testing
@testable import WindFreeKit

@Suite("Interpretação de estado e capacidades")
struct InterpreterTests {
    @Test func interpretsState() throws {
        let state = ACInterpreter.state(from: try Fixtures.status())
        #expect(state.isOn == true)
        #expect(state.targetTemperature == 21)
        #expect(state.temperatureUnit == .celsius)
        #expect(state.ambientTemperature == 26)
        #expect(state.humidity == 61)
        #expect(state.mode == "cool")
        #expect(state.fanMode == "auto")
        #expect(state.oscillation == "vertical")
        #expect(state.windFreeOn && state.sleepOn)
        #expect(state.displayOn == true)
        #expect(state.beepOn == false)
        #expect(state.autoCleanOn == true)
        #expect(state.filterUsage == 17)
        #expect(state.filterAlarmThreshold == 300)
        #expect(state.powerWatts == 640)
        #expect(state.energyKWh == 676.4)
    }

    @Test func interpretsCapabilitiesFromDevice() throws {
        let caps = ACInterpreter.capabilities(from: try Fixtures.status())
        #expect(caps.power)
        #expect(caps.targetTemperature == TemperatureRange(minimum: 16, maximum: 30))
        #expect(caps.modes == ["cool", "dry", "wind", "auto"])
        #expect(caps.fanModes.count == 5)
        #expect(caps.oscillationModes == ["fixed", "vertical", "horizontal", "all"])
        #expect(caps.supportsWindFree && caps.supportsSleep)
        #expect(caps.humidity && caps.ambientTemperature)
        // Iluminação aparece desativada, mas o display funciona via `execute`.
        #expect(caps.display)
        #expect(caps.beep && caps.autoClean && caps.filter && caps.energy)
        #expect(caps.filterAlarmThresholds == [180, 300, 500, 700])
    }

    @Test func disabledCapabilitiesAreHidden() throws {
        let json = Fixtures.statusJSON.replacingOccurrences(
            of: "\"custom.airConditionerTropicalNightMode\"", with: "\"audioVolume\", \"fanOscillationMode\"")
        let caps = ACInterpreter.capabilities(from: try Fixtures.status(json))
        #expect(!caps.beep)
        #expect(caps.oscillationModes.isEmpty)
        #expect(!caps.supports(.oscillation))
    }

    @Test func displayRequiresExecute() throws {
        let json = Fixtures.statusJSON.replacingOccurrences(of: "\"execute\":", with: "\"executeRemoved\":")
        #expect(!ACInterpreter.capabilities(from: try Fixtures.status(json)).display)
    }

    @Test func missingCapabilitiesMeanUnsupported() {
        var state = ACState.sample()
        state.filterUsage = nil
        let caps = ACInterpreter.capabilities(from: Fixtures.status(for: state))
        #expect(!caps.humidity)
        #expect(!caps.display)
        #expect(!caps.energy)
        #expect(!caps.filter)
        #expect(caps.oscillationModes.isEmpty)
        #expect(!caps.hasExtras)
    }

    @Test func rangeFromCoolingSetpointRange() throws {
        let json = """
        {"components":{"main":{
          "thermostatCoolingSetpoint":{
            "coolingSetpoint":{"value":75,"unit":"F"},
            "coolingSetpointRange":{"value":{"minimum":62,"maximum":84,"step":1},"unit":"F"}
          }}}}
        """
        let status = try Fixtures.status(json)
        #expect(ACInterpreter.capabilities(from: status).targetTemperature == TemperatureRange(minimum: 62, maximum: 84))
        #expect(ACInterpreter.state(from: status).temperatureUnit == .fahrenheit)
    }

    @Test func assumedRangeIsFlagged() throws {
        let json = #"{"components":{"main":{"thermostatCoolingSetpoint":{"coolingSetpoint":{"value":22,"unit":"C"}}}}}"#
        let range = try #require(ACInterpreter.capabilities(from: try Fixtures.status(json)).targetTemperature)
        #expect(range.isAssumed)
    }

    @Test func toleratesNullAndUnexpectedValues() throws {
        let json = #"{"components":{"main":{"switch":{"switch":{"value":null}},"temperatureMeasurement":{"temperature":{"value":"25.5"}},"airConditionerMode":{"supportedAcModes":{"value":[1,"cool",null]}}}}}"#
        let status = try Fixtures.status(json)
        let state = ACInterpreter.state(from: status)
        #expect(state.isOn == nil)
        #expect(state.ambientTemperature == 25.5)
        #expect(ACInterpreter.capabilities(from: status).modes == ["cool"])
    }

    @Test func rangeClampsAndSnaps() {
        let range = TemperatureRange(minimum: 16, maximum: 30, step: 0.5)
        #expect(range.clamp(10) == 16)
        #expect(range.clamp(22.3) == 22.5)
        #expect(range.clamp(40) == 30)
    }
}

@Suite("WindFree e modo sono")
struct OptionalModeTests {
    let all = ["off", "windFree", "sleep", "windFreeSleep"]
    let noCombo = ["off", "windFree", "sleep"]

    @Test func composesCombinations() {
        #expect(OptionalMode.compose(windFree: true, sleep: false, changed: .windFree, supported: all) == "windFree")
        #expect(OptionalMode.compose(windFree: true, sleep: true, changed: .sleep, supported: all) == "windFreeSleep")
        #expect(OptionalMode.compose(windFree: false, sleep: false, changed: .sleep, supported: all) == "off")
    }

    @Test func lastChoiceWinsWithoutCombinedMode() {
        #expect(OptionalMode.compose(windFree: true, sleep: true, changed: .sleep, supported: noCombo) == "sleep")
        #expect(OptionalMode.compose(windFree: true, sleep: true, changed: .windFree, supported: noCombo) == "windFree")
    }

    @Test func unsupportedReturnsNil() {
        #expect(OptionalMode.compose(windFree: false, sleep: true, changed: .sleep, supported: ["off", "windFree"]) == nil)
    }

    @Test func decomposes() {
        #expect(OptionalMode.hasWindFree("windFreeSleep") && OptionalMode.hasSleep("windFreeSleep"))
        #expect(!OptionalMode.hasWindFree("speed") && !OptionalMode.hasSleep(nil))
    }
}

@Suite("Montagem de comandos")
struct CommandBuilderTests {
    @Test func powerOnFirstPowerOffLast() {
        let on = ACCommandBuilder.steps(for: [.mode: .text("dry"), .power: .bool(true), .targetTemperature: .number(23)])
        #expect(on.first?.isPowerOn == true)
        #expect(on.map(\.settings) == [[.power], [.targetTemperature], [.mode]])

        let off = ACCommandBuilder.steps(for: [.power: .bool(false), .beep: .bool(true)])
        #expect(off.last?.commands.first?.command == "off")
        #expect(off.last?.isPowerOn == false)
    }

    @Test func buildsExpectedPayloads() throws {
        let temperature = try #require(ACCommandBuilder.commands(for: .targetTemperature, value: .number(23)).first)
        #expect(temperature.capability == "thermostatCoolingSetpoint")
        #expect(temperature.command == "setCoolingSetpoint")
        #expect(temperature.arguments == [.number(23)])

        let data = try JSONEncoder().encode(temperature)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        #expect(json["component"] == "main")
        #expect(String(decoding: data, as: UTF8.self).contains("[23]"))
    }

    /// Aparelho da referência: iluminação desativada, só o `execute` com opção invertida funciona.
    @Test func displayOptionIsInverted() throws {
        let caps = ACInterpreter.capabilities(from: try Fixtures.status())
        #expect(caps.displayControl == .samsungExecute)
        let on = try #require(ACCommandBuilder.commands(for: .display, value: .bool(true), capabilities: caps).first)
        #expect(on.capability == "execute")
        #expect(on.arguments.last?["x.com.samsung.da.options"]?.stringArray == ["Light_Off"])
    }

    @Test func mismatchedValueBuildsNothing() {
        #expect(ACCommandBuilder.commands(for: .mode, value: .bool(true)).isEmpty)
    }
}
