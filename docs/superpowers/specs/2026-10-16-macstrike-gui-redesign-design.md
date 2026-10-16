# MacStrike — Redesenho da GUI (estilo CleanMyMac)

**Data:** 2026-10-16
**Status:** aprovado (design) — próximo passo: plano de implementação
**Alvo:** target SwiftUI `macstrike-gui` + novos tipos puros em `BottleEngine`

## Objetivo

Substituir a GUI atual (um `NavigationSplitView` de fábrica com `Form`
agrupado, em `Sources/MacStrikeGUI/ContentView.swift`) por uma interface
moderna e bonita inspirada no CleanMyMac da MacPaw: escura, com vidro, cantos
arredondados e um fluxo **centrado em jogos** em vez de centrado em *bottles*.

A complexidade técnica (Wine, DXMT, Steam, bottles) deixa de ser exposta como
objetos a gerenciar e passa a ser resolvida por baixo, guiando o usuário.

## Decisões de UX (travadas no brainstorming)

- **Filosofia:** "hero jogar" — experiência mágica focada em jogar, não em
  gerenciar bottles.
- **Primeira tela:** biblioteca em grade de cards de jogos (CS2, GTA V,
  "+ adicionar"). Clicar num card abre o detalhe daquele jogo.
- **Setup:** assistente **passo-a-passo** (wizard dedicado), não checklist
  inline.
- **Pele:** "Aurora" — acento gradiente azul→roxo sobre navy escuro.
- **Navegação:** rail fino à esquerda com **Jogos · Ajustes · Pro**.

## Restrições herdadas do projeto

- SwiftUI puro; tem que continuar compilando com `swift build` (Command Line
  Tools, sem Xcode) — caminho de distribuição $0.
- Stack 100% Wine aberto (GPTK/Gcenx). Nada de CrossOver no código.
- Não adicionar dependências externas novas.

## Arquitetura (Abordagem 1 — aprovada)

A lógica que decide *o que* um jogo precisa é pura e vai para o `BottleEngine`
(coberta por `selftest`); a parte de *pintar e animar* fica no SwiftUI.

### Fronteiras de módulo

- **`BottleEngine` (novos tipos, puros e testáveis):** `Game`, `GameCatalog`,
  `SetupStep`, `SetupPlan`. Zero I/O, zero SwiftUI.
- **`MacStrikeGUI` (reescrito):** SwiftUI + um `SetupRunner` async que executa
  os steps chamando as APIs existentes (`BottleManager`, `DXMTInstaller`,
  `SteamProvisioner`, `GameLauncher`, `BottleEngine`). O atual `BottleStore`
  vira um `AppModel` / `GameLibraryStore`.
- **CLI (`Sources/macstrike`) e orquestradores de execução:** intactos.

## Modelo puro (em `BottleEngine`)

```swift
struct Game: Identifiable, Sendable    // id, nome, slug, accent (card), steamAppID?, backend recomendado
enum  GameCatalog                      // .cs2 (real), .gtaV (placeholder "em breve"); .builtins
enum  SetupStep                        // .ensureWine, .fetchDXMT, .installGraphics,
                                       //   .installSteam, .installGame(appID), .ready
struct SetupPlan                       // steps ordenados p/ um Game + estado de cada
                                       //   (pending/running/done/failed) + progresso 0–1
```

- `SetupPlan.steps(for: Game)` → ordem canônica dos passos daquele jogo.
- `SetupPlan.next(given:)` → **função pura**: dado o estado observado do bottle
  (Wine presente? DXMT baixado? graphics DLLs instaladas? Steam instalada? jogo
  baixado?), retorna o próximo `SetupStep` ou `.ready`. Pula passos já
  satisfeitos.
- Um tipo de entrada `SetupState` (structs de bools) descreve o que já está
  satisfeito, para `next(given:)` permanecer puro e testável.

## Estrutura da GUI (Aurora)

- **Rail à esquerda** (fino, ícones): Jogos · Ajustes · Pro.
- **Jogos:** grade de cards. Card = arte (gradiente+nome por ora) + badge de
  estado (Pronto / Preparar / Baixando). Clicar → detalhe.
- **Detalhe do jogo:** hero com a arte; botão **▶ Jogar** aceso só se `ready`;
  caso contrário vira **Configurar** → abre o wizard.
- **Wizard (sheet):** passo N/total, anel de progresso, texto do passo atual,
  Continuar/Cancelar. Dirigido pelo `SetupPlan` + `SetupRunner`.
- **Ajustes (modo avançado):** backend gráfico, perfil balanced/turbo, abrir
  pasta do bottle, rodar `.exe` avulso (o que o `Form` atual faz).
- **Pro:** licença/trial (reaproveita a lógica do `LicenseSheet`, repaginada).

## Fluxo de dados / runner

`SetupRunner` — `@MainActor`, observável. Recebe o `SetupPlan`, executa cada
step numa task em background e publica `currentStep`, `progress`, `log`. Uma
falha para o wizard no passo com mensagem legível + **Tentar de novo**. Jogar é
`GameLauncher.launch` com o ambiente do bottle (já montado por
`LaunchEnvironment`).

## Tema

`Theme.swift` com tokens: `bg`, `card`, `accentGradient` (azul→roxo),
`textPrimary/Secondary`, raios, sombras. Janela com título oculto / toolbar
unificada (via `AppDelegate`/`NSWindow`); `.preferredColorScheme(.dark)`.

## Erros e testes

- **selftest (novos checks, além dos 67 atuais):** catálogo contém CS2;
  `SetupPlan.steps(for:)` produz a ordem esperada; `next(given:)` pula passos
  satisfeitos; jogo vira `.ready` quando tudo satisfeito.
- **Erros:** cada step reporta falha legível ("Wine ausente", "download
  falhou"); a UI nunca quebra; log acessível no wizard/Ajustes.

## Escopo da 1ª entrega

Biblioteca + detalhe + wizard + Ajustes + Pro, com **CS2** real no catálogo e
GTA V como card "em breve". Reskin Aurora completo. Sem tocar em CLI nem no
motor de execução. Arte dos jogos = gradiente + nome (sem baixar imagens de
terceiros).

## Fora de escopo

- GTA V funcional (só placeholder).
- Empacotamento/notarização .app (fluxo já existe em `scripts/build-app.sh`).
- Download de artes/box-art de terceiros.
- Mudanças na CLI.
