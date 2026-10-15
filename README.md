<div align="center">

# MacStrike

**Run Windows games on macOS — a lightweight, open-source game runtime for Apple Silicon.**

MacStrike creates isolated Wine "bottles", wires in a Direct3D→Metal translation
layer, installs Windows Steam inside them, and launches your games — all from a
clean CLI or a native SwiftUI app.

</div>

---

## What it is

MacStrike is a thin, original orchestration layer over proven open-source
technology. It does the plumbing so you don't have to:

```
macOS (Apple Silicon)
 └─ MacStrike            ← this project (Swift)
     └─ bottle           ← an isolated WINEPREFIX ("a portable Windows")
         └─ Wine         ← runs the Windows .exe (x86_64 via Rosetta 2)
             └─ DXMT / D3DMetal / DXVK   ← Direct3D 11/12 → Metal
                 └─ your GPU
```

Everything heavy is open source and downloaded on demand — MacStrike ships **no
third-party binaries**:

| Component | Role | Source |
|---|---|---|
| **Wine** | Runs Windows executables | Apple Game Porting Toolkit / WineHQ / Gcenx |
| **DXMT** | D3D11 → Metal (Apple Silicon) | [3Shain/dxmt](https://github.com/3Shain/dxmt) |
| **DXVK** | D3D9/10/11 → Vulkan (via MoltenVK) | [doitsujin/dxvk](https://github.com/doitsujin/dxvk) |
| **D3DMetal** | D3D11/12 → Metal | Apple Game Porting Toolkit |

## Features

- 🍾 **Bottle management** — create/configure isolated Wine prefixes per game.
- ⬇️ **One-command setup** — auto-downloads Wine and DXMT.
- 🎮 **Steam built in** — installs the Windows Steam client into a bottle and
  launches games by app ID.
- ⚡ **Performance tuned** — `msync`, persistent shader cache, async shader
  compilation, Rosetta AVX, Metal HUD — the knobs that matter for frame rate.
- 🖥️ **CLI + GUI** — scriptable `macstrike` command, or a native SwiftUI app.
- ✅ **Tested core** — a dependency-free engine with a self-test suite.

## Requirements

- Apple Silicon Mac (M1 or newer), macOS 13+.
- **Rosetta 2** installed (`softwareupdate --install-rosetta`).
- Swift toolchain (Xcode or Command Line Tools) to build.

## Install & build

```bash
git clone https://github.com/lucasolegario/mac-strike.git
cd mac-strike
swift build
swift run selftest        # runs the engine self-tests
swift run macstrike       # shows CLI help
```

## Quick start — running a game

```bash
# 1. Install Wine (one time). Auto-downloads an open-source build.
bash scripts/setup-wine.sh
export MACSTRIKE_WINE_ROOT="$HOME/Library/Application Support/MacStrike/wine"

# 2. Download the DXMT (D3D11→Metal) runtime.
swift run macstrike fetch-dxmt

# 3. Create a bottle for your game.
swift run macstrike create MyGame --backend d3dmetal --perf turbo
PREFIX="$HOME/Library/Application Support/MacStrike/Bottles/MyGame"

# 4. Install the graphics DLLs into the bottle.
swift run macstrike install-graphics "$PREFIX" \
  --from "$HOME/Library/Application Support/MacStrike/dlls/d3dmetal"

# 5. Install the Windows Steam client into the bottle.
swift run macstrike steam "$PREFIX" install

# 6. Log in, install your game, then play it (730 = Counter-Strike 2).
swift run macstrike steam "$PREFIX" run
swift run macstrike steam "$PREFIX" play 730
```

> **Wine compatibility:** some Wine builds have bugs that crash the Steam client
> (e.g. a known TCP-enumeration assertion). If Steam shows a black window or
> exits, point `MACSTRIKE_WINE_ROOT` at the **Apple Game Porting Toolkit** Wine
> (`bash scripts/setup-wine.sh --gptk`), which is the most reliable on macOS.

## GUI

The SwiftUI app mirrors the whole flow — download DXMT, create a bottle, install
graphics, install Steam, and play with one click.

```bash
# A) from the CLI, no Xcode:
swift run macstrike-gui

# B) in Xcode: open Package.swift, pick the "macstrike-gui" scheme, Run.
open Package.swift

# C) build a distributable .app bundle:
brew install xcodegen && xcodegen generate && open MacStrike.xcodeproj
```

## Project layout

```
Sources/
  BottleEngine/     reusable, dependency-free core
    Bottle            model + persisted config (bottle.json)
    WineInstallation  locates wine/wineserver/dll paths
    LaunchEnvironment the launch-environment recipe
    GraphicsBackend   d3dmetal / dxvk / wined3d + DLL overrides
    DLLInstaller      installs translation DLLs into a bottle
    DXMTInstaller     downloads + lays out the DXMT runtime
    BottleManager     create / save / load bottles
    GameLauncher      launch a Windows .exe
    SteamProvisioner  install + drive the Windows Steam client
    PerformanceProfile  frame-rate tunables
  macstrike/        command-line interface
  MacStrikeGUI/     SwiftUI app
  selftest/         dependency-free test runner
scripts/setup-wine.sh   downloads an open-source Wine
```

## How it works

MacStrike is an **interoperability** project: it builds on public, documented
interfaces of open-source software (Wine environment variables, the standard
Wine PE DLL layout, Steam command-line flags) and implements its own
orchestration in Swift. It contains no third-party source code or binaries;
runtime components are fetched from their official open-source releases.

## Contributing

Issues and PRs welcome. The engine is pure Swift with no external dependencies,
so `swift build && swift run selftest` is all you need to iterate.

## License

MacStrike is released under the **MIT License** (see [LICENSE](LICENSE)).

The components MacStrike downloads keep their own licenses: Wine (LGPL-2.1),
DXVK (zlib), DXMT and the Apple Game Porting Toolkit (their respective terms).
MacStrike does not redistribute them — you obtain them from their official
sources. See [CREDITS.md](CREDITS.md).

## Disclaimer

MacStrike is an independent project and is not affiliated with or endorsed by
Valve, Apple, Microsoft, or any game publisher. "Steam" and game titles are
trademarks of their respective owners. Use it in accordance with the terms of
the software and games you run.
