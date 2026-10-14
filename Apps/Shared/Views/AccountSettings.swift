import SwiftUI
import WindFreeKit

/// Conta SmartThings: conexão atual e OAuth (o caminho normal); em "Avançado", token pessoal (testes) e
/// dados simulados.
/// Comum ao Mac (janela de ajustes) e ao iPhone/iPad (folha de ajustes).
struct AccountSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var redirectURI = AppModel.defaultRedirectURI
    @State private var pastedCallback = ""
    @State private var personalToken = ""
    @State private var tokenExpiry = Date().addingTimeInterval(24 * 3600)
    @State private var busy = false
    @State private var oauthStatus: String?
    @State private var oauthStatusIsError = false
    @State private var tokenStatus: String?
    @State private var showingAdvanced = false

    var body: some View {
        Form {
            Section("Conexão atual") {
                currentConnection
            }

            Section {
                if model.credentialSummary == nil, !model.isSimulated {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Crie um app OAuth na sua conta SmartThings (uma vez).")
                        Text("2. Informe o Client ID e o Client Secret abaixo.")
                        Text("3. Autorize no navegador e cole aqui o endereço final.")
                        Link("Como criar o app OAuth", destination: Self.guideURL)
                    }
                    .font(.callout)
                }
                Group {
                    TextField("Client ID", text: $clientID)
                    SecureField("Client Secret", text: $clientSecret)
                    TextField("Endereço de retorno", text: $redirectURI)
                }
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                HStack {
                    Button("Autorizar no navegador") { authorize() }
                        .disabled(clientID.isEmpty || clientSecret.isEmpty || redirectURI.isEmpty || busy)
                    if model.oauthRequest != nil {
                        Text("Aguardando o endereço final…").font(.caption).foregroundStyle(.secondary)
                        Button("Cancelar") { model.cancelOAuth() }.buttonStyle(.borderless)
                    }
                }
                if model.oauthRequest != nil {
                    Text("""
                    No navegador, entre na conta, escolha o local e autorize. A página final pode mostrar \
                    "404 Not Found" — é esperado. Copie o endereço completo da barra (com code=…) e cole aqui.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Endereço com code=…", text: $pastedCallback)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                        PasteButton(payloadType: String.self) { values in
                            if let value = values.first { pastedCallback = value }
                        }
                        .labelStyle(.iconOnly)
                    }
                    HStack {
                        Button("Concluir") { completePasted() }
                            .disabled(pastedCallback.isEmpty || busy)
                        if busy { ProgressView().controlSize(.small) }
                    }
                }
                if let oauthStatus {
                    Text(oauthStatus).font(.callout)
                        .foregroundStyle(oauthStatusIsError ? Color.orange : Color.primary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Conectar conta SmartThings")
            } footer: {
                Text("""
                O app OAuth ("API Access") é registrado por você, com os escopos `r:devices:*`, `x:devices:*` e \
                `r:locations:*` (nomes dos cômodos) e o endereço de retorno \(OAuthService.smartThingsRedirectURI). \
                O segredo fica só no Keychain deste aparelho. O app renova o acesso sozinho; sem uso por 29 dias, \
                será preciso autorizar de novo.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup("Avançado", isExpanded: $showingAdvanced) {
                    advanced
                }
            }
        }
        .formStyle(.grouped)
        .disabled(busy)
        .onAppear {
            // Abre o "Avançado" quando algo dele está em uso.
            if model.isSimulated || model.credentialSummary?.kind == .personalToken { showingAdvanced = true }
        }
    }

    /// Token pessoal (testes) e dados simulados, fora do caminho principal.
    @ViewBuilder
    private var advanced: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token pessoal — somente para testes").font(.headline)
            SecureField("Token pessoal", text: $personalToken)
                .autocorrectionDisabled()
            DatePicker("Expira em", selection: $tokenExpiry, displayedComponents: [.date, .hourAndMinute])
            Button("Validar e salvar") { savePersonalToken() }
                .disabled(personalToken.isEmpty || busy)
            if let tokenStatus {
                Text(tokenStatus).font(.callout)
            }
            Text("""
            Tokens criados em account.smartthings.com/tokens valem 24 horas: servem para validar a integração, \
            não como acesso definitivo. Permissões: listar, ver e controlar aparelhos; ver locais (cômodos).
            """)
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        Toggle("Dados simulados", isOn: Binding(
            get: { model.preferences.useSimulation },
            set: { value in Task { await model.setSimulation(value) } }
        ))
        Text("Aparelhos fictícios, para demonstração e desenvolvimento, sem conta nem rede.")
            .font(.caption).foregroundStyle(.secondary)
    }

    static let guideURL = URL(string: "https://github.com/douglasrubims/windfree-apple/blob/main/docs/AUTENTICACAO.md")!

    @ViewBuilder
    private var currentConnection: some View {
        if model.isSimulated {
            Label("Dados simulados", systemImage: "testtube.2")
        } else if let summary = model.credentialSummary {
            switch summary.kind {
            case .oauth:
                Label("Conectado via OAuth", systemImage: "checkmark.seal")
                if let refresh = summary.refreshExpiresAt {
                    Text("Renovação automática. Autorização válida sem uso até \(refresh.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .personalToken:
                Label("Token pessoal (temporário)", systemImage: "clock.badge.exclamationmark")
                if let expiry = summary.accessExpiresAt {
                    Text(expiry > .now
                        ? "Expira \(expiry.formatted(.relative(presentation: .named)))."
                        : "Expirado em \(expiry.formatted(date: .abbreviated, time: .shortened)).")
                        .font(.caption).foregroundStyle(expiry > .now ? Color.secondary : Color.orange)
                }
            }
            if summary.kind == .oauth {
                Button("Autorizar de novo (mesmo app OAuth)") { reauthorize() }
                    .disabled(busy)
            }
            if model.roomsUnavailable {
                Text("""
                Os cômodos não aparecem porque a autorização não tem a permissão `r:locations:*`. Inclua essa \
                permissão no app OAuth (smartthings apps:oauth:update) e toque em "Autorizar de novo".
                """)
                .font(.caption).foregroundStyle(.secondary)
            }
            Button("Desconectar e apagar credenciais") {
                Task { await model.signOut() }
            }
        } else {
            Text("Nenhuma conta conectada.").foregroundStyle(.secondary)
        }
    }

    private func authorize() {
        oauthStatus = nil
        let client = OAuthClientConfiguration(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            openURL(try model.beginOAuth(client: client))
            clientSecret = ""
            pastedCallback = ""
        } catch {
            show(error: error)
        }
    }

    private func reauthorize() {
        oauthStatus = nil
        Task {
            do {
                openURL(try await model.beginReauthorization())
                pastedCallback = ""
            } catch {
                show(error: error)
            }
        }
    }

    private func completePasted() {
        guard let url = URL(string: pastedCallback.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            show(error: OAuthError.missingCode)
            return
        }
        busy = true
        oauthStatus = "Trocando o código pelo acesso…"
        oauthStatusIsError = false
        Task {
            defer { busy = false }
            do {
                try await model.completeOAuth(callbackURL: url)
                pastedCallback = ""
                oauthStatus = "Conta conectada via OAuth."
            } catch {
                show(error: error)
            }
        }
    }

    private func show(error: Error) {
        oauthStatus = AppModel.message(for: error)
        oauthStatusIsError = true
    }

    private func savePersonalToken() {
        busy = true
        tokenStatus = "Validando…"
        Task {
            defer { busy = false }
            do {
                try await model.savePersonalToken(personalToken, expiresAt: tokenExpiry)
                personalToken = ""
                tokenStatus = "Token validado e salvo no Keychain."
            } catch {
                tokenStatus = AppModel.message(for: error)
            }
        }
    }
}
