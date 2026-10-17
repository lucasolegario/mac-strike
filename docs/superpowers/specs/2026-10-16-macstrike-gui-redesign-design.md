# MacStrike — Redesenho da GUI (estilo CleanMyMac)

**Data:** 2026-10-16
**Status:** aprovado (design) + revisado contra o código (2026-10-16)
**Alvo:** target SwiftUI `macstrike-gui` + novos tipos em `BottleEngine`

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
  "+ adicionar jogo"). Clicar num card abre o detalhe daquele jogo.
- **Setup:** assistente **passo-a-passo** (wizard dedicado), não checklist
  inline.
- **Pele:** "Aurora" — acento gradiente azul→roxo sobre navy escuro.
- **Navegação:** rail fino à esquerda com **Jogos · Ajustes · Pro**.

## Restrições herdadas do projeto

- **macOS 13 é o piso** (`Package.swift`: `platforms: [.macOS(.v13)]`). Proíbe
  `@Observable`/Observation, `ContentUnavailableView` e outras APIs macOS 14+.
  Usar `ObservableObject` + `@Published`, como o código atual.
- Swift tools 6.0; tipos cruzando concorrência precisam ser `Sendable`.
- SwiftUI puro; tem que continuar compilando com `swift build` (Command Line
  Tools, sem Xcode) — caminho de distribuição $0.
- Testes vão para `Sources/selftest/main.swift` com o helper `check(_:_:)`
  existente — **não há XCTest** no Command Line Tools.
- Stack 100% Wine aberto (GPTK/Gcenx). Nada de CrossOver no código.
- Não adicionar dependências externas novas.

## Arquitetura (Abordagem 1 — aprovada)

A lógica que decide *o que* um jogo precisa é pura e vai para o `BottleEngine`
(coberta por `selftest`); a parte de *pintar e animar* fica no SwiftUI.

### Fronteiras de módulo

- **`BottleEngine`:** `Game`, `GameCatalog`, `SetupStep`, `SetupState`,
  `SetupPlan` (puros, zero I/O, zero SwiftUI) + `WineInstaller` e
  `GameDetection` (com I/O, espelhando `DXMTInstaller`).
- **`MacStrikeGUI` (reescrito):** SwiftUI + `SetupRunner` async que executa os
  steps chamando as APIs do engine. O atual `BottleStore` é substituído por
  **`AppModel`** (nome único e definitivo).
- **CLI (`Sources/macstrike`):** intacta nesta entrega.

## Correções da revisão do spec (2026-10-16)

A revisão contra o código encontrou sete problemas; as resoluções estão
incorporadas abaixo:

1. **`.ensureWine` não tinha implementação.** Não existia API Swift para
   instalar Wine (só `scripts/setup-wine.sh`). **Resolução:** criar
   `WineInstaller` no engine, espelhando `DXMTInstaller` (baixa o release do
   Gcenx do GitHub, extrai, instala em `<support>/wine`). O wizard fica
   autônomo.
2. **Faltava criar o bottle.** **Resolução:** `SetupStep.createBottle` entra
   como primeiro passo, usando `BottleManager.createBottle`.
3. **O bottle CS2 existente seria ignorado.** **Resolução:** o bottle de um
   jogo é resolvido por **nome** (`Game.bottleName`, "CS2" para o CS2), em
   `<support>/Bottles/<bottleName>`. Se já existir, é adotado — o passo
   `createBottle` fica satisfeito e o setup aparece já adiantado.
4. **"Jogo baixado?" não era detectável.** **Resolução:** `GameDetection`
   novo, que checa `drive_c/Program Files (x86)/Steam/steamapps/common/<dir>`.
   O passo `installGame` abre a Steam na página do jogo, instrui o usuário a
   instalar pela Steam, e faz **polling** até detectar — sem barra de progresso
   falsa (o app não tem acesso ao progresso da Steam).
5. **`Game.accent` quebraria a pureza do engine.** **Resolução:** `Game` guarda
   `accentFrom: String` e `accentTo: String` (hex do gradiente, dois campos
   separados — tupla não sintetiza `Equatable`); a GUI resolve para `Color`.
6. **`SetupPlan` misturava responsabilidades.** **Resolução:** `SetupPlan` é
   **puro** (ordem + decisão). Todo estado de execução (running/failed/
   progresso/log) vive no `SetupRunner`, na GUI.
7. **Ambiguidades.** Nome único `AppModel`; janela usa
   `.windowStyle(.hiddenTitleBar)` do SwiftUI, sem gambiarra de `NSWindow`.

## Modelo puro (em `BottleEngine`)

```swift
struct Game: Identifiable, Sendable, Equatable {
    let id: String              // slug: "cs2", "gtav"
    let name: String            // "Counter-Strike 2"
    let bottleName: String      // "CS2" — adota bottles existentes
    let steamAppID: Int?        // 730; nil para jogo avulso (.exe)
    let backend: GraphicsBackend
    let accentFrom: String      // hex inicial do gradiente do card
    let accentTo: String        // hex final
    let supported: Bool         // GTA V entra como false ("em breve")
}

enum GameCatalog {              // .cs2, .gtaV; .builtins: [Game]
}

enum SetupStep: Equatable, Sendable {
    case createBottle, installWine, fetchDXMT, installGraphics,
         installSteam, installGame(appID: Int), ready
}

struct SetupState: Sendable {   // o que já está satisfeito (só bools)
    var bottleExists, wineReady, dxmtDownloaded,
        graphicsInstalled, steamInstalled, gameInstalled: Bool
}

struct SetupPlan {              // PURO
    static func steps(for game: Game) -> [SetupStep]
    static func next(for game: Game, given state: SetupState) -> SetupStep
    static func progress(for game: Game, given state: SetupState) -> Double
}
```

`next(for:given:)` retorna o primeiro step não satisfeito, ou `.ready`.

## Estrutura da GUI (Aurora)

- **Rail à esquerda** (fino, ícones): Jogos · Ajustes · Pro.
- **Jogos:** grade de cards. Card = gradiente + nome + badge de estado
  (Pronto / Preparar / Em breve). Clicar → detalhe. Último card é
  **"+ Adicionar jogo"** → abre `NSOpenPanel` de `.exe` e cria um jogo avulso
  na biblioteca (usa o `GameLauncher` existente).
- **Detalhe do jogo:** hero com gradiente+nome; botão **▶ Jogar** aceso só se
  `.ready`; caso contrário **Configurar** → abre o wizard.
- **Wizard (sheet):** passo N/total, anel de progresso, texto do passo atual,
  Continuar/Cancelar, **Tentar de novo** em falha.
- **Ajustes (modo avançado):** backend gráfico, perfil balanced/turbo (**Pro**),
  abrir pasta do bottle, rodar `.exe` avulso, log.
- **Pro:** licença/trial (reaproveita a lógica de `LicenseSheet`, repaginada).

### Gating Pro

Igual ao de hoje: **só o perfil `turbo` é Pro**. Todo o resto é livre.

## Fluxo de dados / runner

`SetupRunner` — `@MainActor`, `ObservableObject`. Recebe `Game` + `SetupState`,
executa cada step numa task em background e publica `currentStep`, `progress`,
`log`, `failure`. Falha para o wizard no passo com mensagem legível +
**Tentar de novo**. O passo `installGame` abre a Steam e faz polling de
`GameDetection` até o jogo aparecer. Jogar é `SteamProvisioner.play` (jogo
Steam) ou `GameLauncher.launch` (jogo avulso).

## Tema

`Theme.swift` com tokens: `bg`, `card`, `accentGradient` (azul→roxo),
`textPrimary/Secondary`, raios, sombras. `.windowStyle(.hiddenTitleBar)` e
`.preferredColorScheme(.dark)`.

## Erros e testes

- **selftest (novos checks, além dos 67 atuais):** catálogo contém CS2 com
  appID 730 e bottleName "CS2"; `steps(for:)` produz a ordem canônica;
  `next(for:given:)` pula passos satisfeitos; retorna `.ready` com tudo
  satisfeito; `progress` vai de 0 a 1; `WineInstaller.pickAsset` escolhe o
  `.tar.xz` do canal certo; `GameDetection.steamAppDir` monta o caminho certo.
- **Erros:** cada step reporta falha legível ("Wine ausente", "download
  falhou"); a UI nunca quebra; log acessível no wizard e em Ajustes.

## Escopo da 1ª entrega

Biblioteca + detalhe + wizard + Ajustes + Pro, com **CS2** real no catálogo,
GTA V como card "em breve" e "+ Adicionar jogo" funcional para `.exe`. Reskin
Aurora completo. `WineInstaller` + `GameDetection` novos no engine. Sem tocar
na CLI. Arte dos jogos = gradiente + nome (sem baixar imagens de terceiros).

## Fora de escopo

- GTA V funcional (só placeholder não-suportado).
- Empacotamento/notarização .app (fluxo já existe em `scripts/build-app.sh`).
- Download de artes/box-art de terceiros.
- Mudanças na CLI.
- Progresso real de download da Steam (o app não tem acesso).
