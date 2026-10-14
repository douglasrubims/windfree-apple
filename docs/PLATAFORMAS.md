# Arquitetura e plataformas futuras

Existem os apps de macOS (barra de menus), iOS/iPadOS e watchOS. Todos reutilizam o mesmo núcleo
(`WindFreeKit`) e o mesmo modelo do app (`Apps/Shared/Core`); as telas de controle são compartilhadas entre
Mac e iPhone/iPad, e o relógio tem telas próprias.

## Camadas

```
Packages/WindFreeKit           (Foundation, Observation, Security, os — sem SwiftUI/AppKit/UIKit)
├── API/            SmartThingsAPI (protocolo), SmartThingsClient (URLSession), erros, transporte injetável
├── Auth/           OAuthService, CredentialManager (renovação), SecureStore + KeychainStore
├── Model/          DeviceSummary/DeviceStatus, ACState, ACCapabilities, ACInterpreter, ACCommandBuilder
├── Sync/           ACSyncEngine (fila, agrupamento, retenção, confirmação), PollingPolicy, RefreshScheduler
├── Simulation/     SimulatedSmartThings (dados simulados)
└── Support/        JSONValue, DiagnosticReport

Apps/Shared
├── Core/           AppModel (credenciais, aparelhos, ciclo de vida), Preferences, Labels — Mac, iOS e watchOS
└── Views/          Controles, pás, fluxo de ar, recursos do aparelho, conta, status — Mac e iOS

Apps/macOS/WindFree            (específico do Mac)
├── App/            WindFreeApp (MenuBarExtra + Settings)
├── Platform/       LoginItemController (SMAppService), PanelWindowObserver, MacSystemEvents (suspensão/tela)
├── Views/          Painel, página de ajustes do painel, janela de ajustes
└── Debug/          Gerador de capturas (somente Debug)

Apps/iOS/WindFree              (iPhone e iPad)
├── WindFreeiOSApp  Ciclo de vida por scenePhase (consulta só em primeiro plano)
├── RootView        Pilha no iPhone; lista de aparelhos + controles no iPad; folha de ajustes
└── WatchLink/WatchSetupView  Autorização do relógio e envio por WatchConnectivity

Apps/watchOS/WindFree          (Apple Watch, embutido no app do iPhone)
├── WindFreeWatchApp  Ciclo de vida por scenePhase
├── WatchReceiver     Recebe a autorização do iPhone e grava no Keychain do relógio
└── WatchViews        Temperatura (Digital Crown), liga/desliga, modo; demais recursos e pás em "mais"
```

As fronteiras entre núcleo e plataforma são poucas e simples:

| Interface | macOS hoje | iOS/iPadOS | watchOS |
|---|---|---|---|
| `SmartThingsAPI` | `SmartThingsClient` ou simulação | igual | igual |
| `AccessTokenProvider` | `CredentialManager` (PAT ou OAuth próprio) | `CredentialManager` (autorização própria do aparelho; para distribuição pública, servidor de troca) | token recebido do iPhone ou do servidor |
| `SecureStore` | `KeychainStore` | `KeychainStore` | `KeychainStore` |
| Visibilidade/energia | `PanelWindowObserver`, `MacSystemEvents` | `scenePhase` → `panelVisible`, `suspend`/`resume` | `scenePhase`, modo de baixo consumo |
| Atualização em segundo plano | processo residente + `RefreshScheduler` | `BGAppRefreshTask`/WidgetKit | `WKApplicationRefreshBackgroundTask`/complicações |

`ACSyncEngine` é `@MainActor @Observable`: qualquer interface SwiftUI observa diretamente o estado exibido,
os pedidos pendentes, os retidos e os não confirmados.

## iOS e iPadOS (implementado)

- Um único alvo para iPhone e iPad. iPhone: pilha com os controles, status e recursos do aparelho; iPad com
  largura regular e mais de um aparelho: `NavigationSplitView` com a lista de aparelhos.
- Mesmo `AppModel` e mesmas telas do Mac. O que muda: ciclo de vida por `scenePhase` (consulta a cada 15 s com o
  app aberto, para em segundo plano), botões redondos de 44 pt e ajustes numa folha.
- Autenticação: a mesma do Mac (app OAuth do próprio usuário, copiar e colar o endereço final), com autorização
  separada do Mac. Para distribuição pública seria preciso um servidor de troca de tokens; ver
  [AUTENTICACAO.md](AUTENTICACAO.md#implicações-para-ios-ipados-e-watchos).
- Não implementado: atualização em segundo plano (`BGAppRefreshTask` é oportunista), widget e Atalhos.

## watchOS (implementado, independente)

- Tela principal: temperatura pela Digital Crown (ou − e +), liga/desliga e modo. Em "mais", os mesmos
  recursos do iPhone que o aparelho declarar: vento, direção, WindFree, sono, modo especial; pás verticais e
  laterais (posição pela Digital Crown, botão Oscilar) e alcance lateral; luz do display, bipe, limpeza
  automática; filtro (uso, aviso, zerar) e consumo; aparelho, desconexão e, em Avançado, dados simulados.
- **Independente:** o relógio tem autorização própria e fala direto com o SmartThings (Wi‑Fi/celular), mesmo
  sem o iPhone. `WKRunsIndependentlyOfCompanionApp = YES`.
- **Credencial:** o relógio não faz login (não há navegador prático nele). O iPhone faz uma autorização OAuth
  separada, com o mesmo app OAuth, e a envia por `WCSession.sendMessage` com o app do relógio aberto. Mensagem
  direta e criptografada entre aparelhos pareados, sem `applicationContext`/`transferUserInfo`, que ficariam
  gravados em disco até a entrega. O relógio guarda no próprio Keychain e renova sozinho; cada aparelho tem a
  sua autorização, então um não invalida o outro.
- Consultas só com o app em primeiro plano. Não implementado: complicações e atualização em segundo plano
  (`WKApplicationRefreshBackgroundTask`).

## O que não foi feito de propósito

- Nenhum servidor de troca de tokens foi criado (necessário só para distribuição a terceiros).
- O pacote declara iOS 17 e watchOS 10 e **compila** para essas plataformas
  (`xcodebuild -scheme WindFreeKit -destination generic/platform=iOS|watchOS`), mas não foi executado nelas.
