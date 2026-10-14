# Estado da validação

Legenda: ✅ feito · ⬜ não feito · — não se aplica

| Item | Implementado | Compilado | Testado (automático/simulação) | Validado no aparelho real |
|---|---|---|---|---|
| Listagem de aparelhos e filtro de ar-condicionado | ✅ | ✅ | ✅ testes do cliente | ✅ aparelho encontrado na conta real |
| Leitura de status e capacidades | ✅ | ✅ | ✅ JSON fictício + simulação | ✅ diagnóstico do aparelho real lido e interpretado (11/10/2026) |
| Saúde (online/offline) | ✅ | ✅ | ✅ simulação | ⬜ |
| Token pessoal (validar, guardar no Keychain, 401 → sessão expirada) | ✅ | ✅ | ✅ testes; Keychain verificado no app em sandbox | ✅ validado e salvo na conta real |
| OAuth (URL, `state`, troca do código, renovação, persistência) | ✅ | ✅ | ✅ testes com transporte falso | ✅ autorização e troca do código na conta real (11/10/2026); ⬜ renovação automática (após 24 h) |
| Ligar/desligar | ✅ | ✅ | ✅ | ✅ uso no Mac, iPhone e relógio |
| Temperatura desejada / ambiente | ✅ | ✅ | ✅ | ✅ uso no Mac, iPhone e relógio |
| Modo, vento | ✅ | ✅ | ✅ | ⬜ |
| Nome do cômodo (`r:locations:*`) e nomes repetidos numerados | ✅ | ✅ | ✅ testes + simulação | ⬜ |
| Direção: `fanOscillationMode`, ou pás verticais/laterais (oscilar ou posição exata) e alcance lateral via `samsungce.airConditionerAirFlowDirection` | ✅ | ✅ | ✅ simulação + perfil real | ✅ pás (controles deslizantes) no aparelho real; ⬜ alcance lateral |
| Modo especial (silencioso, inteligente, rápido, conforto seco…) | ✅ | ✅ | ✅ simulação | ⬜ |
| WindFree e sono (atributo compartilhado) | ✅ | ✅ | ✅ | ⬜ |
| Umidade | ✅ | ✅ | ✅ | ⬜ |
| Display (`setLightingLevel`; `execute` invertido como alternativa) | ✅ | ✅ | ✅ simulação + perfil real | ⬜ **precisa confirmar** |
| Bipe (`samsungce.airConditionerBeep` ou volume), limpeza automática, alerta e reset do filtro | ✅ | ✅ | ✅ simulação | ⬜ |
| Consumo (potência média da janela quando `power` vem 0) | ✅ | ✅ | ✅ perfil real | ⬜ |
| Agrupamento de cliques (um comando) | ✅ | ✅ | ✅ | ⬜ |
| Pedido × confirmado × não confirmado | ✅ | ✅ | ✅ | ⬜ |
| Retenção com o ar desligado e envio ao ligar | ✅ | ✅ | ✅ | ⬜ **comportamento do aparelho a confirmar** |
| Sem consultas sobrepostas | ✅ | ✅ | ✅ testes + log | — |
| Espera progressiva e limite da API (429) | ✅ | ✅ | ✅ testes | ⬜ |
| Consulta mais frequente com painel aberto | ✅ | ✅ | ✅ teste do agendador; com o painel fechado, medido 1 leitura a cada ~2 min | — |
| Recuperação após suspensão | ✅ | ✅ | ✅ teste do agendador (retoma após 3 s); ⬜ suspensão real do Mac não testada | — |
| Painel: claro/escuro, estados de carregamento, offline, sessão expirada, não confirmado | ✅ | ✅ | ✅ capturas geradas com dados simulados | — |
| Fechar com Esc / clique fora | ✅ | ✅ | ⬜ (não verificado separadamente) | — |
| Temperatura na barra de menus | ✅ | ✅ | ⬜ (verificação manual) | — |
| Abertura pelo Finder (`dist/WindFree.app`) | ✅ | ✅ | ✅ aberto via LaunchServices (`open`), processo filho do launchd; ⬜ duplo clique no Finder | — |
| App iOS/iPadOS | ✅ | ✅ | ✅ simulador iPhone 17 e iPad Pro 13" com dados simulados (capturas) | ✅ iPhone 15 Pro Max: login OAuth e controle do aparelho (11/10/2026) |
| App watchOS (independente) | ✅ | ✅ | ✅ simulador Apple Watch Series 12 com dados simulados (capturas) | ✅ Apple Watch Series 10: conexão e controle (12/10/2026); ⬜ recursos de "mais" adicionados depois |
| Autorização do relógio pelo iPhone (WatchConnectivity) | ✅ | ✅ | ✅ formato das mensagens testado | ✅ iPhone 15 Pro Max → Apple Watch Series 10 |

## Perfil do aparelho real (diagnóstico de 11/10/2026)

WindFree 2026 com aquecimento. Diferenças em relação ao aparelho do projeto de referência, já tratadas:

- modos `auto`, `cool`, `dry`, `fan`, `heat` (a referência usava `wind`);
- `fanOscillationMode` desativada; direção por `samsungce.airConditionerAirFlowDirection`: pás verticais
  (oscilar ou posições 1–6), laterais (oscilar ou 1–5) e alcance lateral (toda a largura, esquerda, direita).
  Comandos e tipos dos argumentos conferidos na definição publicada da capacidade;
- iluminação ativa, com `setLightingLevel` (na referência ela vinha desativada);
- bipe por `samsungce.airConditionerBeep`;
- modos especiais: `off`, `sleep`, `quiet`, `smart`, `speed`, `windFree`, `windFreeSleep`, `dryComfort`;
- potência instantânea zerada; o app mostra a média da última janela do relatório (`deltaEnergy`);
- faixa 16–30 °C declarada pelo aparelho.

Nomes de comandos das capacidades Samsung conferidos no catálogo da biblioteca pysmartthings (usada pela
integração SmartThings do Home Assistant); ainda não confirmados no aparelho.

## Medições (dados simulados, painel fechado, build Debug)

- Leituras de status: 20:58:57 → 21:01:05 → 21:03:13 (intervalo de ~2 min; o macOS agrupa temporizadores),
  nenhuma sobreposta.
- CPU em repouso: 0,0 %. Memória residente: ~88 MB.
- Keychain: gravar, ler, atualizar e apagar um item fictício dentro do app em sandbox, com assinatura ad-hoc,
  sem erros (`-keychainSelfTest YES`, só em Debug).

## Testes automáticos

```bash
swift test --package-path Packages/WindFreeKit
```

73 testes em 11 grupos: interpretação de estado e capacidades (incluindo capacidades desativadas, faixas de
temperatura e valores inesperados), WindFree/sono, montagem de comandos e ordem de envio, fila e agrupamento,
retenção com o ar desligado, confirmação e não confirmação, comandos recusados, consultas sobrepostas, sessão
expirada, limite da API, falhas de rede, aparelho offline, reset do filtro, política e agendamento de consultas (incluindo retomada após suspensão e parada com sessão expirada),
cliente HTTP (paginação, 401 com renovação, 429, falhas de comando), OAuth (URL, `state`, Basic auth,
renovação única para chamadas simultâneas, `invalid_grant`) e remoção de dados pessoais do diagnóstico.

## Capturas com dados simulados (somente Debug)

```bash
open build/DerivedData/Build/Products/Debug/WindFree.app --args -simulated YES -renderSnapshots YES
```

Gera PNGs das telas reais (claro e escuro) em
`~/Library/Containers/io.github.douglasrubims.WindFree/Data/Library/Caches/Snapshots` e encerra.

## Checklist no aparelho real

Use primeiro um token pessoal (24 h). Faça cada passo e observe o painel e o aparelho.

1. **Descoberta:** o aparelho aparece com o nome do app SmartThings.
2. **Capacidades:** Ajustes › Exportar diagnóstico. Confira modos, velocidades, direções, modos opcionais e faixa
   de temperatura. Se possível, envie o arquivo (já sem identificadores) para ajustar o mapeamento.
3. **Leitura:** temperatura ambiente, umidade e estado batem com o app SmartThings.
4. **Ligar/desligar** pelo painel.
5. **Temperatura:** clique várias vezes em + rapidamente; deve sair um único comando e o valor final aparecer
   confirmado.
6. **Modo, vento, direção.**
7. **WindFree e sono** (observe se o aparelho aceita fora do modo resfriar).
8. **Desligado:** mude temperatura e vento com o ar desligado — devem aparecer "Aplicado ao ligar". Ligue pelo
   painel e depois repita ligando pelo controle remoto. Os ajustes devem ser aplicados nos dois casos.
   Confira também se o aparelho realmente ignora esses ajustes desligado (comportamento da referência).
9. **Display:** ligue e desligue a luz. Se o efeito for invertido ou nulo, informe.
10. **Bipe, limpeza automática, alerta do filtro, consumo.**
11. **Offline:** desligue o disjuntor ou o Wi-Fi do aparelho; o painel deve mostrar "Aparelho offline".
12. **Sessão expirada:** após 24 h o token pessoal deve levar a "Sessão expirada".
13. **Suspensão:** suspenda o Mac por alguns minutos; ao acordar o estado deve atualizar sozinho.
