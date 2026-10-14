# WindFree para Mac, iPhone, iPad e Apple Watch

Aplicativo nativo para controlar ar-condicionado Samsung WindFree pela API oficial do SmartThings. No Mac,
fica na barra de menus com a temperatura e abre um painel compacto; no iPhone e no iPad, é um app com os
mesmos controles e layout adaptável; no Apple Watch, controles essenciais com a Digital Crown, funcionando
sem o iPhone por perto.

Escrito em Swift e SwiftUI, sem Electron, WebView, Node ou SmartThings CLI. O núcleo (API, autenticação,
interpretação de capacidades, fila de comandos e confirmação) fica num pacote Swift independente de interface,
compartilhado pelos apps de Mac, iPhone/iPad e Apple Watch.

> **Situação:** em uso com um Samsung WindFree 2026 (com aquecimento) no Mac, iPhone e Apple Watch, com login
> OAuth. Alguns recursos ainda não foram confirmados individualmente no aparelho; veja
> [docs/VALIDACAO.md](docs/VALIDACAO.md). Projeto pessoal, sem relação com a Samsung.

## Recursos

- Temperatura na barra de menus (desejada ou ambiente); sem ícone no Dock.
- Painel: ligar/desligar, temperatura desejada (botões e controle deslizante), temperatura ambiente,
  umidade, modo, velocidade do vento, direção (oscilação ou, nos modelos que permitem, controles deslizantes com a
  posição exata das pás verticais e laterais, botão Oscilar e alcance da oscilação lateral), WindFree e modo sono.
- Página de ajustes: modo especial (silencioso, inteligente, rápido…), luz do display, bipe, limpeza automática,
  filtro (uso, alerta e zerar contador) e consumo de energia.
- Tudo aparece **somente se o aparelho declarar a capacidade**. Modos, velocidades, direções e faixa de
  temperatura vêm do próprio aparelho, nada é fixo por modelo.
- Vários aparelhos na conta: escolha pelo título do painel ou nos ajustes, com o nome do cômodo
  ("Ar condicionado · Quarto") quando a autorização inclui `r:locations:*`.
- Início automático opcional, modo claro e escuro, painel fecha ao clicar fora ou com Esc.

### Sincronização

- Cliques seguidos são agrupados (600 ms) e viram um único comando.
- O painel diferencia o que foi **pedido** (enviando…), o que foi **confirmado** pelo aparelho e o que
  **não foi confirmado** (o painel volta ao estado real e avisa).
- Com o ar desligado, ajustes de clima (temperatura, modo, vento, direção, WindFree/sono) ficam marcados
  "Aplicado ao ligar" e são enviados logo depois do comando de ligar — também se o ar for ligado por outro
  meio (controle remoto, app SmartThings).
- Nunca há duas requisições simultâneas para o mesmo aparelho.
- Consultas: a cada 15 s com o painel aberto; a cada 2 min com ele fechado (5 min no modo de baixo consumo);
  param com a tela apagada ou o Mac suspenso e voltam ao acordar. Falhas aumentam a espera
  progressivamente (até 10 min) e o limite da API (HTTP 429) é respeitado.
- A animação do fluxo de ar só roda com o painel visível e o ar ligado (e respeita "Reduzir movimento").

## Requisitos

| | |
|---|---|
| macOS | 14 Sonoma ou mais novo (usa Observation, `MenuBarExtra`, `SMAppService`, `openSettings`) |
| iPhone/iPad | iOS/iPadOS 17 ou mais novo |
| Apple Watch | watchOS 10 ou mais novo |
| Mac | Apple Silicon ou Intel (o empacotamento gera binário universal) |
| Para compilar | Xcode 16 ou mais novo (testado no Xcode 27 / Swift 6.4, macOS 27, arm64) |
| Conta | Ar-condicionado já configurado no app SmartThings, numa conta Samsung |

## Execução

### Pelo Xcode

1. Abra `WindFree.xcodeproj`.
2. Esquema **WindFree**, destino **My Mac**, ⌘R.
3. O ícone aparece na barra de menus. Sem conta configurada, o painel oferece **Conectar conta…**, que abre a
   conexão por OAuth (ver [Configurar a autenticação](#configurar-a-autenticação)).

Dados simulados (aparelhos fictícios, para demonstração e desenvolvimento) ficam em **Ajustes › Conta ›
Avançado**, ou direto com o argumento `-simulated YES` em
*Product › Scheme › Edit Scheme › Run › Arguments*.

### Pela linha de comando

```bash
xcodebuild -project WindFree.xcodeproj -scheme WindFree -configuration Debug -derivedDataPath build/DerivedData build
```

```bash
open build/DerivedData/Build/Products/Debug/WindFree.app --args -simulated YES
```

### Testes

```bash
swift test --package-path Packages/WindFreeKit
```

Também rodam pelo Xcode (⌘U no esquema WindFree).

## iPhone e iPad

O alvo **WindFree-iOS** (iOS/iPadOS 17 ou mais novo) usa o mesmo núcleo e as mesmas telas de controle do
Mac. No iPhone, uma tela com os controles e os recursos do aparelho; no iPad com espaço e mais de um
aparelho, lista de aparelhos ao lado. As consultas acontecem com o app aberto e param em segundo plano.

### No simulador

No Xcode, escolha o esquema **WindFree-iOS** e um simulador de iPhone ou iPad e pressione ⌘R. Para dados
simulados, ative `-simulated YES` em *Edit Scheme › Run › Arguments*.

### No seu iPhone

1. Conecte o iPhone ao Mac por cabo (ou na mesma rede, depois do primeiro pareamento) e confie no computador.
2. No iPhone: **Ajustes › Privacidade e Segurança › Modo de Desenvolvedor**, ative e reinicie.
3. No Xcode: *Settings › Accounts*, adicione sua Apple ID. Para não gravar o ID da sua equipe no projeto
   (que é público), crie na raiz do repositório o arquivo `Local.xcconfig` (ignorado pelo git) com
   `DEVELOPMENT_TEAM = SEU_TEAM_ID`; o alvo iOS lê esse arquivo por `Apps/iOS/Signing.xcconfig`. O Team ID
   aparece em *Settings › Accounts* ao selecionar a equipe. (Escolher o Team em *Signing & Capabilities* também
   funciona, mas grava o ID no `project.pbxproj`.) Se o identificador `io.github.douglasrubims.WindFree` não
   estiver disponível para a sua equipe, troque por outro único.
4. Escolha o seu iPhone como destino no esquema **WindFree-iOS** e pressione ⌘R.
5. Na primeira vez, confie no desenvolvedor no iPhone: **Ajustes › Geral › VPN e Gerenciamento de
   Dispositivos › App de Desenvolvedor › Confiar**.

Pela linha de comando (com o iPhone conectado):

```bash
xcodebuild -project WindFree.xcodeproj -scheme WindFree-iOS -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData -allowProvisioningUpdates build
```

Com Apple ID gratuita o app vale **7 dias** e precisa ser instalado de novo pelo Xcode; com o Apple Developer
Program, 1 ano.

### Conta no iPhone

O Keychain do Mac não passa para o iPhone: o iPhone faz a própria autorização (cada aparelho com a sua, o que
evita um derrubar a renovação do outro). Em **Ajustes › Conta SmartThings**, use o mesmo Client ID, Client
Secret e endereço de retorno do Mac, toque em **Autorizar no navegador**, autorize no Safari, copie o endereço
da página 404 e toque em **Colar** no WindFree. Depois **Concluir**.

## Apple Watch

O alvo **WindFree-watchOS** (watchOS 10 ou mais novo) vem embutido no app do iPhone. Tela principal com a
temperatura (Digital Crown ou − e +), modo e liga/desliga; em "mais", os demais recursos do iPhone: vento,
WindFree, sono, modo especial, pás (posição pela Digital Crown ou oscilar), display, bipe, limpeza, filtro,
consumo e aparelho. O relógio é **independente**: tem a própria autorização e fala direto com o SmartThings pelo Wi‑Fi
ou celular do relógio, mesmo longe do iPhone.

**Conectar o relógio** (uma vez, com o iPhone já conectado por OAuth):

1. Abra o WindFree no relógio e deixe aberto.
2. No iPhone: **Ajustes › Apple Watch › Autorizar o relógio no navegador**. Autorize no Safari, copie o
   endereço da página 404, volte, toque em **Colar** e em **Enviar ao relógio**.
3. O iPhone faz uma autorização separada (mesmo app OAuth) e a envia ao relógio por WatchConnectivity, com o
   app do relógio aberto, sem filas gravadas em disco. O relógio guarda no próprio Keychain e renova sozinho.

**No relógio de verdade:** com o iPhone conectado ao Mac e desbloqueado, ative no relógio **Ajustes ›
Privacidade e Segurança › Modo de Desenvolvedor** (a opção aparece depois que o Xcode reconhece o relógio,
por exemplo abrindo *Window › Devices and Simulators*). Depois rode o esquema **WindFree-iOS** no iPhone; o app
do relógio é instalado junto (ou em **Watch › Meu Relógio › Disponíveis**). Também dá para rodar o esquema
**WindFree-watchOS** direto num simulador de Apple Watch.

## Gerar o .app

```bash
scripts/build-app.sh
```

Gera `dist/WindFree.app` (Release, universal, sandbox, hardened runtime, assinatura ad-hoc) e
`dist/WindFree.zip`. Copie o app para `/Applications` e abra pelo Finder; ele não depende do terminal nem de
variáveis de ambiente. Para que o início automático aponte para o lugar certo, ative-o depois de mover o app.

A assinatura ad-hoc vale para este Mac. Para outras pessoas é preciso assinar com um certificado
Developer ID e notarizar (`xcrun notarytool`); sem isso o Gatekeeper bloqueia o app baixado.

## Configurar a autenticação

Resumo — os detalhes, fontes e implicações estão em [docs/AUTENTICACAO.md](docs/AUTENTICACAO.md).

- **Uso contínuo (recomendado): OAuth.** Registre um app *API Access* na sua conta (uma vez, por exemplo com
  `npx @smartthings/cli@2.1.2 apps:create`), com escopos `r:devices:*`, `x:devices:*` e `r:locations:*` (nomes dos cômodos) e o endereço de retorno
  `https://api.smartthings.com/installedapp`. No WindFree: **Ajustes › Conta › Conectar conta SmartThings**, informe Client ID,
  Client Secret e o endereço, e clique em **Autorizar no navegador**. Depois de autorizar, o navegador para
  numa página 404 do SmartThings: copie o endereço dela, cole no WindFree e clique em **Concluir**. O app renova o
  acesso sozinho; após 29 dias sem uso é preciso autorizar de novo.
- **Validação rápida: token pessoal** (em **Ajustes › Conta › Avançado**). Crie em
  <https://account.smartthings.com/tokens>. Vale **24 horas** e
  não é uma autenticação definitiva.

Tokens e segredos ficam só no Keychain deste Mac. Nada sensível vai para UserDefaults, logs ou arquivos.

## Diagnóstico do aparelho

Em **Ajustes › Exportar diagnóstico** o app grava um JSON com as capacidades e o status bruto do aparelho,
**sem** identificadores (IDs, nomes, número de série, MAC são removidos). Serve para conferir o mapeamento de
comandos contra o aparelho real. O arquivo fica em
`~/Library/Containers/io.github.douglasrubims.WindFree/Data/Library/Application Support/WindFree/`.
Revise antes de compartilhar.

## Estrutura

```
WindFree.xcodeproj         Projeto com os alvos WindFree (macOS) e WindFree-iOS (iPhone e iPad)
Apps/Shared/Core/          Modelo do app e textos, comuns a Mac, iPhone/iPad e Apple Watch
Apps/Shared/Views/         Telas comuns ao Mac e ao iPhone/iPad (SwiftUI, sem AppKit/UIKit)
Apps/macOS/WindFree/       Barra de menus, ajustes e integração com o Mac (AppKit)
Apps/iOS/WindFree/         App de iPhone e iPad (inclui a conexão com o Apple Watch)
Apps/watchOS/WindFree/     App do Apple Watch
Packages/WindFreeKit/      Núcleo compartilhado (sem SwiftUI/AppKit) e testes
docs/                      Autenticação, plataformas futuras e validação
scripts/                   Empacotamento e geração do ícone
```

Arquitetura por plataforma: [docs/PLATAFORMAS.md](docs/PLATAFORMAS.md).

## Limitações conhecidas

- Validado com um único modelo (WindFree 2026 com aquecimento). Outros modelos podem expor recursos por
  capacidades diferentes; o app só mostra o que o aparelho declara, e o diagnóstico ajuda a ajustar o
  mapeamento.
- **Resfriamento em 5 etapas** e **limpeza a frio** não aparecem na API pública do SmartThings (não constam no
  status do aparelho; ver relatos na comunidade SmartThings), por isso não estão nos apps.
- **Luz do display**: usa `setLightingLevel` quando a capacidade de iluminação está ativa (caso do aparelho
  validado). Se estiver desativada, recorre a um comando `execute` da Samsung com a opção invertida, observado
  no projeto de referência, que pode não funcionar em outros modelos.
- **Pás**: a numeração das posições é a do próprio aparelho (a mesma do app SmartThings); o app não sabe se a
  posição 1 é a mais alta ou a mais baixa.
- A retenção de ajustes com o ar desligado assume que o aparelho ignora esses comandos desligado (comportamento
  descrito na referência). Se o seu aparelho aceitar, a retenção apenas atrasa o envio até ligar.
- Se o aparelho não informar a faixa de temperatura, o app usa 16–30 °C (60–86 °F) e avisa no painel.
- O SmartThings não permite retorno automático do OAuth para o Mac: o cadastro exige `https` e a autorização
  bloqueia `localhost`. O usuário copia o endereço final (página 404 do próprio SmartThings) e cola no app.
  Ver [docs/AUTENTICACAO.md](docs/AUTENTICACAO.md).
- Com assinatura ad-hoc, o macOS pode pedir acesso ao Keychain depois de recompilar.
- Assinatura em tempo real (eventos do SmartThings) não é usada: exigiria um servidor. O estado é lido por
  consulta periódica.

## Licença

[MIT](LICENSE).

## Créditos

Comportamento e mapeamento de comandos estudados no projeto
[samsung-windfree-tray-app](https://github.com/c0dag/samsung-windfree-tray-app). Como ele não declara licença,
nenhum código ou asset foi copiado: o código e o ícone deste repositório são próprios.

Samsung, WindFree e SmartThings são marcas da Samsung Electronics. Este projeto é independente e não tem
relação com a Samsung.
