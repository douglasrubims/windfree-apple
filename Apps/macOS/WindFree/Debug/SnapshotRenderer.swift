#if DEBUG
import AppKit
import OSLog
import SwiftUI
import WindFreeKit

/// Gera capturas das telas reais com dados simulados, em modo claro e escuro, para revisão visual.
/// Só existe em Debug. Uso:
///   open WindFree.app --args -simulated YES -renderSnapshots YES
/// As imagens ficam em ~/Library/Containers/io.github.douglasrubims.WindFree/Data/Library/Caches/Snapshots
@MainActor
enum SnapshotRenderer {
    static var isRequested: Bool { UserDefaults.standard.bool(forKey: "renderSnapshots") }

    static func run(model: AppModel) async {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        await waitUntil { model.phase == .ready && model.engine?.isLoaded == true }
        model.select("sim-sala")
        await waitUntil { model.engine?.deviceID == "sim-sala" && model.engine?.isLoaded == true }
        guard let sala = model.engine else { exit(1) }
        model.panelVisible = true

        for (suffix, appearance) in [("claro", NSAppearance.Name.aqua), ("escuro", .darkAqua)] {
            save(PanelView().environment(model).environment(LoginItemController()), "1-painel-ligado-\(suffix)", appearance, folder)
            save(DeviceSettingsView(engine: sala, close: {}).frame(width: 330).environment(model).environment(LoginItemController()), "3-ajustes-\(suffix)", appearance,
                 folder)
            save(SettingsView().environment(model).environment(LoginItemController()), "5-conta-\(suffix)", appearance, folder)
        }

        // Pás laterais oscilando: botão ativo, controle esmaecido e alcance lateral visível.
        sala.request(.horizontalAirflow, .text("swing"))
        await waitUntil(timeout: 10) { sala.confirmed?.horizontalAirflow == "swing" && sala.activity == .idle }
        save(PanelView().environment(model).environment(LoginItemController()), "7-pas-oscilando-claro", .aqua, folder)
        sala.request(.horizontalAirflow, .text("2"))
        await waitUntil(timeout: 10) { sala.confirmed?.horizontalAirflow == "2" && sala.activity == .idle }

        // Aparelho desligado com ajustes retidos até ligar.
        if let quarto = model.devices.first(where: { $0.id == "sim-quarto" }) {
            model.select(quarto.id)
            await waitUntil { model.engine?.isLoaded == true }
            model.engine?.request(.targetTemperature, .number(20))
            model.engine?.request(.fanMode, .text("high"))
            try? await Task.sleep(for: .seconds(1.5))
            for (suffix, appearance) in [("claro", NSAppearance.Name.aqua), ("escuro", .darkAqua)] {
                save(PanelView().environment(model).environment(LoginItemController()), "2-painel-desligado-retido-\(suffix)", appearance, folder)
            }
            if let engine = model.engine {
                save(DeviceSettingsView(engine: engine, close: {}).environment(model).environment(LoginItemController()), "3b-ajustes-compacto-claro",
                     .aqua, folder)
            }
        }

        // Comando não confirmado: o simulador recusa WindFree fora do modo resfriar.
        if let sala = model.devices.first(where: { $0.id == "sim-sala" }) {
            model.select(sala.id)
            await waitUntil { model.engine?.isLoaded == true }
            model.engine?.request(.mode, .text("dry"))
            await waitUntil(timeout: 10) { model.engine?.confirmed?.mode == "dry" && model.engine?.activity == .idle }
            model.engine?.request(.optionalMode, .text("windFree"))
            await waitUntil(timeout: 15) { model.engine?.unconfirmed.isEmpty == false }
            save(PanelView().environment(model).environment(LoginItemController()), "4-nao-confirmado-claro", .aqua, folder)
        }

        // Aparelho offline.
        if let office = model.devices.first(where: { $0.id == "sim-escritorio" }) {
            model.select(office.id)
            await waitUntil { model.engine?.isLoaded == true }
            save(PanelView().environment(model).environment(LoginItemController()), "6-offline-escuro", .darkAqua, folder)
        }

        print("Capturas em \(folder.path)")
        exit(0)
    }

    /// Grava, lê e apaga um item fictício no Keychain do app (sandbox + assinatura atual) e encerra.
    /// Uso: open WindFree.app --args -keychainSelfTest YES  → resultado no log (categoria "debug").
    static var isKeychainCheckRequested: Bool { UserDefaults.standard.bool(forKey: "keychainSelfTest") }

    static func runKeychainCheck() -> Never {
        let log = Logger(subsystem: "io.github.douglasrubims.WindFree", category: "debug")
        let store = KeychainStore(service: AppModel.keychainService + ".selftest")
        let key = "selftest"
        let payload = Data("valor-ficticio".utf8)
        do {
            try store.write(payload, for: key)
            let read = try store.read(key)
            try store.write(Data("atualizado".utf8), for: key)
            let updated = try store.read(key)
            try store.delete(key)
            let gone = try store.read(key)
            let ok = read == payload && updated == Data("atualizado".utf8) && gone == nil
            log.notice("Keychain self-test: \(ok ? "OK" : "FALHOU", privacy: .public)")
            exit(ok ? 0 : 1)
        } catch {
            log.error("Keychain self-test: erro \(String(describing: error), privacy: .public)")
            exit(2)
        }
    }

    private static func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func save<V: View>(_ view: V, _ name: String, _ appearance: NSAppearance.Name, _ folder: URL) {
        let hosting = NSHostingView(rootView: view
            .background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 10, height: 10),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        // Sempre em 2x (Retina), independentemente da tela em que a janela invisível cair.
        let bounds = hosting.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2),
                                         pixelsHigh: Int(bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0)
        else { return }
        rep.size = bounds.size
        hosting.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
#endif
