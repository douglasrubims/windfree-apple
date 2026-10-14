import SwiftUI
import WindFreeKit

/// Conecta o Apple Watch: o iPhone faz uma autorização própria para o relógio (mesmo app OAuth) e a envia
/// ao app do relógio, que a guarda no Keychain dele. Depois o relógio funciona sozinho, mesmo sem o iPhone.
struct WatchSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(WatchLink.self) private var watch
    @Environment(\.openURL) private var openURL

    @State private var pasted = ""
    @State private var busy = false
    @State private var status: String?
    @State private var statusIsError = false

    private var hasOAuth: Bool { model.credentialSummary?.kind == .oauth && !model.isSimulated }

    var body: some View {
        Form {
            Section {
                Label(watch.isAppInstalled ? "WindFree instalado no relógio" : "WindFree não instalado no relógio",
                      systemImage: watch.isAppInstalled ? "checkmark.circle" : "xmark.circle")
                Label(watch.isReachable ? "App do relógio aberto" : "Abra o WindFree no relógio",
                      systemImage: watch.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
                    .foregroundStyle(watch.isReachable ? Color.primary : Color.orange)
            } header: {
                Text("Relógio")
            } footer: {
                if !watch.isAppInstalled {
                    Text("Instale pelo app Watch do iPhone (Meu Relógio › Disponíveis) ou pelo Xcode.")
                }
            }

            if hasOAuth {
                Section {
                    Button("Autorizar o relógio no navegador") { authorize() }
                        .disabled(busy)
                    if model.companionRequest != nil {
                        Text("""
                        Entre na conta, escolha o local e autorize. Na página "404 Not Found", copie o endereço \
                        completo da barra e cole aqui. Mantenha o WindFree aberto no relógio.
                        """)
                        .font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            TextField("Endereço com code=…", text: $pasted)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            PasteButton(payloadType: String.self) { values in
                                if let value = values.first { pasted = value }
                            }
                            .labelStyle(.iconOnly)
                        }
                        Button("Enviar ao relógio") { complete() }
                            .disabled(pasted.isEmpty || busy || !watch.isReachable)
                    }
                    if let status {
                        Text(status).font(.callout).foregroundStyle(statusIsError ? Color.orange : Color.primary)
                    }
                } header: {
                    Text("Conectar")
                } footer: {
                    Text("""
                    O relógio recebe uma autorização própria, separada da do iPhone, e a renova sozinho. \
                    Ele passa a falar direto com o SmartThings pelo Wi‑Fi ou celular, mesmo longe do iPhone.
                    """)
                }

                Section {
                    Button("Desconectar o relógio", role: .destructive) { signOut() }
                        .disabled(busy || !watch.isReachable)
                }
            } else {
                Section {
                    Text("""
                    Conecte primeiro este iPhone por OAuth (Ajustes › Conta SmartThings). O relógio usa o mesmo \
                    app OAuth, com uma autorização própria.
                    """)
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Apple Watch")
        .onDisappear { model.cancelCompanionAuthorization() }
    }

    private func authorize() {
        status = nil
        pasted = ""
        Task {
            do {
                openURL(try await model.beginCompanionAuthorization())
            } catch {
                show(AppModel.message(for: error), error: true)
            }
        }
    }

    private func complete() {
        guard let url = URL(string: pasted.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            show(OAuthError.missingCode.userMessage, error: true)
            return
        }
        busy = true
        show("Trocando o código e enviando ao relógio…", error: false)
        Task {
            defer { busy = false }
            do {
                let credential = try await model.completeCompanionAuthorization(callbackURL: url)
                try await watch.send(credential)
                pasted = ""
                show("Relógio conectado.", error: false)
            } catch WatchLink.Failure.notReachable {
                show("Abra o WindFree no relógio e tente de novo (autorize de novo: o código é de uso único).",
                     error: true)
            } catch {
                show(AppModel.message(for: error), error: true)
            }
        }
    }

    private func signOut() {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await watch.signOutWatch()
                show("Credenciais apagadas do relógio.", error: false)
            } catch {
                show("Não foi possível falar com o relógio. Abra o WindFree nele e tente de novo.", error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        status = text
        statusIsError = error
    }
}
