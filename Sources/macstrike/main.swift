import Foundation
import BottleEngine

// macstrike — thin CLI over BottleEngine: create and manage bottles, run games.
//
// Usage:
//   macstrike create <name> [--prefix <dir>] [--arch win64|win32] [--backend d3dmetal|dxvk|wined3d]
//   macstrike info   <prefix-dir>
//   macstrike cmd    <prefix-dir> <path-to-exe> [args...]   # print the launch command
//   macstrike run    <prefix-dir> <path-to-exe> [args...]   # actually launch (needs Wine)
//
// Wine location: $MACSTRIKE_WINE_ROOT, else ~/Library/Application Support/MacStrike/wine

func wineRoot() -> URL {
    if let env = ProcessInfo.processInfo.environment["MACSTRIKE_WINE_ROOT"] {
        return URL(fileURLWithPath: env)
    }
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("MacStrike/wine")
}

func defaultPrefix(name: String) -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("MacStrike/Bottles/\(name)")
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    print("""
    macstrike — run Windows games in Wine bottles (clean-room, open-source stack)

    Commands:
      create <name> [--prefix DIR] [--arch win64|win32] [--backend d3dmetal|dxvk|wined3d] [--perf balanced|turbo]
      info   <prefix-dir>
      license activate <key>                activate a MacStrike Pro license
      license status                        show license state
      license deactivate                    remove the stored license
      fetch-dxmt                            download DXMT (open D3D11->Metal) into MacStrike
      install-graphics <prefix-dir> --from DIR   copy backend DLLs into the bottle
      steam  <prefix-dir> install [--gui]    download + install Windows Steam in the bottle
      steam  <prefix-dir> run                launch the installed Steam client
      steam  <prefix-dir> play <appid>       launch a Steam game (CS2 = 730)
      steam  <prefix-dir> status             is Steam installed? show the play command
      steam  <prefix-dir> disable-overlay    turn off the Steam overlay (close Steam first)
      cmd    <prefix-dir> <exe> [args...]    print the exact launch command
      run    <prefix-dir> <exe> [args...]    launch the game (requires Wine installed)

    Wine root: $MACSTRIKE_WINE_ROOT (default: ~/Library/Application Support/MacStrike/wine)
    """)
    exit(0)
}

let wine = WineInstallation(root: wineRoot())
let rest = Array(args.dropFirst())

func option(_ name: String, in list: [String]) -> String? {
    guard let i = list.firstIndex(of: name), i + 1 < list.count else { return nil }
    return list[i + 1]
}

switch command {
case "create":
    guard let name = rest.first, !name.hasPrefix("--") else { fail("create needs a <name>") }
    let prefix = option("--prefix", in: rest).map { URL(fileURLWithPath: $0) } ?? defaultPrefix(name: name)
    let arch = Bottle.Architecture(rawValue: option("--arch", in: rest) ?? "win64") ?? .win64
    let backend = GraphicsBackend(rawValue: option("--backend", in: rest) ?? "d3dmetal") ?? .d3dmetal
    let perf: PerformanceProfile = (option("--perf", in: rest) == "turbo") ? .turbo : .balanced
    let bottle = Bottle(name: name, prefixPath: prefix, architecture: arch,
                        graphicsBackend: backend, performance: perf)
    do {
        let mgr = BottleManager(wine: wine)
        // Only run wineboot if Wine is actually installed; otherwise just scaffold config.
        let created = try mgr.createBottle(bottle, runWineboot: wine.isUsable)
        print("Created bottle '\(created.name)' at \(created.prefixPath.path)")
        print("  arch=\(created.architecture.rawValue) backend=\(created.graphicsBackend.rawValue)")
        if !wine.isUsable {
            print("  (Wine not found at \(wine.root.path); config written but prefix not initialised)")
        }
    } catch { fail("\(error)") }

case "info":
    guard let dir = rest.first else { fail("info needs a <prefix-dir>") }
    do {
        let bottle = try BottleManager(wine: wine).load(prefixPath: URL(fileURLWithPath: dir))
        let env = LaunchEnvironment.make(for: bottle, wine: wine)
        print("Bottle: \(bottle.name)  [\(bottle.architecture.rawValue), \(bottle.graphicsBackend.rawValue)]")
        print("Launch environment:")
        for (k, v) in env.sorted(by: { $0.key < $1.key }) { print("  \(k)=\(v)") }
    } catch { fail("\(error)") }

case "license":
    let support = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacStrike")
    let mgr = LicenseManager(storageURL: support.appendingPathComponent("license.json"))
    let sub = rest.first ?? "status"
    switch sub {
    case "status":
        switch mgr.entitlement() {
        case .licensed(let l): print("MacStrike Pro — licensed (\(l.email ?? l.key))")
        case .trial(let d):    print("Free trial — \(d) day(s) left")
        case .trialExpired:    print("Trial expired — free tier (activate a license for Pro)")
        case .community:       print("Community build — all features unlocked (licensing not configured)")
        }
    case "activate":
        guard rest.count >= 2 else { fail("license activate needs a <key>") }
        do {
            let l = try mgr.activate(key: rest[1])
            print("Activated. Welcome to MacStrike Pro\(l.email.map { " (\($0))" } ?? "").")
        } catch { fail("\(error)") }
    case "deactivate":
        mgr.deactivate(); print("License removed.")
    default:
        fail("unknown license subcommand '\(sub)'")
    }

case "fetch-dxmt":
    let support = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MacStrike")
    do {
        let installer = DXMTInstaller(supportDir: support, wine: wine)
        let result = try installer.install { print("  \($0)") }
        print("DXMT \(result.tag) ready.")
        print("  DLLs: \(result.dllDir.path)")
        print("  winemetal.so into Wine: \(result.winemetalInstalled ? "yes" : "no")")
        print("Next: macstrike install-graphics <prefix> --from \"\(result.dllDir.path)\"")
    } catch { fail("\(error)") }

case "install-graphics":
    guard let dir = rest.first, let from = option("--from", in: rest) else {
        fail("install-graphics needs <prefix-dir> --from <dll-dir>")
    }
    do {
        let mgr = BottleManager(wine: wine)
        var bottle = try mgr.load(prefixPath: URL(fileURLWithPath: dir))
        let fromURL = URL(fileURLWithPath: from)
        var sources = DLLInstaller.Sources()
        switch bottle.graphicsBackend {
        case .d3dmetal: sources.d3dmetal = fromURL
        case .dxvk:     sources.dxvk = fromURL
        case .wined3d:  fail("backend is wined3d; nothing to install")
        }
        let installed = try DLLInstaller(sources: sources).install(bottle.graphicsBackend, into: bottle)
        // Record what landed so launch-time overrides match reality.
        bottle.installedGraphicsDLLs = installed
        try mgr.save(bottle)
        print("Installed \(bottle.graphicsBackend.rawValue) DLLs into '\(bottle.name)': \(installed.joined(separator: ", "))")
        print("WINEDLLOVERRIDES will force: \(installed.map { "\($0)=n,b" }.joined(separator: ";"))")
    } catch { fail("\(error)") }

case "steam":
    guard rest.count >= 2 else { fail("steam needs <prefix-dir> <install|run|play|status>") }
    let dir = rest[0]
    let sub = rest[1]
    do {
        let bottle = try BottleManager(wine: wine).load(prefixPath: URL(fileURLWithPath: dir))
        let steam = SteamProvisioner(launcher: GameLauncher(wine: wine))
        switch sub {
        case "disable-overlay":
            let n = try SteamConfig.disableOverlay(in: bottle)
            print(n > 0 ? "Steam overlay disabled in \(n) config(s). (Make sure Steam was closed.)"
                        : "Nothing changed — overlay already off, or Steam hasn't created a config yet.")
        case "status":
            if let exe = SteamProvisioner.installedSteamExe(in: bottle) {
                print("Steam installed: \(exe.path)")
            } else {
                print("Steam not installed in '\(bottle.name)'. Run: macstrike steam \"\(dir)\" install")
            }
            print("Play CS2 would run:\n  \(steam.describePlay(appID: SteamApp.cs2, in: bottle))")
        case "install":
            guard wine.isUsable else { fail("Wine not found at \(wine.root.path); run scripts/setup-wine.sh first") }
            print("Downloading SteamSetup.exe …")
            let silent = !rest.contains("--gui")
            let p = try steam.install(into: bottle, silent: silent)
            p.waitUntilExit()
            print(SteamProvisioner.isInstalled(in: bottle)
                  ? "Steam installed into '\(bottle.name)'."
                  : "Installer finished (exit \(p.terminationStatus)); verify with: macstrike steam \"\(dir)\" status")
        case "run":
            guard wine.isUsable else { fail("Wine not found at \(wine.root.path)") }
            _ = try steam.launchSteam(in: bottle)
            print("Launched Steam.")
        case "play":
            guard wine.isUsable else { fail("Wine not found at \(wine.root.path)") }
            guard rest.count >= 3, let appID = Int(rest[2]) else { fail("play needs a numeric <appid> (CS2 = 730)") }
            _ = try steam.play(appID: appID, in: bottle)
            print("Launched app \(appID).")
        default:
            fail("unknown steam subcommand '\(sub)'")
        }
    } catch { fail("\(error)") }

case "cmd", "run":
    guard rest.count >= 2 else { fail("\(command) needs <prefix-dir> <exe> [args...]") }
    let dir = rest[0]
    let exe = rest[1]
    let extra = Array(rest.dropFirst(2))
    do {
        let bottle = try BottleManager(wine: wine).load(prefixPath: URL(fileURLWithPath: dir))
        let launcher = GameLauncher(wine: wine)
        if command == "cmd" {
            print(launcher.describeCommand(bottle: bottle, exePath: exe, arguments: extra))
        } else {
            let p = try launcher.launch(bottle: bottle, exePath: exe, arguments: extra)
            p.waitUntilExit()
            exit(p.terminationStatus)
        }
    } catch { fail("\(error)") }

default:
    fail("unknown command '\(command)'")
}
