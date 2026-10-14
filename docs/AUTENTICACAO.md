# Autenticação no SmartThings

Este documento resume o que a documentação oficial e o fórum de desenvolvedores do SmartThings dizem
sobre acesso contínuo à API, e como o WindFree aplica isso. Pesquisa feita em outubro de 2026.

## O que a plataforma oferece

| Caminho | Validade | Uso no WindFree |
|---|---|---|
| **Token pessoal (PAT)** | 24 h para tokens criados a partir de 30/12/2024 | Somente para validar a integração. Não é autenticação definitiva. |
| **OAuth 2.0 `authorization_code`** (app "API Access") | Access token de 24 h; refresh token expira após **29 dias sem uso** | Caminho recomendado para uso contínuo. |
| `client_credentials` | Não suportado pelo SmartThings | — |
| Login do SmartThings CLI | Pertence ao CLI | **Não reutilizado.** O app não lê nem copia credenciais do CLI. |

Fontes:

- [Authorization and Permissions](https://developer.smartthings.com/docs/getting-started/authorization-and-permissions) — PAT válido por 24 h; recomenda integração OAuth para acesso contínuo.
- [OAuth Integrations](https://developer.smartthings.com/docs/service-integrations/oauth) — endpoints de autorização e de token; troca de código com `Authorization: Basic base64(clientId:clientSecret)`.
- [Fórum: 403 no authorize de app API_ONLY](https://community.smartthings.com/t/403-forbidden-when-using-oauth-authorize-endpoint-for-api-only-smartapp/309689) (jun/2026) — equipe do SmartThings confirma: app API_ONLY com OAuth e renovação agendada é a opção de longo prazo; access token 24 h; refresh token expira após 29 dias sem uso; limite padrão de 500 instalações; há relatos de problemas com `http://localhost` como endereço de retorno (confirmado aqui: é um bloqueio do servidor a `localhost`/`127.0.0.1` no pedido de autorização).

Pontos importantes:

- A troca do código e a renovação exigem o **Client Secret** (cliente confidencial). Não há PKCE documentado.
  Por isso o segredo **não** é embutido no aplicativo: cada usuário registra o próprio app e informa o segredo,
  que fica só no Keychain do Mac.
- O token de acesso é enviado como `Authorization: Bearer …` em todas as chamadas da API.

## Configuração do OAuth (uma vez, manual)

1. **Registrar um app "API Access" (OAuth-In)** na sua conta Samsung. O caminho atual é o SmartThings CLI,
   usado apenas como ferramenta de registro (o WindFree não depende dele):

   ```sh
   npx @smartthings/cli@2.1.2 apps:create
   ```

   Escolha o tipo OAuth-In, informe um nome, os escopos `r:devices:*`, `x:devices:*` e `r:locations:*` e o endereço de retorno.
   O comando mostra o **Client ID** e o **Client Secret** — o segredo aparece uma única vez; guarde-o num
   gerenciador de senhas. Nunca coloque esses valores no repositório.

2. **Endereço de retorno: `https://api.smartthings.com/installedapp`.** O que foi verificado em 11/10/2026
   (Mac deste projeto, app OAuth-In criado com o CLI 2.1.2):
   - o cadastro exige `https`, exceto para `localhost` ("https is required except for localhost"), o que
     exclui loopback IPv6 (`http://[::1]`) e esquemas próprios (`windfree://`);
   - o servidor de autorização responde **403** a qualquer pedido com `localhost` ou `127.0.0.1` no
     `redirect_uri`, antes de verificar o app (acontece até com um Client ID inexistente);
   - sem `redirect_uri`, o fluxo termina em `https://api.smartthings.com/installedapp?code=…&state=…`, mas a
     troca do código é recusada (HTTP 400), porque o endereço precisa ser idêntico nas duas etapas.

   Por isso o WindFree usa a própria página `installedapp` do SmartThings como endereço de retorno, enviado
   explicitamente na autorização e na troca. Ela responde "404 Not Found", mas a barra do navegador mostra o
   endereço com o código: copie e cole no WindFree. O código não passa por nenhum site de terceiros, é de uso
   único e não serve sem o segredo. Não há retorno automático para o Mac.

   Para conferir ou trocar os endereços de um app já registrado:

   ```sh
   npx @smartthings/cli@2.1.2 apps:oauth:update
   ```

   Use a versão 2.x do CLI: a 1.10.x, que o `npx` pode reaproveitar do cache, falha com
   "Invalid base URL undefined".

3. **No WindFree:** Ajustes → Conta → seção OAuth. Informe Client ID, Client Secret e o mesmo endereço de
   retorno e clique em "Autorizar no navegador". Entre na conta Samsung, escolha o local e autorize. Copie o
   endereço da página 404 em que o navegador parar, cole no campo do WindFree e clique em "Concluir". Se der
   erro, o WindFree mostra o motivo informado pelo SmartThings; autorize de novo (o código é de uso único).

4. O app troca o código por tokens, confere o acesso listando os aparelhos e só então grava a credencial no
   Keychain. A partir daí renova o token sozinho (10 min antes de expirar ou após um 401).

Se o app ficar mais de 29 dias sem renovar (por exemplo, sem ser aberto), a autorização expira e o painel
mostra "Sessão expirada".

## Cômodos (permissão `r:locations:*`)

A lista de aparelhos traz só o identificador do cômodo; o nome vem de `GET /locations/{id}/rooms`, que exige
`r:locations:*` ("See all locations"), conforme a especificação OpenAPI pública do SmartThings. Com ela, os apps
mostram "Ar condicionado · Quarto"; sem ela, funcionam igual e diferenciam nomes repetidos com número.

Para liberar numa autorização existente: inclua `r:locations:*` no app OAuth
(`npx @smartthings/cli@2.1.2 apps:oauth:update`) e use **Ajustes › Conta › Autorizar de novo** (reaproveita o
Client ID e o segredo guardados). No relógio: **iPhone › Ajustes › Apple Watch › Autorizar o relógio**. Essa
permissão também dá leitura de dados das casas (nomes e configurações dos locais); o app só lê os cômodos.

## Token pessoal (validação)

1. Crie em <https://account.smartthings.com/tokens> com as permissões de listar, ver e controlar aparelhos.
2. Ajustes → Conta → Avançado → Token pessoal. Ajuste a data de expiração (padrão: 24 h a partir de agora) e clique em
   "Validar e salvar". O token só é gravado se a API aceitá-lo.
3. Quando o SmartThings recusar o token (401), o painel mostra "Sessão expirada".

## Armazenamento

| Dado | Onde |
|---|---|
| Token pessoal, Client ID/Secret, access/refresh token | Keychain do Mac (`io.github.douglasrubims.WindFree`), item não sincronizado, acessível após o primeiro desbloqueio, só neste aparelho |
| Aparelho escolhido, temperatura exibida na barra, modo simulado | UserDefaults (não sensível) |
| Respostas da API | Não são gravadas; a sessão HTTP não usa cache nem cookies |

Com assinatura ad-hoc ("Sign to Run Locally"), cada nova compilação muda a assinatura e o macOS pode pedir
permissão para o app ler o item do Keychain. Configurar um Team no Xcode evita esses pedidos.

## Implicações para iOS, iPadOS e watchOS

Veja também [PLATAFORMAS.md](PLATAFORMAS.md).

- **Segredo do cliente:** um app distribuído (App Store/TestFlight) não pode carregar o segredo. As opções são
  (a) cada usuário registrar o próprio app OAuth, como no macOS (viável para uso pessoal, ruim para terceiros),
  ou (b) um pequeno servidor de troca de tokens que guarda o segredo, faz a troca do código e as renovações, e
  entrega ao app apenas tokens de acesso. Para distribuir a outras pessoas, (b) é o caminho correto.
- **Login no iPhone/iPad:** `ASWebAuthenticationSession` com retorno HTTPS para o servidor (ou esquema próprio,
  se o SmartThings aceitar). Como no macOS, o cadastro exige `https`; um retorno automático ao app exige um endereço `https` próprio (por exemplo, um Universal Link ou o servidor de troca).
- **Apple Watch (implementado):** não há login prático no relógio. O iPhone faz uma autorização OAuth
  separada (mesmo app OAuth, copiar e colar o endereço) e a envia ao relógio por WatchConnectivity, com o app
  do relógio aberto; o relógio grava no próprio Keychain e renova sozinho, sem depender do iPhone. Isso inclui
  o Client Secret, que passa a existir no Keychain do relógio também. Para distribuição pública, o caminho
  seria o servidor de troca de tokens.
- **Nada é compartilhado automaticamente.** O Keychain de cada aparelho é separado; os itens do WindFree são
  gravados sem sincronização pelo iCloud. Grupos de acesso compartilham itens apenas entre apps do mesmo time
  no mesmo aparelho.
- **Renovação concorrente:** a documentação não deixa claro se o refresh token muda a cada renovação no app
  API Access. Se mudar, dois aparelhos renovando a mesma autorização se invalidam. Por segurança, apenas um
  dono (servidor ou iPhone) deve renovar e distribuir tokens de acesso, ou cada aparelho deve ter a própria
  autorização.
