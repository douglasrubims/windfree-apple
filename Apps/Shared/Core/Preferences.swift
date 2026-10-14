import Foundation
import Observation

/// Configurações não sensíveis (UserDefaults). Tokens e segredos ficam no Keychain.
@MainActor
@Observable
final class Preferences {
    enum MenuBarTemperature: String, CaseIterable, Identifiable {
        case target, ambient
        var id: String { rawValue }
        var title: String { self == .target ? "Desejada" : "Ambiente" }
    }

    private let defaults: UserDefaults

    var useSimulation: Bool {
        didSet { defaults.set(useSimulation, forKey: Keys.useSimulation) }
    }

    var selectedDeviceID: String? {
        didSet { defaults.set(selectedDeviceID, forKey: Keys.selectedDeviceID) }
    }

    var menuBarTemperature: MenuBarTemperature {
        didSet { defaults.set(menuBarTemperature.rawValue, forKey: Keys.menuBarTemperature) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // `-simulated YES` na linha de comando ou no esquema do Xcode força os dados simulados.
        useSimulation = defaults.bool(forKey: Keys.useSimulation) || defaults.bool(forKey: "simulated")
        selectedDeviceID = defaults.string(forKey: Keys.selectedDeviceID)
        menuBarTemperature = MenuBarTemperature(rawValue: defaults.string(forKey: Keys.menuBarTemperature) ?? "")
            ?? .target
    }

    private enum Keys {
        static let useSimulation = "useSimulation"
        static let selectedDeviceID = "selectedDeviceID"
        static let menuBarTemperature = "menuBarTemperature"
    }
}
