# MacStrike GUI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace MacStrike's stock SwiftUI bottle-manager GUI with a dark, modern, game-centric interface inspired by MacPaw's CleanMyMac — a game library, a per-game hero screen, and a step-by-step setup wizard that provisions Wine, DXMT, Steam and the game itself.

**Architecture:** Pure decision logic (`Game`, `GameCatalog`, `SetupStep`, `SetupState`, `SetupPlan`) plus two new I/O helpers (`WineInstaller`, `GameDetection`) go into the `BottleEngine` library, where the existing `selftest` runner covers them. The SwiftUI target is rewritten: an `AppModel` (replacing `BottleStore`) owns app state, a `SetupRunner` executes plan steps off the main thread, and views render the "Aurora" theme. The CLI target is untouched.

**Tech Stack:** Swift 6 tools, SwiftUI (macOS 13 floor), Foundation, `Process`/`URLSession` for I/O, `/usr/bin/tar` for extraction. No external dependencies.

**Spec:** `docs/superpowers/specs/2026-10-16-macstrike-gui-redesign-design.md`

## Global Constraints

- **macOS 13 is the floor** (`Package.swift`: `platforms: [.macOS(.v13)]`). Do NOT use `@Observable`/Observation, `ContentUnavailableView`, `.scrollTargetBehavior`, or any macOS 14+ API. Use `ObservableObject` + `@Published` + `@EnvironmentObject`.
- **No XCTest.** Command Line Tools has no test runtime. All tests are `check(_:_:)` calls appended to `Sources/selftest/main.swift`, run with `swift run selftest`.
- **Must keep building with `swift build`** (Command Line Tools, no Xcode).
- **No new external dependencies.**
- `BottleEngine` must not `import SwiftUI` or `import AppKit`.
- Stack is 100% open Wine (GPTK/Gcenx). No CrossOver references anywhere in code, comments, or copy.
- Pro gating: **only the `turbo` performance profile is Pro-gated.** Everything else is free.
- User-facing copy is **Portuguese (pt-BR)**, matching the existing GUI.
- Commit with: `git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" commit -m "..."`
- After every task: `swift build` must succeed and `swift run selftest` must report **all checks passed** (67 pre-existing checks must never regress).

## File Structure

**Created in `Sources/BottleEngine/`:**
- `Game.swift` — the `Game` value type and `GameCatalog` of built-ins.
- `SetupPlan.swift` — `SetupStep`, `SetupState`, `SetupPlan` (pure ordering + decision).
- `GameDetection.swift` — detects whether a Steam game is installed in a bottle.
- `WineInstaller.swift` — downloads and installs the Gcenx Wine build.

**Created in `Sources/MacStrikeGUI/`:**
- `Theme.swift` — Aurora design tokens and small shared view modifiers.
- `AppModel.swift` — app state, bottle/game resolution, `SetupState` observation, licensing.
- `SetupRunner.swift` — executes a `SetupPlan` step by step with progress and log.
- `SetupStepPresentation.swift` — pt-BR titles/subtitles for `SetupStep` (UI copy stays out of the engine).
- `RootView.swift` — the left rail + section switching.
- `LibraryView.swift` — game grid, game card, "+ Adicionar jogo".
- `GameDetailView.swift` — per-game hero with Play/Configure.
- `SetupWizardView.swift` — the step-by-step sheet.
- `SettingsView.swift` — advanced settings (backend, profile, bottle folder, run .exe, log).
- `ProView.swift` — license/trial screen.

**Modified:**
- `Sources/MacStrikeGUI/MacStrikeApp.swift` — window chrome, dark scheme, `AppModel`.
- `Sources/selftest/main.swift` — new checks appended.

**Deleted:**
- `Sources/MacStrikeGUI/ContentView.swift` — replaced by the new view files.
- `Sources/MacStrikeGUI/BottleStore.swift` — replaced by `AppModel.swift`.

---

### Task 1: `Game` and `GameCatalog`

The pure catalog of games. `bottleName` is what makes the user's **existing** `Bottles/CS2` get adopted instead of a fresh empty bottle being created.

**Files:**
- Create: `Sources/BottleEngine/Game.swift`
- Test: `Sources/selftest/main.swift` (append)

**Interfaces:**
- Consumes: `GraphicsBackend` (existing), `SteamApp` (existing, `Sources/BottleEngine/SteamProvisioner.swift:136`).
- Produces: `Game` with members `id`, `name`, `bottleName`, `steamAppID`, `backend`, `accentFrom`, `accentTo`, `supported`, and initializer `Game(id:name:bottleName:steamAppID:backend:accentFrom:accentTo:supported:)`. `GameCatalog.cs2`, `GameCatalog.gtaV`, `GameCatalog.builtins`, `GameCatalog.game(id:)`. Also `Game.custom(name:exePath:)` returning a `Game` with `steamAppID == nil` and `id` prefixed `custom:`.

- [ ] **Step 1: Write the failing test**

Append to the end of `Sources/selftest/main.swift`, immediately **before** the final `print("")` / failure-summary block:

```swift
print("Game catalog:")
do {
    let cs2 = GameCatalog.cs2
    check(cs2.id == "cs2", "cs2 slug")
    check(cs2.name == "Counter-Strike 2", "cs2 display name")
    check(cs2.bottleName == "CS2", "cs2 adopts the existing CS2 bottle name")
    check(cs2.steamAppID == SteamApp.cs2, "cs2 maps to Steam app 730")
    check(cs2.backend == .d3dmetal, "cs2 defaults to d3dmetal")
    check(cs2.supported, "cs2 is supported")
    check(!GameCatalog.gtaV.supported, "GTA V ships as an unsupported placeholder")
    check(GameCatalog.builtins.count == 2, "two built-in games")
    check(GameCatalog.game(id: "cs2") == cs2, "lookup by slug finds cs2")
    check(GameCatalog.game(id: "nope") == nil, "unknown slug returns nil")

    let custom = Game.custom(name: "Meu jogo", exePath: "/tmp/x/game.exe")
    check(custom.steamAppID == nil, "custom game has no Steam app id")
    check(custom.id.hasPrefix("custom:"), "custom game id is namespaced")
    check(custom.exePath == "/tmp/x/game.exe", "custom game remembers its exe")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run selftest`
Expected: FAIL to **compile** — `cannot find 'GameCatalog' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/BottleEngine/Game.swift`:

```swift
import Foundation

/// A game MacStrike knows how to run.
///
/// A game is the user-facing unit: it owns a bottle (resolved by `bottleName`,
/// so an existing bottle on disk is adopted rather than duplicated) and, for
/// Steam titles, a Steam app id.
public struct Game: Identifiable, Sendable, Equatable {
    /// Stable slug ("cs2"), or "custom:<name>" for a user-added executable.
    public let id: String
    /// Display name.
    public let name: String
    /// Directory name under `<support>/Bottles/` that backs this game.
    public let bottleName: String
    /// Steam app id, or nil for a bare executable.
    public let steamAppID: Int?
    /// Graphics translation backend this game should use.
    public let backend: GraphicsBackend
    /// Card gradient, as hex strings. The GUI resolves these to colors — the
    /// engine stays free of SwiftUI.
    public let accentFrom: String
    public let accentTo: String
    /// False for catalog entries that are placeholders ("coming soon").
    public let supported: Bool
    /// Absolute path to the executable, for custom (non-Steam) games.
    public let exePath: String?

    public init(
        id: String,
        name: String,
        bottleName: String,
        steamAppID: Int?,
        backend: GraphicsBackend = .d3dmetal,
        accentFrom: String,
        accentTo: String,
        supported: Bool = true,
        exePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.bottleName = bottleName
        self.steamAppID = steamAppID
        self.backend = backend
        self.accentFrom = accentFrom
        self.accentTo = accentTo
        self.supported = supported
        self.exePath = exePath
    }

    /// A user-added game backed by a bare `.exe`. Runs in a shared "Custom" bottle.
    public static func custom(name: String, exePath: String) -> Game {
        Game(id: "custom:\(name)",
             name: name,
             bottleName: "Custom",
             steamAppID: nil,
             accentFrom: "#3A3F55",
             accentTo: "#22263A",
             exePath: exePath)
    }
}

/// The built-in game catalog.
public enum GameCatalog {
    public static let cs2 = Game(
        id: "cs2",
        name: "Counter-Strike 2",
        bottleName: "CS2",
        steamAppID: SteamApp.cs2,
        accentFrom: "#243B6B",
        accentTo: "#14203A")

    /// Placeholder — not supported yet, shown as "em breve".
    public static let gtaV = Game(
        id: "gtav",
        name: "Grand Theft Auto V",
        bottleName: "GTAV",
        steamAppID: SteamApp.gtaV,
        accentFrom: "#6B5A24",
        accentTo: "#3F3016",
        supported: false)

    public static let builtins: [Game] = [cs2, gtaV]

    public static func game(id: String) -> Game? {
        builtins.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build && swift run selftest`
Expected: PASS — all checks pass, including the 12 new ones.

- [ ] **Step 5: Commit**

```bash
git add Sources/BottleEngine/Game.swift Sources/selftest/main.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add Game model and built-in game catalog"
```

---

### Task 2: `SetupStep`, `SetupState`, `SetupPlan`

The pure brain of the wizard: the canonical step order per game, and which step comes next given what's already on disk. No I/O — this is the piece the selftest can fully cover.

**Files:**
- Create: `Sources/BottleEngine/SetupPlan.swift`
- Test: `Sources/selftest/main.swift` (append)

**Interfaces:**
- Consumes: `Game` from Task 1.
- Produces: `SetupStep` (cases `.installWine`, `.createBottle`, `.fetchDXMT`, `.installGraphics`, `.installSteam`, `.installGame(appID: Int)`, `.ready`); `SetupState` (mutable bools `wineReady`, `bottleExists`, `dxmtDownloaded`, `graphicsInstalled`, `steamInstalled`, `gameInstalled`, with a memberwise init defaulting every field to `false`); `SetupPlan.steps(for:)`, `SetupPlan.isSatisfied(_:given:)`, `SetupPlan.next(for:given:)`, `SetupPlan.progress(for:given:)`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/selftest/main.swift`, before the final summary block:

```swift
print("SetupPlan (pure):")
do {
    let cs2 = GameCatalog.cs2
    let steps = SetupPlan.steps(for: cs2)
    check(steps == [.installWine, .createBottle, .fetchDXMT,
                    .installGraphics, .installSteam, .installGame(appID: 730)],
          "cs2 step order: wine -> bottle -> dxmt -> graphics -> steam -> game")

    // Wine must come before the bottle: wineboot needs a usable Wine.
    check(steps.firstIndex(of: .installWine)! < steps.firstIndex(of: .createBottle)!,
          "Wine is installed before the bottle is created")

    let custom = Game.custom(name: "X", exePath: "/tmp/x.exe")
    check(SetupPlan.steps(for: custom) == [.installWine, .createBottle, .fetchDXMT, .installGraphics],
          "a custom game skips the Steam steps")

    // Nothing done yet -> first step.
    var st = SetupState()
    check(SetupPlan.next(for: cs2, given: st) == .installWine, "empty state starts at installWine")
    check(SetupPlan.progress(for: cs2, given: st) == 0, "empty state is 0% progress")

    // Satisfied steps are skipped.
    st.wineReady = true
    check(SetupPlan.next(for: cs2, given: st) == .createBottle, "wine ready -> createBottle")
    st.bottleExists = true
    check(SetupPlan.next(for: cs2, given: st) == .fetchDXMT, "bottle exists -> fetchDXMT")
    st.dxmtDownloaded = true
    check(SetupPlan.next(for: cs2, given: st) == .installGraphics, "dxmt ready -> installGraphics")
    st.graphicsInstalled = true
    check(SetupPlan.next(for: cs2, given: st) == .installSteam, "graphics ready -> installSteam")
    st.steamInstalled = true
    check(SetupPlan.next(for: cs2, given: st) == .installGame(appID: 730), "steam ready -> installGame")

    // Mid-way progress is a real fraction.
    let mid = SetupPlan.progress(for: cs2, given: st)
    check(mid > 0.8 && mid < 1.0, "five of six steps done is between 80% and 100%")

    // Everything done -> ready.
    st.gameInstalled = true
    check(SetupPlan.next(for: cs2, given: st) == .ready, "all satisfied -> ready")
    check(SetupPlan.progress(for: cs2, given: st) == 1.0, "all satisfied -> 100%")

    // Out-of-order satisfaction still returns the earliest missing step.
    var holes = SetupState()
    holes.wineReady = true
    holes.steamInstalled = true
    check(SetupPlan.next(for: cs2, given: holes) == .createBottle,
          "later steps done out of order still reports the earliest gap")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run selftest`
Expected: FAIL to compile — `cannot find 'SetupPlan' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/BottleEngine/SetupPlan.swift`:

```swift
import Foundation

/// One unit of work needed to make a game playable.
public enum SetupStep: Equatable, Sendable {
    /// Download and install the open Wine build.
    case installWine
    /// Create (or adopt) the game's bottle and boot its prefix.
    case createBottle
    /// Download the DXMT D3D->Metal runtime.
    case fetchDXMT
    /// Copy the translation DLLs into the bottle.
    case installGraphics
    /// Install the Windows Steam client into the bottle.
    case installSteam
    /// Let Steam download the game, then detect it on disk.
    case installGame(appID: Int)
    /// Nothing left to do.
    case ready
}

/// What is already satisfied on disk. Plain bools so the planner stays pure
/// and fully testable; the GUI fills this in by inspecting the filesystem.
public struct SetupState: Sendable, Equatable {
    public var wineReady: Bool
    public var bottleExists: Bool
    public var dxmtDownloaded: Bool
    public var graphicsInstalled: Bool
    public var steamInstalled: Bool
    public var gameInstalled: Bool

    public init(
        wineReady: Bool = false,
        bottleExists: Bool = false,
        dxmtDownloaded: Bool = false,
        graphicsInstalled: Bool = false,
        steamInstalled: Bool = false,
        gameInstalled: Bool = false
    ) {
        self.wineReady = wineReady
        self.bottleExists = bottleExists
        self.dxmtDownloaded = dxmtDownloaded
        self.graphicsInstalled = graphicsInstalled
        self.steamInstalled = steamInstalled
        self.gameInstalled = gameInstalled
    }
}

/// Decides *what* a game still needs, and in what order. Pure: no I/O.
public enum SetupPlan {

    /// The canonical step order for `game`.
    ///
    /// Wine comes first because creating a bottle runs `wineboot`, which needs a
    /// usable Wine. Steam steps only apply to Steam titles.
    public static func steps(for game: Game) -> [SetupStep] {
        var steps: [SetupStep] = [.installWine, .createBottle, .fetchDXMT, .installGraphics]
        if let appID = game.steamAppID {
            steps.append(.installSteam)
            steps.append(.installGame(appID: appID))
        }
        return steps
    }

    /// Is this step already done, according to `state`?
    public static func isSatisfied(_ step: SetupStep, given state: SetupState) -> Bool {
        switch step {
        case .installWine:     return state.wineReady
        case .createBottle:    return state.bottleExists
        case .fetchDXMT:       return state.dxmtDownloaded
        case .installGraphics: return state.graphicsInstalled
        case .installSteam:    return state.steamInstalled
        case .installGame:     return state.gameInstalled
        case .ready:           return true
        }
    }

    /// The earliest unsatisfied step, or `.ready`.
    public static func next(for game: Game, given state: SetupState) -> SetupStep {
        steps(for: game).first { !isSatisfied($0, given: state) } ?? .ready
    }

    /// Fraction of this game's steps already satisfied, 0...1.
    public static func progress(for game: Game, given state: SetupState) -> Double {
        let all = steps(for: game)
        guard !all.isEmpty else { return 1 }
        let done = all.filter { isSatisfied($0, given: state) }.count
        return Double(done) / Double(all.count)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build && swift run selftest`
Expected: PASS — all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BottleEngine/SetupPlan.swift Sources/selftest/main.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add pure setup planner (steps, state, next, progress)"
```

---

### Task 3: `GameDetection`

Answers "is the game actually downloaded?" — the thing the wizard polls for while Steam does the downloading. The path helper is pure and testable; only the existence check touches disk.

**Files:**
- Create: `Sources/BottleEngine/GameDetection.swift`
- Test: `Sources/selftest/main.swift` (append)

**Interfaces:**
- Consumes: `Bottle` (existing), `SteamApp` (existing).
- Produces: `GameDetection.knownInstallDirs: [Int: String]`, `GameDetection.steamAppsCommon(in:)`, `GameDetection.installDir(for:in:)`, `GameDetection.isInstalled(appID:in:)`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/selftest/main.swift`, before the final summary block:

```swift
print("GameDetection:")
do {
    let b = Bottle(name: "CS2", prefixPath: URL(fileURLWithPath: "/tmp/bottles/CS2"))
    check(GameDetection.steamAppsCommon(in: b).path
            == "/tmp/bottles/CS2/drive_c/Program Files (x86)/Steam/steamapps/common",
          "steamapps/common path inside the bottle")
    check(GameDetection.installDir(for: SteamApp.cs2, in: b)?.lastPathComponent
            == "Counter-Strike Global Offensive",
          "cs2 install dir name matches Steam's on-disk name")
    check(GameDetection.installDir(for: 999999, in: b) == nil,
          "unknown app id has no known install dir")
    check(!GameDetection.isInstalled(appID: SteamApp.cs2, in: b),
          "nothing installed under a bogus prefix")

    // Create the directory and it should be detected.
    let fm = FileManager.default
    let dir = GameDetection.installDir(for: SteamApp.cs2, in: b)!
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    check(GameDetection.isInstalled(appID: SteamApp.cs2, in: b),
          "detects the game once its directory exists")
    try? fm.removeItem(at: URL(fileURLWithPath: "/tmp/bottles/CS2"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run selftest`
Expected: FAIL to compile — `cannot find 'GameDetection' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/BottleEngine/GameDetection.swift`:

```swift
import Foundation

/// Detects whether a Steam game is actually installed inside a bottle.
///
/// MacStrike cannot see Steam's download progress — Steam owns that UI. What it
/// can do is watch for the game's install directory to appear, which is how the
/// setup wizard knows the download finished.
public enum GameDetection {

    /// Steam app id -> directory name under `steamapps/common`.
    /// Matches the names Steam actually uses on disk.
    public static let knownInstallDirs: [Int: String] = [
        SteamApp.cs2: "Counter-Strike Global Offensive",
        SteamApp.gtaV: "Grand Theft Auto V",
    ]

    /// `steamapps/common` inside `bottle`.
    public static func steamAppsCommon(in bottle: Bottle) -> URL {
        bottle.prefixPath
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common")
    }

    /// Where `appID` would be installed in `bottle`, or nil if we don't know
    /// its directory name. Pure path math — does not touch disk.
    public static func installDir(for appID: Int, in bottle: Bottle) -> URL? {
        guard let name = knownInstallDirs[appID] else { return nil }
        return steamAppsCommon(in: bottle).appendingPathComponent(name)
    }

    /// Is `appID` present in `bottle`?
    public static func isInstalled(appID: Int, in bottle: Bottle) -> Bool {
        guard let dir = installDir(for: appID, in: bottle) else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build && swift run selftest`
Expected: PASS — all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BottleEngine/GameDetection.swift Sources/selftest/main.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Detect installed Steam games inside a bottle"
```

---

### Task 4: `WineInstaller`

Makes the wizard autonomous: downloads the Gcenx Wine build from GitHub and installs it into `<support>/wine`, which is exactly what `scripts/setup-wine.sh` does today. Mirrors `DXMTInstaller`'s structure (`Sources/BottleEngine/DXMTInstaller.swift`) deliberately — same download/extract/lay-out shape, same pure-helper-plus-orchestration split. Note the archive is `.tar.xz` (not `.tar.gz`), so extraction uses `tar -xJf`.

**Files:**
- Create: `Sources/BottleEngine/WineInstaller.swift`
- Test: `Sources/selftest/main.swift` (append)

**Interfaces:**
- Consumes: `WineInstallation` (existing).
- Produces: `WineInstaller(supportDir:channel:)` with `channel` defaulting to `"staging"`; `WineInstaller.releasesAPI`; `WineInstaller.pickAsset(fromReleaseJSON:channel:)` returning `(tag: String, url: URL)`; `WineInstaller.wineRoot`; `WineInstaller.isInstalled`; `WineInstaller.install(progress:)` returning `WineInstaller.Result` with `tag` and `root`; `WineInstaller.WineError`.

- [ ] **Step 1: Write the failing test**

Append to `Sources/selftest/main.swift`, before the final summary block. The network path is not tested (selftest must stay offline); the pure asset picker is:

```swift
print("WineInstaller asset picking:")
do {
    let json = """
    {"tag_name":"wine-staging-11.18",
     "assets":[
       {"name":"wine-devel-11.18-osx64.tar.xz",
        "browser_download_url":"https://example.com/wine-devel-11.18-osx64.tar.xz"},
       {"name":"wine-staging-11.18-osx64.tar.xz",
        "browser_download_url":"https://example.com/wine-staging-11.18-osx64.tar.xz"},
       {"name":"README.md",
        "browser_download_url":"https://example.com/README.md"}
     ]}
    """.data(using: .utf8)!

    let staging = try WineInstaller.pickAsset(fromReleaseJSON: json, channel: "staging")
    check(staging.tag == "wine-staging-11.18", "reads the release tag")
    check(staging.url.lastPathComponent == "wine-staging-11.18-osx64.tar.xz",
          "staging channel picks the staging tarball")

    let devel = try WineInstaller.pickAsset(fromReleaseJSON: json, channel: "devel")
    check(devel.url.lastPathComponent == "wine-devel-11.18-osx64.tar.xz",
          "devel channel picks the devel tarball")

    // No channel match -> falls back to the first .tar.xz, never the README.
    let other = try WineInstaller.pickAsset(fromReleaseJSON: json, channel: "nope")
    check(other.url.pathExtension == "xz", "falls back to a tarball, not a stray asset")

    // No tarballs at all -> throws.
    let empty = #"{"tag_name":"x","assets":[{"name":"a.txt","browser_download_url":"https://e/a.txt"}]}"#
        .data(using: .utf8)!
    var threw = false
    do { _ = try WineInstaller.pickAsset(fromReleaseJSON: empty, channel: "staging") }
    catch { threw = true }
    check(threw, "no .tar.xz asset throws")

    let inst = WineInstaller(supportDir: URL(fileURLWithPath: "/tmp/ms-support"))
    check(inst.wineRoot.path == "/tmp/ms-support/wine", "installs into <support>/wine")
    check(!inst.isInstalled, "a bogus support dir has no Wine")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run selftest`
Expected: FAIL to compile — `cannot find 'WineInstaller' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/BottleEngine/WineInstaller.swift`:

```swift
import Foundation

/// Downloads and installs the open-source macOS Wine build (Gcenx) into
/// `<support>/wine`, the same layout `scripts/setup-wine.sh` produces.
///
/// Release assets are `.tar.xz` tarballs named like `wine-staging-11.18-osx64.tar.xz`.
/// Inside, the Wine tree sits at some depth (often `.../Contents/Resources/wine`),
/// so we locate it by finding `bin/wine` and copying that directory's parent.
public struct WineInstaller: Sendable {

    public static let releasesAPI = URL(string:
        "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest")!

    /// Directory holding `wine/`, `downloads/` (e.g. ~/Library/Application Support/MacStrike).
    public let supportDir: URL
    /// Release channel: "staging" (default) or "devel".
    public let channel: String

    public init(supportDir: URL, channel: String = "staging") {
        self.supportDir = supportDir
        self.channel = channel
    }

    public enum WineError: Error, CustomStringConvertible {
        case network(String)
        case noAsset
        case extractionFailed(String)
        case badArchive(String)
        public var description: String {
            switch self {
            case .network(let m):          return "Erro de rede: \(m)"
            case .noAsset:                 return "Nenhum .tar.xz encontrado na última release do Wine"
            case .extractionFailed(let m): return "Falha ao extrair o Wine: \(m)"
            case .badArchive(let m):       return "Layout inesperado no arquivo do Wine: \(m)"
            }
        }
    }

    /// Where Wine gets installed.
    public var wineRoot: URL { supportDir.appendingPathComponent("wine") }

    /// Is a usable Wine already installed?
    public var isInstalled: Bool { WineInstallation(root: wineRoot).isUsable }

    // MARK: - Pure helpers (unit-tested)

    /// Parse GitHub's "latest release" JSON and pick the tarball for `channel`.
    /// Falls back to the first `.tar.xz` when the channel has no match.
    public static func pickAsset(
        fromReleaseJSON data: Data, channel: String
    ) throws -> (tag: String, url: URL) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else {
            throw WineError.badArchive("release JSON sem assets")
        }
        let tag = (obj["tag_name"] as? String) ?? "latest"
        let tarballs: [String] = assets
            .compactMap { $0["browser_download_url"] as? String }
            .filter { $0.hasSuffix(".tar.xz") }
        let chosen = tarballs.first { $0.contains("wine-\(channel)-") } ?? tarballs.first
        guard let chosen, let url = URL(string: chosen) else { throw WineError.noAsset }
        return (tag, url)
    }

    /// Find the Wine tree inside an extracted archive: the parent of the
    /// directory containing `bin/wine`.
    public static func wineSourceDir(in extractedRoot: URL) throws -> URL {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: extractedRoot,
                                         includingPropertiesForKeys: nil) else {
            throw WineError.badArchive("não consegui percorrer o arquivo extraído")
        }
        for case let url as URL in walker {
            // Looking for <something>/bin/wine
            guard url.lastPathComponent == "wine" else { continue }
            let parent = url.deletingLastPathComponent()
            guard parent.lastPathComponent == "bin" else { continue }
            return parent.deletingLastPathComponent()
        }
        throw WineError.badArchive("não encontrei bin/wine no arquivo extraído")
    }

    // MARK: - Network / fs steps

    func fetchLatestAsset() throws -> (tag: String, url: URL) {
        let sem = DispatchSemaphore(value: 0)
        var err: String?
        var data: Data?
        var req = URLRequest(url: Self.releasesAPI)
        req.setValue("MacStrike", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: req) { d, resp, e in
            if let e { err = e.localizedDescription }
            else if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                err = "HTTP \(h.statusCode)"
            } else { data = d }
            sem.signal()
        }
        task.resume(); sem.wait()
        if let err { throw WineError.network(err) }
        guard let data else { throw WineError.network("resposta vazia") }
        return try Self.pickAsset(fromReleaseJSON: data, channel: channel)
    }

    func download(_ url: URL, to dst: URL) throws {
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sem = DispatchSemaphore(value: 0)
        var err: String?
        var tmp: URL?
        var req = URLRequest(url: url)
        req.setValue("MacStrike", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: req) { u, resp, e in
            if let e { err = e.localizedDescription }
            else if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                err = "HTTP \(h.statusCode)"
            } else { tmp = u }
            sem.signal()
        }
        task.resume(); sem.wait()
        if let err { throw WineError.network(err) }
        guard let tmp else { throw WineError.network("nenhum arquivo retornado") }
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
    }

    func extract(_ tarball: URL, into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xJf", tarball.path, "-C", dir.path]   // -J = xz
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw WineError.extractionFailed("tar saiu com \(p.terminationStatus)")
        }
    }

    // MARK: - Orchestration

    public struct Result: Sendable {
        public let tag: String
        public let root: URL
    }

    /// Full install: query the latest release, download, extract, copy the Wine
    /// tree into `<support>/wine`. A no-op when Wine is already installed.
    @discardableResult
    public func install(progress: (@Sendable (String) -> Void)? = nil) throws -> Result {
        let fm = FileManager.default
        if isInstalled {
            progress?("Wine já instalado — nada a fazer.")
            return Result(tag: "existente", root: wineRoot)
        }

        progress?("Consultando a última release do Wine…")
        let (tag, assetURL) = try fetchLatestAsset()

        let downloads = supportDir.appendingPathComponent("downloads")
        let tarball = downloads.appendingPathComponent("wine-\(tag).tar.xz")
        progress?("Baixando \(assetURL.lastPathComponent) (~190 MB)…")
        try download(assetURL, to: tarball)

        let staging = downloads.appendingPathComponent("wine-\(tag)-extracted")
        try? fm.removeItem(at: staging)
        progress?("Extraindo…")
        try extract(tarball, into: staging)

        let source = try Self.wineSourceDir(in: staging)
        progress?("Instalando em \(wineRoot.lastPathComponent)…")
        try? fm.removeItem(at: wineRoot)
        try fm.createDirectory(at: wineRoot, withIntermediateDirectories: true)
        // Copy the tree's *contents* so wineRoot ends up with bin/, lib/, …
        for entry in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: entry, to: wineRoot.appendingPathComponent(entry.lastPathComponent))
        }
        try? fm.removeItem(at: staging)

        guard isInstalled else {
            throw WineError.badArchive("instalação terminou sem bin/wine utilizável")
        }
        progress?("Wine \(tag) pronto.")
        return Result(tag: tag, root: wineRoot)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift build && swift run selftest`
Expected: PASS — all checks pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/BottleEngine/WineInstaller.swift Sources/selftest/main.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Install open Wine (Gcenx) from the engine, no shell script needed"
```

---

### Task 5: Aurora theme

The design tokens every view uses. Small, self-contained, and it must come before the views so they have something to paint with.

**Files:**
- Create: `Sources/MacStrikeGUI/Theme.swift`

**Interfaces:**
- Produces: `Color.init?(hex:)`; `Theme.bg`, `Theme.bgRaised`, `Theme.card`, `Theme.stroke`, `Theme.textPrimary`, `Theme.textSecondary`, `Theme.accentFrom`, `Theme.accentTo`, `Theme.accent`, `Theme.accentGradient`, `Theme.ok`, `Theme.warn`, `Theme.radius`, `Theme.radiusSmall`; `Theme.gradient(from:to:)`; view modifier `.auroraCard()`; `AuroraButtonStyle`.

Verification for this task is a clean build — there is no UI to test yet.

- [ ] **Step 1: Write the theme**

Create `Sources/MacStrikeGUI/Theme.swift`:

```swift
import SwiftUI

extension Color {
    /// Build a color from "#RRGGBB" (or "RRGGBB"). Returns nil on bad input.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red:   Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >>  8) & 0xFF) / 255,
                  blue:  Double( v        & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Aurora — MacStrike's dark theme: blue→purple accents over deep navy.
enum Theme {
    static let bg         = Color(hex: "#0B0D14")!
    static let bgRaised   = Color(hex: "#10131C")!
    static let card       = Color.white.opacity(0.04)
    static let stroke     = Color.white.opacity(0.07)
    static let textPrimary   = Color(hex: "#E8ECF5")!
    static let textSecondary = Color(hex: "#8893AB")!

    static let accentFrom = Color(hex: "#5B8CFF")!
    static let accentTo   = Color(hex: "#7A5CFF")!
    static let accent     = accentFrom
    static let ok         = Color(hex: "#6EE7A8")!
    static let warn       = Color(hex: "#FFB065")!

    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 10

    static let accentGradient = LinearGradient(
        colors: [accentFrom, accentTo], startPoint: .topLeading, endPoint: .bottomTrailing)

    /// A card gradient from a `Game`'s hex pair, falling back to the accent.
    static func gradient(from: String, to: String) -> LinearGradient {
        LinearGradient(
            colors: [Color(hex: from) ?? accentFrom, Color(hex: to) ?? accentTo],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The app background: a subtle vertical wash, not a flat fill.
    static let backgroundWash = LinearGradient(
        colors: [bgRaised, bg], startPoint: .top, endPoint: .bottom)
}

/// Standard raised panel: translucent fill, hairline stroke, rounded corners.
struct AuroraCard: ViewModifier {
    var radius: CGFloat = Theme.radius
    func body(content: Content) -> some View {
        content
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func auroraCard(radius: CGFloat = Theme.radius) -> some View {
        modifier(AuroraCard(radius: radius))
    }
}

/// The primary call-to-action: gradient fill, white text, springy press.
struct AuroraButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : Theme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accentGradient)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.card)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds with no errors (the theme is not referenced yet, which is fine).

- [ ] **Step 3: Commit**

```bash
git add Sources/MacStrikeGUI/Theme.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add Aurora theme tokens and shared view styles"
```

---

### Task 6: `AppModel`

Replaces `BottleStore`. It resolves a game's bottle by name (adopting the user's existing `Bottles/CS2`), computes a `SetupState` per game by inspecting disk, holds licensing, and keeps the custom-game list. `BottleStore.swift` is deleted in this task, so `ContentView.swift` — which references it — is deleted too; the app gets a temporary placeholder root view that Task 7+ replace.

**Files:**
- Create: `Sources/MacStrikeGUI/AppModel.swift`
- Delete: `Sources/MacStrikeGUI/BottleStore.swift`
- Delete: `Sources/MacStrikeGUI/ContentView.swift`
- Modify: `Sources/MacStrikeGUI/MacStrikeApp.swift`

**Interfaces:**
- Consumes: `Game`, `GameCatalog`, `SetupState`, `SetupPlan`, `GameDetection`, `WineInstaller` (Tasks 1–4); existing `Bottle`, `BottleManager`, `WineInstallation`, `SteamProvisioner`, `GameLauncher`, `LicenseManager`, `DXMTInstaller`, `GraphicsBackend`, `PerformanceProfile`.
- Produces: `AppModel` (`@MainActor`, `ObservableObject`) with published `games`, `customGames`, `log`, `lastError`, `licenseStatus`, `entitlement`, `activating`; stored `supportDir`, `bottlesRoot`; computed `wine`, `manager`, `launcher`, `steam`, `wineInstaller`, `dxmtDLLDir`, `isPro`, `licensingConfigured`, `entitlementLabel`; methods `bottle(for:)`, `bottleOrNil(for:)`, `setupState(for:)`, `nextStep(for:)`, `progress(for:)`, `isReady(for:)`, `refreshAll()`, `appendLog(_:)`, `play(_:)`, `openBottleFolder(_:)`, `runExe(in:exePath:)`, `addCustomGame(name:exePath:)`, `updateBottle(for:backend:turbo:)`, `activateLicense(_:)`, `deactivateLicense()`, `refreshEntitlement()`.

- [ ] **Step 1: Write `AppModel`**

Create `Sources/MacStrikeGUI/AppModel.swift`:

```swift
import Foundation
import Combine
import AppKit
import BottleEngine

/// App state and the bridge to BottleEngine, organised around *games*.
///
/// A game's bottle is resolved by `Game.bottleName`, so a bottle the user
/// already has on disk (e.g. `Bottles/CS2`) is adopted rather than duplicated.
@MainActor
final class AppModel: ObservableObject {

    // Library
    @Published var customGames: [Game] = []
    /// Bumped whenever on-disk state changes, to force setup re-evaluation.
    @Published private(set) var revision = 0

    // Diagnostics
    @Published var log = ""
    @Published var lastError: String?

    // Licensing
    @Published var licenseStatus: LicenseStatus = .unlicensed
    @Published var entitlement: Entitlement = .community
    @Published var activating = false

    let supportDir: URL
    let bottlesRoot: URL

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacStrike")
        self.supportDir = support
        self.bottlesRoot = support.appendingPathComponent("Bottles")
        try? FileManager.default.createDirectory(at: bottlesRoot, withIntermediateDirectories: true)
        loadCustomGames()
        refreshEntitlement()
    }

    // MARK: - Engine handles

    var wine: WineInstallation { WineInstallation(root: supportDir.appendingPathComponent("wine")) }
    var manager: BottleManager { BottleManager(wine: wine) }
    var launcher: GameLauncher { GameLauncher(wine: wine) }
    var steam: SteamProvisioner { SteamProvisioner(launcher: launcher) }
    var wineInstaller: WineInstaller { WineInstaller(supportDir: supportDir) }
    var dxmtInstaller: DXMTInstaller { DXMTInstaller(supportDir: supportDir, wine: wine) }
    var dxmtDLLDir: URL { supportDir.appendingPathComponent("dlls/d3dmetal") }

    /// Every game shown in the library: built-ins first, then user-added.
    var games: [Game] { GameCatalog.builtins + customGames }

    // MARK: - Bottles

    /// The bottle path for a game (whether or not it exists yet).
    func bottlePath(for game: Game) -> URL {
        bottlesRoot.appendingPathComponent(game.bottleName)
    }

    /// The game's bottle as stored on disk, or nil if it hasn't been created.
    func bottleOrNil(for game: Game) -> Bottle? {
        try? manager.load(prefixPath: bottlePath(for: game))
    }

    /// The game's bottle, or a fresh unsaved one configured for the game.
    func bottle(for game: Game) -> Bottle {
        bottleOrNil(for: game) ?? Bottle(
            name: game.bottleName,
            prefixPath: bottlePath(for: game),
            graphicsBackend: game.backend)
    }

    // MARK: - Setup state

    /// Inspect disk and report what's already satisfied for `game`.
    func setupState(for game: Game) -> SetupState {
        let b = bottleOrNil(for: game)
        let fm = FileManager.default
        var st = SetupState()
        st.wineReady = wine.isUsable
        st.bottleExists = b != nil
        st.dxmtDownloaded = fm.fileExists(
            atPath: dxmtDLLDir.appendingPathComponent("x86_64-windows").path)
        if let b {
            st.graphicsInstalled = !b.installedGraphicsDLLs.isEmpty
            st.steamInstalled = SteamProvisioner.isInstalled(in: b)
            if let appID = game.steamAppID {
                st.gameInstalled = GameDetection.isInstalled(appID: appID, in: b)
            } else {
                // A custom game is "installed" when its exe is there.
                st.gameInstalled = game.exePath.map { fm.fileExists(atPath: $0) } ?? false
            }
        }
        return st
    }

    func nextStep(for game: Game) -> SetupStep {
        SetupPlan.next(for: game, given: setupState(for: game))
    }
    func progress(for game: Game) -> Double {
        SetupPlan.progress(for: game, given: setupState(for: game))
    }
    func isReady(for game: Game) -> Bool { nextStep(for: game) == .ready }

    /// Re-read disk state; call after any operation that changes it.
    func refreshAll() { revision += 1 }

    // MARK: - Log

    func appendLog(_ line: String) { log += line + "\n" }

    // MARK: - Actions

    /// Launch the game: via Steam for Steam titles, directly for custom ones.
    func play(_ game: Game) {
        let b = bottle(for: game)
        do {
            if let appID = game.steamAppID {
                _ = try steam.play(appID: appID, in: b)
                appendLog("▶ Jogando \(game.name) (app \(appID))")
            } else if let exe = game.exePath {
                _ = try launcher.launch(bottle: b, exePath: exe)
                appendLog("▶ Rodando \(exe)")
            } else {
                lastError = "Esse jogo não tem executável definido."
            }
        } catch {
            lastError = "\(error)"
            appendLog("✗ \(error)")
        }
    }

    func openBottleFolder(_ game: Game) {
        NSWorkspace.shared.open(bottlePath(for: game))
    }

    func runExe(in game: Game, exePath: String) {
        do {
            _ = try launcher.launch(bottle: bottle(for: game), exePath: exePath)
            appendLog("▶ \(URL(fileURLWithPath: exePath).lastPathComponent)")
        } catch {
            lastError = "\(error)"
        }
    }

    /// Apply advanced settings to a game's bottle.
    func updateBottle(for game: Game, backend: GraphicsBackend, turbo: Bool) {
        guard var b = bottleOrNil(for: game) else {
            lastError = "Crie o bottle primeiro (configure o jogo)."
            return
        }
        b.graphicsBackend = backend
        b.performance = turbo ? .turbo : .balanced
        do {
            try manager.save(b)
            appendLog("✓ Ajustes salvos para \(game.name)")
            refreshAll()
        } catch {
            lastError = "\(error)"
        }
    }

    // MARK: - Custom games (persisted as JSON next to the bottles)

    private var customGamesFile: URL { supportDir.appendingPathComponent("custom-games.json") }

    private struct CustomEntry: Codable { var name: String; var exePath: String }

    private func loadCustomGames() {
        guard let data = try? Data(contentsOf: customGamesFile),
              let entries = try? JSONDecoder().decode([CustomEntry].self, from: data) else { return }
        customGames = entries.map { Game.custom(name: $0.name, exePath: $0.exePath) }
    }

    private func saveCustomGames() {
        let entries = customGames.compactMap { g -> CustomEntry? in
            guard let exe = g.exePath else { return nil }
            return CustomEntry(name: g.name, exePath: exe)
        }
        try? JSONEncoder().encode(entries).write(to: customGamesFile, options: .atomic)
    }

    func addCustomGame(name: String, exePath: String) {
        let game = Game.custom(name: name, exePath: exePath)
        guard !customGames.contains(where: { $0.id == game.id }) else { return }
        customGames.append(game)
        saveCustomGames()
    }

    func removeCustomGame(_ game: Game) {
        customGames.removeAll { $0.id == game.id }
        saveCustomGames()
    }

    // MARK: - Licensing

    var licenseManager: LicenseManager {
        LicenseManager(storageURL: supportDir.appendingPathComponent("license.json"))
    }
    var isPro: Bool { entitlement.hasPro }
    var licensingConfigured: Bool { licenseManager.config.isConfigured }

    var entitlementLabel: String {
        switch entitlement {
        case .licensed:        return "Pro"
        case .trial(let days): return "Trial · \(days)d"
        case .trialExpired:    return "MacStrike Pro"
        case .community:       return "Pro"
        }
    }

    func refreshEntitlement() {
        licenseStatus = licenseManager.cachedStatus()
        entitlement = licenseManager.entitlement()
    }

    func activateLicense(_ key: String) {
        activating = true
        let mgr = licenseManager
        Task.detached {
            do {
                _ = try mgr.activate(key: key)
                await MainActor.run { self.refreshEntitlement(); self.activating = false }
            } catch {
                await MainActor.run { self.lastError = "\(error)"; self.activating = false }
            }
        }
    }

    func deactivateLicense() {
        licenseManager.deactivate()
        refreshEntitlement()
    }
}
```

- [ ] **Step 2: Delete the old GUI files**

```bash
git rm Sources/MacStrikeGUI/BottleStore.swift Sources/MacStrikeGUI/ContentView.swift
```

- [ ] **Step 3: Point the app at `AppModel` with a temporary root**

Replace the body of `Sources/MacStrikeGUI/MacStrikeApp.swift`'s `WindowGroup` and its `@StateObject`. The final chrome lands in Task 12; this keeps the target compiling now. Apply these exact edits:

Replace:
```swift
    @StateObject private var store = BottleStore()
```
with:
```swift
    @StateObject private var model = AppModel()
```

Replace:
```swift
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 460)
```
with:
```swift
            Text("MacStrike")
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
```

- [ ] **Step 4: Verify it builds and tests still pass**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass (engine untouched by this task).

- [ ] **Step 5: Commit**

```bash
git add -A Sources/MacStrikeGUI
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Replace BottleStore with game-centric AppModel"
```

---

### Task 7: `SetupRunner` and step presentation

Executes the plan. All the long work (downloads, installers, wineboot) runs off the main thread; the wizard observes `currentStep`, `progress`, `log` and `failure`. The `installGame` step is special: it opens Steam and then **polls** `GameDetection` until the game appears, because Steam owns the download UI.

**Files:**
- Create: `Sources/MacStrikeGUI/SetupRunner.swift`
- Create: `Sources/MacStrikeGUI/SetupStepPresentation.swift`

**Interfaces:**
- Consumes: `AppModel` (Task 6), `SetupStep`/`SetupPlan`/`SetupState` (Task 2), `WineInstaller` (Task 4), `GameDetection` (Task 3).
- Produces: `SetupRunner` (`@MainActor`, `ObservableObject`) with `init(model:game:)`, published `phase`, `currentStep`, `progress`, `log`, `failure`, `waitingForSteam`; methods `start()`, `retry()`, `cancel()`, `refresh()`; enum `SetupRunner.Phase` (`.idle`, `.running`, `.waitingForSteam`, `.failed`, `.done`). Also `SetupStep.title`, `SetupStep.subtitle`, `SetupStep.iconName` (pt-BR UI copy).

- [ ] **Step 1: Write the step presentation**

Create `Sources/MacStrikeGUI/SetupStepPresentation.swift`. UI copy lives here, not in the engine:

```swift
import Foundation
import BottleEngine

// pt-BR copy for setup steps. Kept in the GUI so BottleEngine stays
// logic-only, with no user-facing strings to localise.
extension SetupStep {
    var title: String {
        switch self {
        case .installWine:     return "Instalando o motor"
        case .createBottle:    return "Preparando o ambiente"
        case .fetchDXMT:       return "Baixando a tradução gráfica"
        case .installGraphics: return "Ativando os gráficos"
        case .installSteam:    return "Instalando a Steam"
        case .installGame:     return "Instalando o jogo"
        case .ready:           return "Tudo pronto"
        }
    }

    var subtitle: String {
        switch self {
        case .installWine:
            return "Baixando o Wine open source (~190 MB). Pode deixar rodando."
        case .createBottle:
            return "Criando o ambiente Windows isolado deste jogo."
        case .fetchDXMT:
            return "Baixando o DXMT, que traduz Direct3D para Metal."
        case .installGraphics:
            return "Copiando as DLLs de tradução para o ambiente do jogo."
        case .installSteam:
            return "Baixando e instalando o cliente da Steam."
        case .installGame:
            return "A Steam vai abrir para baixar o jogo. Instale por lá e volte — "
                 + "o MacStrike detecta sozinho quando terminar."
        case .ready:
            return "Esse jogo está pronto para rodar."
        }
    }

    var iconName: String {
        switch self {
        case .installWine:     return "cpu"
        case .createBottle:    return "cube.box"
        case .fetchDXMT:       return "sparkles"
        case .installGraphics: return "wand.and.stars"
        case .installSteam:    return "arrow.down.circle"
        case .installGame:     return "gamecontroller"
        case .ready:           return "checkmark.seal.fill"
        }
    }
}
```

- [ ] **Step 2: Write the runner**

Create `Sources/MacStrikeGUI/SetupRunner.swift`:

```swift
import Foundation
import Combine
import BottleEngine

/// Runs a game's `SetupPlan`, one step at a time, off the main thread.
///
/// Every step is idempotent and re-derived from disk, so cancelling and
/// restarting is safe. The `installGame` step can't be driven by us — Steam
/// downloads the game in its own window — so it opens Steam and polls until
/// the game's directory shows up.
@MainActor
final class SetupRunner: ObservableObject {

    enum Phase: Equatable {
        case idle
        case running
        /// Steam is open and we're waiting for the user to finish the download.
        case waitingForSteam
        case failed(String)
        case done
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentStep: SetupStep = .ready
    @Published private(set) var progress: Double = 0
    @Published private(set) var log: String = ""

    let game: Game
    private let model: AppModel
    private var task: Task<Void, Never>?

    /// Total steps for this game, for "passo N de M".
    let totalSteps: Int
    /// 1-based index of `currentStep` in the plan, for display.
    var stepNumber: Int {
        let all = SetupPlan.steps(for: game)
        guard let i = all.firstIndex(of: currentStep) else { return all.count }
        return i + 1
    }

    init(model: AppModel, game: Game) {
        self.model = model
        self.game = game
        self.totalSteps = SetupPlan.steps(for: game).count
        refresh()
    }

    /// Re-read disk and update the displayed step/progress without running anything.
    func refresh() {
        let state = model.setupState(for: game)
        currentStep = SetupPlan.next(for: game, given: state)
        progress = SetupPlan.progress(for: game, given: state)
        if currentStep == .ready { phase = .done }
    }

    func start() {
        guard phase != .running, phase != .waitingForSteam else { return }
        phase = .running
        task = Task { await self.runLoop() }
    }

    func retry() {
        phase = .idle
        start()
    }

    func cancel() {
        task?.cancel()
        task = nil
        if phase == .running || phase == .waitingForSteam { phase = .idle }
    }

    private func emit(_ line: String) {
        log += line + "\n"
        model.appendLog(line)
    }

    /// Execute steps until the plan is satisfied, a step fails, or we're cancelled.
    private func runLoop() async {
        while !Task.isCancelled {
            refresh()
            let step = currentStep
            if step == .ready {
                phase = .done
                model.refreshAll()
                return
            }
            phase = .running
            emit("▶ \(step.title)")
            do {
                let handled = try await perform(step)
                model.refreshAll()
                if !handled { return }   // step is waiting on the user (Steam)
            } catch {
                emit("✗ \(error)")
                phase = .failed("\(error)")
                return
            }
        }
    }

    /// Run one step. Returns false when the step hands control to the user and
    /// the loop should stop (the Steam download).
    private func perform(_ step: SetupStep) async throws -> Bool {
        switch step {
        case .installWine:
            let installer = model.wineInstaller
            try await run { emit in try installer.install { emit($0) } }
            return true

        case .createBottle:
            let mgr = model.manager
            let bottle = model.bottle(for: game)
            let wineUsable = model.wine.isUsable
            try await run { emit in
                emit("Criando bottle “\(bottle.name)”…")
                _ = try mgr.createBottle(bottle, runWineboot: wineUsable)
            }
            return true

        case .fetchDXMT:
            let installer = model.dxmtInstaller
            try await run { emit in
                let r = try installer.install { emit($0) }
                emit("DXMT \(r.tag) pronto.")
            }
            return true

        case .installGraphics:
            let mgr = model.manager
            let dir = model.dxmtDLLDir
            var bottle = model.bottle(for: game)
            try await run { emit in
                var sources = DLLInstaller.Sources()
                switch bottle.graphicsBackend {
                case .d3dmetal: sources.d3dmetal = dir
                case .dxvk:     sources.dxvk = dir
                case .wined3d:  emit("wined3d: nada a instalar"); return
                }
                let installed = try DLLInstaller(sources: sources)
                    .install(bottle.graphicsBackend, into: bottle)
                bottle.installedGraphicsDLLs = installed
                try mgr.save(bottle)
                emit("Instalado: \(installed.joined(separator: ", "))")
            }
            return true

        case .installSteam:
            let steam = model.steam
            let bottle = model.bottle(for: game)
            try await run { emit in
                emit("Baixando SteamSetup.exe…")
                let p = try steam.install(into: bottle, silent: true)
                p.waitUntilExit()
                emit(SteamProvisioner.isInstalled(in: bottle)
                     ? "Steam instalada."
                     : "Instalador saiu com \(p.terminationStatus)")
            }
            return true

        case .installGame(let appID):
            // Steam owns this download. Open it, then watch for the game.
            let steam = model.steam
            let bottle = model.bottle(for: game)
            try await run { emit in
                emit("Abrindo a Steam para instalar o jogo…")
                _ = try steam.play(appID: appID, in: bottle)
            }
            phase = .waitingForSteam
            emit("Aguardando a instalação pela Steam…")
            await pollForGame(appID: appID, in: bottle)
            return false

        case .ready:
            return true
        }
    }

    /// Poll every 5s (up to 4h) until the game's directory appears.
    private func pollForGame(appID: Int, in bottle: Bottle) async {
        let deadline = Date().addingTimeInterval(4 * 60 * 60)
        while !Task.isCancelled, Date() < deadline {
            if GameDetection.isInstalled(appID: appID, in: bottle) {
                emit("✓ Jogo detectado.")
                model.refreshAll()
                refresh()
                if currentStep == .ready { phase = .done } else { start() }
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// Run blocking work off the main actor, streaming its progress into the log.
    private func run(
        _ work: @escaping @Sendable (@escaping @Sendable (String) -> Void) throws -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try work { line in
                Task { @MainActor in self.emit("  " + line) }
            }
        }.value
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass.

Note: if the compiler complains that `SetupRunner` is captured in a `@Sendable` closure inside `run`, the capture is `self` on the main actor hopping back via `Task { @MainActor in … }`, which is correct; mark the inner closure parameter `@escaping @Sendable` exactly as written.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacStrikeGUI/SetupRunner.swift Sources/MacStrikeGUI/SetupStepPresentation.swift
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add setup runner that executes a game's plan step by step"
```

---

### Task 8: Library view (rail + game grid)

The first screen: the slim Aurora rail and the grid of game cards, including "+ Adicionar jogo".

**Files:**
- Create: `Sources/MacStrikeGUI/RootView.swift`
- Create: `Sources/MacStrikeGUI/LibraryView.swift`
- Modify: `Sources/MacStrikeGUI/MacStrikeApp.swift`

**Interfaces:**
- Consumes: `AppModel` (Task 6), `Theme`/`AuroraButtonStyle` (Task 5), `Game`/`GameCatalog`.
- Produces: `RootView`; `AppSection` enum (`.games`, `.settings`, `.pro`); `LibraryView`; `GameCard`. `RootView` owns `@State selectedGame: Game?` and presents `GameDetailView` (Task 9) — for this task, the navigation target is a placeholder that Task 9 replaces.

- [ ] **Step 1: Write `RootView`**

Create `Sources/MacStrikeGUI/RootView.swift`:

```swift
import SwiftUI
import BottleEngine

enum AppSection: String, CaseIterable, Identifiable {
    case games, settings, pro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .games:    return "Jogos"
        case .settings: return "Ajustes"
        case .pro:      return "Pro"
        }
    }
    var icon: String {
        switch self {
        case .games:    return "gamecontroller.fill"
        case .settings: return "slider.horizontal.3"
        case .pro:      return "star.fill"
        }
    }
}

/// The app shell: a slim icon rail on the left, the active section on the right.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: AppSection = .games
    @State private var selectedGame: Game?

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(Theme.stroke)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backgroundWash.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .alert("Erro", isPresented: .constant(model.lastError != nil)) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var rail: some View {
        VStack(spacing: 10) {
            Text("MS")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.bottom, 10)

            ForEach(AppSection.allCases) { s in
                Button {
                    section = s
                    if s != .games { selectedGame = nil }
                } label: {
                    Image(systemName: s.icon)
                        .font(.system(size: 15))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(section == s ? .white : Theme.textSecondary)
                        .background {
                            if section == s {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(s.label)
            }
            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 62)
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .games:
            if let game = selectedGame {
                GameDetailView(game: game) { selectedGame = nil }
            } else {
                LibraryView { selectedGame = $0 }
            }
        case .settings:
            SettingsView()
        case .pro:
            ProView()
        }
    }
}
```

- [ ] **Step 2: Write `LibraryView` and `GameCard`**

Create `Sources/MacStrikeGUI/LibraryView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import BottleEngine

/// The game library: a grid of cards. Picking one opens its detail screen.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var onSelect: (Game) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.games) { game in
                        GameCard(game: game)
                            .onTapGesture { if game.supported { onSelect(game) } }
                    }
                    AddGameCard { name, path in
                        model.addCustomGame(name: name, exePath: path)
                    }
                }
            }
            .padding(26)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SUA BIBLIOTECA")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline) {
                Text("Jogos").font(.system(size: 26, weight: .bold))
                Spacer()
                Text(model.entitlementLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(model.isPro ? Theme.ok.opacity(0.15) : Theme.card)
                    .foregroundStyle(model.isPro ? Theme.ok : Theme.textSecondary)
                    .clipShape(Capsule())
            }
        }
    }
}

/// One game tile: gradient art, name, and a status badge driven by the plan.
struct GameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    private var badge: (text: String, color: Color) {
        if !game.supported { return ("Em breve", Theme.textSecondary) }
        if model.isReady(for: game) { return ("Pronto", Theme.ok) }
        let pct = Int(model.progress(for: game) * 100)
        return pct == 0 ? ("Preparar", Theme.warn) : ("\(pct)% configurado", Theme.warn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Theme.gradient(from: game.accentFrom, to: game.accentTo)
                    .frame(height: 140)
                if game.supported {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(badge.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(badge.color)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .auroraCard()
        .opacity(game.supported ? 1 : 0.55)
        .scaleEffect(hovering && game.supported ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// The trailing "+ Adicionar jogo" tile: picks an .exe and adds a custom game.
struct AddGameCard: View {
    var onAdd: (String, String) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
            Text("Adicionar jogo")
                .font(.system(size: 13, weight: .medium))
            Text("Escolha um .exe")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 212)
        .background(Color.white.opacity(hovering ? 0.05 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .onHover { hovering = $0 }
        .onTapGesture(perform: pick)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onAdd(url.deletingPathExtension().lastPathComponent, url.path)
    }
}
```

- [ ] **Step 3: Add temporary stubs so the target links**

`RootView` references `GameDetailView`, `SettingsView` and `ProView`, which arrive in Tasks 9–11. Create `Sources/MacStrikeGUI/Stubs.swift` so this task builds and runs on its own; Tasks 9–11 delete each stub as they add the real view:

```swift
import SwiftUI
import BottleEngine

// Temporary placeholders — replaced by Tasks 9, 10 and 11.
// Delete each one as its real view lands.

struct GameDetailView: View {
    let game: Game
    var onBack: () -> Void
    var body: some View {
        VStack { Text(game.name); Button("Voltar", action: onBack) }
    }
}

struct SettingsView: View {
    var body: some View { Text("Ajustes") }
}

struct ProView: View {
    var body: some View { Text("Pro") }
}
```

- [ ] **Step 4: Point the app at `RootView`**

In `Sources/MacStrikeGUI/MacStrikeApp.swift`, replace:
```swift
            Text("MacStrike")
                .environmentObject(model)
```
with:
```swift
            RootView()
                .environmentObject(model)
```

- [ ] **Step 5: Verify it builds and looks right**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass.

Then run the app and look at it: `swift run macstrike-gui`
Expected: a dark navy window; slim rail on the left with three icons; "SUA BIBLIOTECA / Jogos" header with a Pro/Trial pill; CS2 and GTA V cards (GTA V dimmed, "Em breve"); a dashed "Adicionar jogo" tile. Hovering a card lifts it and reveals a play glyph. Quit the app to continue.

- [ ] **Step 6: Commit**

```bash
git add Sources/MacStrikeGUI
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add Aurora rail and game library grid"
```

---

### Task 9: Game detail view

The per-game hero: big gradient header, a setup progress line, and the primary action — **Jogar** when ready, **Configurar** when not.

**Files:**
- Create: `Sources/MacStrikeGUI/GameDetailView.swift`
- Modify: `Sources/MacStrikeGUI/Stubs.swift` (remove the `GameDetailView` stub)

**Interfaces:**
- Consumes: `AppModel`, `Theme`, `AuroraButtonStyle`, `SetupStep.title`/`.subtitle` (Task 7), `SetupPlan`.
- Produces: `GameDetailView(game:onBack:)`, presenting `SetupWizardView` (Task 10) via `.sheet`. For this task the sheet target is the Task 10 view, so Task 10 must land before the wizard opens; the button is wired now and the stub for the wizard is added here and removed in Task 10.

- [ ] **Step 1: Write the detail view**

Create `Sources/MacStrikeGUI/GameDetailView.swift`:

```swift
import SwiftUI
import BottleEngine

/// A single game's screen: hero art, readiness, and the primary action.
struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var onBack: () -> Void

    @State private var showingWizard = false

    private var ready: Bool { model.isReady(for: game) }
    private var progress: Double { model.progress(for: game) }
    private var next: SetupStep { model.nextStep(for: game) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backButton
                hero
                if ready { readyPanel } else { setupPanel }
            }
            .padding(26)
        }
        .sheet(isPresented: $showingWizard) {
            SetupWizardView(game: game)
                .environmentObject(model)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Jogos").font(.system(size: 13))
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.gradient(from: game.accentFrom, to: game.accentTo)
            VStack(alignment: .leading, spacing: 6) {
                Text(ready ? "PRONTO PARA JOGAR" : "PRECISA DE CONFIGURAÇÃO")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.75))
                Text(game.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(22)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var readyPanel: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tudo configurado")
                    .font(.system(size: 15, weight: .semibold))
                Text("O ambiente deste jogo está completo.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { model.play(game) } label: {
                Label("Jogar", systemImage: "play.fill")
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(18)
        .auroraCard()
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Configuração")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            ProgressView(value: progress)
                .tint(Theme.accent)

            HStack(spacing: 11) {
                Image(systemName: next.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Próximo: \(next.title)")
                        .font(.system(size: 13, weight: .medium))
                    Text(next.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button { showingWizard = true } label: {
                Label("Configurar", systemImage: "wand.and.stars")
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(18)
        .auroraCard()
    }
}
```

- [ ] **Step 2: Swap the stubs**

Edit `Sources/MacStrikeGUI/Stubs.swift`: delete the `GameDetailView` struct and add a temporary `SetupWizardView` stub (removed in Task 10), leaving:

```swift
import SwiftUI
import BottleEngine

// Temporary placeholders — replaced by Tasks 10 and 11.
// Delete each one as its real view lands.

struct SetupWizardView: View {
    let game: Game
    var body: some View { Text("Wizard: \(game.name)") }
}

struct SettingsView: View {
    var body: some View { Text("Ajustes") }
}

struct ProView: View {
    var body: some View { Text("Pro") }
}
```

- [ ] **Step 3: Verify it builds and looks right**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass.

Then: `swift run macstrike-gui`
Expected: clicking the CS2 card opens its detail screen — gradient hero with the name, a "Configuração" card showing a real percentage (on this machine CS2's bottle already exists, so it should be well above 0%), the next step with its pt-BR description, and a **Configurar** button. "‹ Jogos" returns to the grid. Quit to continue.

- [ ] **Step 4: Commit**

```bash
git add Sources/MacStrikeGUI
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add per-game hero detail screen"
```

---

### Task 10: Setup wizard

The step-by-step sheet, driven by `SetupRunner`: progress ring, current step, live log, and the three states that matter — running, waiting on Steam, failed.

**Files:**
- Create: `Sources/MacStrikeGUI/SetupWizardView.swift`
- Modify: `Sources/MacStrikeGUI/Stubs.swift` (remove the `SetupWizardView` stub)

**Interfaces:**
- Consumes: `AppModel`, `SetupRunner` + `SetupRunner.Phase` (Task 7), `SetupStep.title`/`.subtitle`/`.iconName`, `Theme`, `AuroraButtonStyle`.
- Produces: `SetupWizardView(game:)`.

- [ ] **Step 1: Write the wizard**

Create `Sources/MacStrikeGUI/SetupWizardView.swift`.

Note the shape here: `@StateObject` must be initialised in `init`, but the
`AppModel` only arrives through the environment. So the view holds a small
**box** object and creates the real `SetupRunner` in `onAppear`, once the
environment exists. Every sub-view takes the runner as a parameter.

```swift
import SwiftUI
import BottleEngine

/// Step-by-step setup for one game.
///
/// The runner needs `AppModel`, which isn't available in `init`, so it is
/// created on first appearance and parked in `RunnerBox`.
struct SetupWizardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: Game

    /// Holds the runner so it can be built after the environment exists.
    @MainActor final class RunnerBox: ObservableObject {
        @Published var runner: SetupRunner?
    }

    @StateObject private var runnerBox = RunnerBox()
    @State private var showLog = false

    init(game: Game) { self.game = game }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let runner = runnerBox.runner {
                content(runner).padding(26)
                Divider().overlay(Theme.stroke)
                footer(runner)
            } else {
                ProgressView().padding(40)
            }
        }
        .frame(width: 460)
        .background(Theme.backgroundWash)
        .foregroundStyle(Theme.textPrimary)
        .onAppear {
            guard runnerBox.runner == nil else { return }
            let r = SetupRunner(model: model, game: game)
            runnerBox.runner = r
            r.start()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CONFIGURANDO")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textSecondary)
                Text(game.name).font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
    }

    @ViewBuilder
    private func content(_ runner: SetupRunner) -> some View {
        VStack(spacing: 16) {
            ring(runner)
            switch runner.phase {
            case .done:
                stepText(title: "Tudo pronto",
                         subtitle: "Esse jogo está configurado. Pode fechar e jogar.")
            case .failed(let message):
                stepText(title: "Algo deu errado", subtitle: message, tint: Theme.warn)
            case .waitingForSteam:
                stepText(title: "Instale o jogo pela Steam",
                         subtitle: runner.currentStep.subtitle)
            case .running, .idle:
                stepText(title: runner.currentStep.title,
                         subtitle: runner.currentStep.subtitle)
            }
            if showLog { logPanel(runner) }
        }
    }

    private func ring(_ runner: SetupRunner) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, runner.progress))
                .stroke(Theme.accentGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: runner.progress)
            VStack(spacing: 2) {
                if runner.phase == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ok)
                } else {
                    Image(systemName: runner.currentStep.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textPrimary)
                    Text("passo \(runner.stepNumber)/\(runner.totalSteps)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: 136, height: 136)
    }

    private func stepText(title: String, subtitle: String,
                          tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
    }

    private func logPanel(_ runner: SetupRunner) -> some View {
        ScrollView {
            Text(runner.log.isEmpty ? "—" : runner.log)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 110)
        .padding(10)
        .auroraCard(radius: Theme.radiusSmall)
    }

    private func footer(_ runner: SetupRunner) -> some View {
        HStack {
            Button(showLog ? "Ocultar detalhes" : "Ver detalhes") { showLog.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            switch runner.phase {
            case .idle:
                Button("Começar") { runner.start() }
                    .buttonStyle(AuroraButtonStyle())
            case .running:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Button("Cancelar") { runner.cancel() }
                        .buttonStyle(AuroraButtonStyle(prominent: false))
                }
            case .waitingForSteam:
                Button("Cancelar") { runner.cancel() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            case .failed:
                Button("Tentar de novo") { runner.retry() }
                    .buttonStyle(AuroraButtonStyle())
            case .done:
                Button("Fechar") { dismiss() }
                    .buttonStyle(AuroraButtonStyle())
            }
        }
        .padding(18)
    }
}
```

- [ ] **Step 2: Remove the wizard stub**

Edit `Sources/MacStrikeGUI/Stubs.swift` to leave only:

```swift
import SwiftUI
import BottleEngine

// Temporary placeholders — replaced by Task 11.

struct SettingsView: View {
    var body: some View { Text("Ajustes") }
}

struct ProView: View {
    var body: some View { Text("Pro") }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass.

- [ ] **Step 4: Verify the wizard by hand — carefully**

Run: `swift run macstrike-gui`, open CS2, click **Configurar**.

Expected: the sheet appears, the ring shows CS2's real progress, and the runner starts at the first unsatisfied step. **On this machine CS2 is already set up**, so the expected result is the wizard landing on "Tudo pronto" with a green check — not a fresh download. To exercise a real step without destroying the working CS2 bottle, use the GTA V card only after flipping `supported` to `true` locally (and revert that), or add a throwaway custom game. **Do not delete the CS2 bottle to test this.**

- [ ] **Step 5: Commit**

```bash
git add Sources/MacStrikeGUI
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add step-by-step setup wizard"
```

---

### Task 11: Settings and Pro screens

The advanced panel (what today's `Form` exposed) and the licensing screen, both in Aurora.

**Files:**
- Create: `Sources/MacStrikeGUI/SettingsView.swift`
- Create: `Sources/MacStrikeGUI/ProView.swift`
- Delete: `Sources/MacStrikeGUI/Stubs.swift`

**Interfaces:**
- Consumes: `AppModel`, `Theme`, `AuroraButtonStyle`, `GraphicsBackend`, `Entitlement`, `LicenseStatus`.
- Produces: `SettingsView`, `ProView`.

- [ ] **Step 1: Write `SettingsView`**

Create `Sources/MacStrikeGUI/SettingsView.swift`:

```swift
import SwiftUI
import UniformTypeIdentifiers
import BottleEngine

/// Advanced settings: per-game bottle tuning, a bare .exe runner, and the log.
/// `turbo` is the one Pro-gated control.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @State private var selectedID: String = GameCatalog.cs2.id
    @State private var backend: GraphicsBackend = .d3dmetal
    @State private var turbo = false
    @State private var exePath = ""

    private var game: Game {
        model.games.first { $0.id == selectedID } ?? GameCatalog.cs2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MODO AVANÇADO")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Ajustes").font(.system(size: 26, weight: .bold))
                }

                bottlePanel
                exePanel
                logPanel
            }
            .padding(26)
        }
        .onAppear(perform: syncFromBottle)
        .onChange(of: selectedID) { _ in syncFromBottle() }
    }

    private func syncFromBottle() {
        let b = model.bottle(for: game)
        backend = b.graphicsBackend
        turbo = b.performance.metalHUD
    }

    private var bottlePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ambiente do jogo").font(.system(size: 15, weight: .semibold))

            Picker("Jogo", selection: $selectedID) {
                ForEach(model.games) { Text($0.name).tag($0.id) }
            }

            Picker("Backend gráfico", selection: $backend) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            Toggle(isOn: $turbo) {
                HStack(spacing: 6) {
                    Text("Perfil turbo (HUD + tudo ligado)")
                    if !model.isPro {
                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.warn.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
            }
            .disabled(!model.isPro)

            HStack(spacing: 10) {
                Button("Salvar") { model.updateBottle(for: game, backend: backend, turbo: turbo) }
                    .buttonStyle(AuroraButtonStyle())
                Button("Abrir pasta do bottle") { model.openBottleFolder(game) }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var exePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rodar um .exe neste ambiente").font(.system(size: 15, weight: .semibold))
            HStack {
                TextField("Caminho do .exe", text: $exePath)
                    .textFieldStyle(.roundedBorder)
                Button("Escolher…") { chooseExe() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
            Button("Lançar") { model.runExe(in: game, exePath: exePath) }
                .buttonStyle(AuroraButtonStyle())
                .disabled(exePath.isEmpty)
        }
        .padding(18)
        .auroraCard()
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Limpar") { model.log = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                Text(model.log.isEmpty ? "—" : model.log)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 150)
        }
        .padding(18)
        .auroraCard()
    }

    private func chooseExe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { exePath = url.path }
    }
}
```

- [ ] **Step 2: Write `ProView`**

Create `Sources/MacStrikeGUI/ProView.swift`:

```swift
import SwiftUI
import BottleEngine

/// Licensing: trial state, activation, and what Pro unlocks.
struct ProView: View {
    @EnvironmentObject var model: AppModel
    @State private var key = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LICENÇA")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Theme.textSecondary)
                    Text("MacStrike Pro").font(.system(size: 26, weight: .bold))
                }

                statusPanel
                if case .active = model.licenseStatus { } else { activatePanel }
                perksPanel
            }
            .padding(26)
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 14) {
            Image(systemName: model.isPro ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 22))
                .foregroundStyle(model.isPro ? Theme.ok : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if case .active = model.licenseStatus {
                Button("Remover licença") { model.deactivateLicense() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var headline: String {
        switch model.entitlement {
        case .licensed:        return "Licença ativa"
        case .trial(let d):    return "Trial — \(d) dia\(d == 1 ? "" : "s") restante\(d == 1 ? "" : "s")"
        case .trialExpired:    return "Trial encerrado"
        case .community:       return "Build community"
        }
    }

    private var detail: String {
        switch model.entitlement {
        case .licensed:
            if case .active(let l) = model.licenseStatus, let email = l.email { return email }
            return "Obrigado por apoiar o MacStrike."
        case .trial:
            return "Todos os recursos Pro liberados durante o trial."
        case .trialExpired:
            return "Ative uma licença lifetime para voltar ao Pro."
        case .community:
            return "Licenciamento não configurado neste build — tudo liberado."
        }
    }

    private var activatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ativar licença").font(.system(size: 15, weight: .semibold))
            Text("Cole a chave que você recebeu na compra.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            TextField("Chave de licença", text: $key)
                .textFieldStyle(.roundedBorder)
                .disabled(model.activating)
            if !model.licensingConfigured {
                Text("⚠︎ Este build ainda não tem o produto configurado (veja LicenseConfig).")
                    .font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
            HStack {
                if model.activating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Ativar") { model.activateLicense(key) }
                    .buttonStyle(AuroraButtonStyle())
                    .disabled(key.isEmpty || model.activating || !model.licensingConfigured)
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var perksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("O que o Pro desbloqueia").font(.system(size: 15, weight: .semibold))
            perk("bolt.fill", "Perfil turbo", "HUD do Metal, shaders assíncronos e GPU de alto desempenho.")
            perk("heart.fill", "Apoia o projeto", "Licença lifetime, sem assinatura recorrente.")
        }
        .padding(18)
        .auroraCard()
    }

    private func perk(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(body).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 3: Delete the stubs file**

```bash
git rm Sources/MacStrikeGUI/Stubs.swift
```

- [ ] **Step 4: Verify it builds and looks right**

Run: `swift build && swift run selftest`
Expected: build succeeds; all checks pass.

Then: `swift run macstrike-gui`
Expected: the rail's second icon shows Ajustes (game picker, backend picker, turbo toggle with a PRO pill if not Pro, save / open-folder, .exe runner, log); the third shows Pro (trial or license state, activation field, perks). Quit to continue.

- [ ] **Step 5: Commit**

```bash
git add -A Sources/MacStrikeGUI
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Add Aurora settings and Pro screens"
```

---

### Task 12: Window chrome and final pass

Hide the title bar, force dark, set a sensible window size, and confirm nothing regressed.

**Files:**
- Modify: `Sources/MacStrikeGUI/MacStrikeApp.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `RootView`, `AppModel`.
- Produces: no new API.

- [ ] **Step 1: Rewrite `MacStrikeApp.swift`**

Replace the whole file with:

```swift
import SwiftUI
import AppKit
import BottleEngine

// SwiftUI front-end for MacStrike.
//
// Two ways to run it:
//   • CLI (no Xcode):   swift run macstrike-gui
//   • Xcode:            open Package.swift in Xcode, pick the "macstrike-gui"
//                       scheme, Run. (To ship a real .app bundle, use the
//                       XcodeGen spec in project.yml — see README.)

@main
struct MacStrikeApp: App {
    @StateObject private var model = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1040, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}  // a game launcher has no "New Document"
        }
    }
}

/// When launched as a bare SwiftPM executable (no .app bundle), macOS does not
/// promote us to a regular, focusable app automatically. Force it so the window
/// appears and takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}
```

- [ ] **Step 2: Update the README's GUI description**

In `README.md`, find the section describing the GUI and replace its description of a bottle list/sidebar with the new flow. Use this wording:

```markdown
A GUI (`swift run macstrike-gui`) é centrada em jogos: uma biblioteca em grade,
a tela de cada jogo com um botão Jogar, e um assistente passo-a-passo que baixa
o Wine, o DXMT e a Steam e detecta quando o jogo terminou de instalar.
```

- [ ] **Step 3: Full verification**

Run: `swift build 2>&1 | tail -5`
Expected: no warnings or errors from the new files.

Run: `swift run selftest`
Expected: "All checks passed." with the original 67 plus every check added in Tasks 1–4.

Run: `swift run macstrike-gui`
Expected: a borderless dark window, 1040×700, rail on the left, library grid. Navigate Jogos → CS2 → back, then Ajustes and Pro. No crashes, no light-mode flashes.

- [ ] **Step 4: Confirm no CrossOver references crept in**

```bash
grep -ri "crossover\|cx_root\|wineloader" Sources/ README.md || echo "clean"
```
Expected: `clean`.

- [ ] **Step 5: Commit**

```bash
git add Sources/MacStrikeGUI/MacStrikeApp.swift README.md
git -c user.name="Lucas Olegario" -c user.email="lucasrolegario@gmail.com" \
  commit -m "Hide title bar, force dark, document the new game-centric GUI"
```

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| `Game`, `GameCatalog` | 1 |
| `SetupStep`, `SetupState`, `SetupPlan` (pure) | 2 |
| `GameDetection` (correction #4) | 3 |
| `WineInstaller` (correction #1) | 4 |
| `createBottle` step (correction #2) | 2 |
| Bottle adopted by name (correction #3) | 1 (`bottleName`), 6 (`bottlePath(for:)`) |
| `accentHex` as strings, engine stays SwiftUI-free (correction #5) | 1, 5 |
| `SetupPlan` pure / runtime state in runner (correction #6) | 2, 7 |
| Single `AppModel` name, `.hiddenTitleBar` (correction #7) | 6, 12 |
| Aurora theme tokens | 5 |
| Left rail: Jogos · Ajustes · Pro | 8 |
| Game grid + status badges | 8 |
| "+ Adicionar jogo" as .exe shortcut | 8 (`AddGameCard`), 6 (`addCustomGame`) |
| Game detail hero + Jogar/Configurar | 9 |
| Wizard sheet with retry | 10 |
| Steam polling, no fake progress | 7 (`pollForGame`), 10 (`waitingForSteam`) |
| Settings: backend, profile, bottle folder, .exe, log | 11 |
| Pro screen, turbo-only gating | 11 |
| selftest additions | 1, 2, 3, 4 |
| CLI untouched | all (no task modifies `Sources/macstrike`) |

No spec requirement is unassigned.

**Type consistency:** `Game.accentFrom`/`accentTo` are used as two `String` properties in Tasks 1, 5, 8 and 9 (the spec sketched a tuple; two properties are used instead so `Equatable` synthesis works — tuples are not nominal `Equatable` types). `SetupState`'s six field names match between Tasks 2, 6 and the tests. `SetupPlan.next(for:given:)` and `progress(for:given:)` keep the same labels in Tasks 2, 6, 7 and 9. `SetupRunner.Phase` cases match between Tasks 7 and 10. `AppModel.isReady(for:)`, `progress(for:)`, `nextStep(for:)` match between Tasks 6, 8 and 9.

**Known wrinkle, handled in Task 10:** `@StateObject` can't see `@EnvironmentObject` in `init`, so the wizard parks its `SetupRunner` in a small `RunnerBox` and builds it in `onAppear`, once the environment exists. Task 10's Step 1 already writes it that way; the sub-views take the runner as a parameter rather than reading a stored property.
