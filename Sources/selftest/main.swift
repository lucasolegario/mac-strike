import Foundation
import BottleEngine

// Minimal, dependency-free test runner for the launch-environment recipe.
// Exits non-zero if any check fails.

var failures = 0
@MainActor func check(_ cond: Bool, _ label: String) {
    if cond {
        print("  ok  - \(label)")
    } else {
        print("  FAIL- \(label)")
        failures += 1
    }
}

let wine = WineInstallation(root: URL(fileURLWithPath: "/opt/gamebottle/wine"))
func bottle(_ backend: GraphicsBackend, sync: Bool = true,
            policy: DllOverridePolicy = .prefixWide) -> Bottle {
    // These launch-environment tests are about WINEDLLOVERRIDES, so they ask for
    // the prefix-wide policy explicitly. Per-application is the product default
    // and is covered in its own section below.
    Bottle(name: "test",
           prefixPath: URL(fileURLWithPath: "/tmp/bottles/test"),
           architecture: .win64,
           graphicsBackend: backend,
           synchronizationEnabled: sync,
           overridePolicy: policy)
}

print("LaunchEnvironment recipe:")
do {
    let env = LaunchEnvironment.make(for: bottle(.d3dmetal), wine: wine)
    check(env["WINEPREFIX"] == "/tmp/bottles/test", "WINEPREFIX is set")
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(ov.contains("d3d11=n,b") && ov.contains("d3d12=n,b") && ov.contains("dxgi=n,b"),
          "d3dmetal overrides d3d11/d3d12/dxgi (prefix-wide policy)")
    check(env["WINEMSYNC"] == "1", "sync maps to WINEMSYNC=1")
    check(env["ROSETTA_ADVERTISE_AVX"] == "1", "advertises AVX under Rosetta")
    check(env["DOTNET_EnableWriteXorExecute"] == "0", ".NET W^X fixup")
    check(env["WINELOADER"] == "/opt/gamebottle/wine/bin/wine", "WINELOADER path")
    check(env["WINESERVER"] == "/opt/gamebottle/wine/bin/wineserver", "WINESERVER path")
}
do {
    let env = LaunchEnvironment.make(for: bottle(.dxvk), wine: wine)
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(ov.contains("d3d11=n,b") && ov.contains("dxgi=n,b"), "dxvk overrides d3d/dxgi (prefix-wide policy)")
}
do {
    let env = LaunchEnvironment.make(for: bottle(.wined3d), wine: wine)
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(!ov.contains("d3d11") && !ov.contains("dxgi"), "wined3d has no graphics DLL overrides")
    // Overlay is NOT blocked by default (VAC-safe).
    check(!ov.contains("gameoverlayrenderer"), "overlay NOT blocked by default (VAC-safe)")
}
do {
    var b = bottle(.d3dmetal); b.disableSteamOverlay = true
    let env = LaunchEnvironment.make(for: b, wine: wine)
    check((env["WINEDLLOVERRIDES"] ?? "").contains("gameoverlayrenderer64="), "overlay blocked only when opted in")
}
do {
    let env = LaunchEnvironment.make(for: bottle(.d3dmetal, sync: false), wine: wine)
    check(env["WINEMSYNC"] == nil, "sync disabled => no WINEMSYNC")
}
do {
    var b = bottle(.d3dmetal)
    b.extraEnvironment = ["ROSETTA_ADVERTISE_AVX": "0", "MY_VAR": "42"]
    let env = LaunchEnvironment.make(for: b, wine: wine)
    check(env["ROSETTA_ADVERTISE_AVX"] == "0", "user override wins")
    check(env["MY_VAR"] == "42", "extra env passed through")
}

print("\nPerformanceProfile:")
do {
    var b = bottle(.d3dmetal); b.performance = .balanced
    let env = LaunchEnvironment.make(for: b, wine: wine)
    check(env["WINEDEBUG"] == "-all", "balanced silences WINEDEBUG")
    check(env["MTL_HUD_ENABLED"] == nil, "balanced keeps HUD off")
    check(env["MTL_SHADER_CACHE_PATH"]?.hasSuffix("cache/shaders") == true, "d3dmetal shader cache path set")
    check(env["MTL_PREFER_HIGH_POWER_GPU"] == "1", "prefers high-power GPU")
}
do {
    var b = bottle(.d3dmetal); b.performance = .turbo
    let env = LaunchEnvironment.make(for: b, wine: wine)
    check(env["MTL_HUD_ENABLED"] == "1", "turbo enables Metal HUD")
}
do {
    var b = bottle(.dxvk); b.performance = .balanced
    let env = LaunchEnvironment.make(for: b, wine: wine)
    check(env["DXVK_STATE_CACHE"] == "1", "dxvk state cache on")
    check(env["DXVK_ASYNC"] == "1", "dxvk async on")
    check(env["MVK_CONFIG_FAST_MATH_ENABLED"] == "1", "MoltenVK fast math on (dxvk)")
}

print("\nDLLInstaller:")
do {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("gbtest-\(UUID().uuidString)")
    let src64 = tmp.appendingPathComponent("src/x86_64-windows")
    let prefix = tmp.appendingPathComponent("prefix")
    try fm.createDirectory(at: src64, withIntermediateDirectories: true)
    for name in ["d3d11.dll", "d3d12.dll", "dxgi.dll", "readme.txt"] {
        fm.createFile(atPath: src64.appendingPathComponent(name).path, contents: Data("x".utf8))
    }
    var b = Bottle(name: "t", prefixPath: prefix, architecture: .win64, graphicsBackend: .d3dmetal)
    let installer = DLLInstaller(sources: .init(d3dmetal: tmp.appendingPathComponent("src")))
    let installed = try installer.install(.d3dmetal, into: b)
    check(Set(installed) == ["d3d11", "d3d12", "dxgi"], "installs 3 d3d dlls (skips .txt)")
    let dest = prefix.appendingPathComponent("drive_c/windows/system32/d3d11.dll")
    check(fm.fileExists(atPath: dest.path), "dll copied into system32")
    b.graphicsBackend = .wined3d
    check(try installer.install(.wined3d, into: b).isEmpty, "wined3d installs nothing")
    try? fm.removeItem(at: tmp)
}
do {
    // Installed-DLL list drives overrides (DXMT set, no d3d12).
    var b = bottle(.d3dmetal)
    b.installedGraphicsDLLs = ["d3d10core", "d3d11", "dxgi", "winemetal"]
    let env = LaunchEnvironment.make(for: b, wine: wine)
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(ov.contains("winemetal=n,b") && ov.contains("d3d10core=n,b"),
          "overrides use installed DXMT DLLs (prefix-wide policy)")
    check(!ov.contains("d3d12"), "no d3d12 override when DXMT installed")
}

print("\nSteamProvisioner:")
do {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("gbsteam-\(UUID().uuidString)")
    let prefix = tmp.appendingPathComponent("CS2")
    let b = Bottle(name: "CS2", prefixPath: prefix, architecture: .win64, graphicsBackend: .d3dmetal)
    let steam = SteamProvisioner(launcher: GameLauncher(wine: wine))

    check(SteamProvisioner.isInstalled(in: b) == false, "fresh bottle: Steam not installed")
    check(SteamProvisioner.installedSteamExe(in: b) == nil, "no steam.exe before install")
    check(SteamProvisioner.installerPath(in: b).path.hasSuffix("CS2/cache/SteamSetup.exe"),
          "installer caches under the bottle")

    // Simulate an installed Steam and re-check detection.
    let steamDir = prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam")
    try fm.createDirectory(at: steamDir, withIntermediateDirectories: true)
    fm.createFile(atPath: steamDir.appendingPathComponent("steam.exe").path, contents: Data("x".utf8))
    check(SteamProvisioner.isInstalled(in: b), "detects installed steam.exe")

    let cmd = steam.describePlay(appID: SteamApp.cs2, in: b)
    check(cmd.contains("-applaunch") && cmd.contains("730"), "play CS2 builds -applaunch 730")
    check(cmd.contains("WINEMSYNC=1"), "play command carries the perf env")
    check(SteamApp.cs2 == 730 && SteamApp.gtaV == 271590, "known app IDs")
    check(SteamProvisioner.installerURL.absoluteString.hasSuffix("SteamSetup.exe"),
          "installer URL points at SteamSetup.exe")
    try? fm.removeItem(at: tmp)
}

print("\nDXMTInstaller (pure helpers):")
do {
    // Fixture mimicking the real 3Shain/dxmt latest-release JSON.
    let json = """
    {"tag_name":"v0.80","assets":[
      {"name":"dxmt-v0.80-builtin.tar.gz","browser_download_url":"https://example/dxmt-v0.80-builtin.tar.gz"},
      {"name":"source.zip","browser_download_url":"https://example/source.zip"}
    ]}
    """.data(using: .utf8)!
    let picked = try DXMTInstaller.pickAsset(fromReleaseJSON: json)
    check(picked.tag == "v0.80", "parses tag v0.80")
    check(picked.url.absoluteString.contains("builtin.tar.gz"), "prefers the builtin tarball")

    // topLevelDir: single wrapping dir case.
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("dxmttop-\(UUID().uuidString)")
    let inner = root.appendingPathComponent("v0.80/x86_64-windows")
    try fm.createDirectory(at: inner, withIntermediateDirectories: true)
    let top = try DXMTInstaller.topLevelDir(in: root)
    check(top.lastPathComponent == "v0.80", "finds wrapping dir v0.80")

    // topLevelDir: contents extracted directly (no wrapper).
    let flat = fm.temporaryDirectory.appendingPathComponent("dxmtflat-\(UUID().uuidString)")
    try fm.createDirectory(at: flat.appendingPathComponent("x86_64-windows"), withIntermediateDirectories: true)
    check((try DXMTInstaller.topLevelDir(in: flat)).lastPathComponent == flat.lastPathComponent,
          "handles archive with no wrapping dir")

    let inst = DXMTInstaller(supportDir: URL(fileURLWithPath: "/tmp/MacStrike"))
    check(inst.dllDestination.path.hasSuffix("MacStrike/dlls/d3dmetal"), "dll destination path")
    try? fm.removeItem(at: root); try? fm.removeItem(at: flat)
}

print("\nSteamConfig (overlay off):")
do {
    let on = "\t\t\t\t\"EnableGameOverlay\"\t\t\"1\"\n"
    let r = SteamConfig.disableOverlayInVDF(on)
    check(r.changed && r.text.contains("\"EnableGameOverlay\"\t\t\"0\""), "flips EnableGameOverlay 1 -> 0")
    let off = "\t\"EnableGameOverlay\"\t\t\"0\"\n"
    check(!SteamConfig.disableOverlayInVDF(off).changed, "already off => no change")
    let none = "\"SomethingElse\" \"1\""
    check(!SteamConfig.disableOverlayInVDF(none).changed, "no overlay key => no change")
}

print("\nSourceTweaks:")
do {
    let cfg = SourceTweaks.autoexecContents(.init(audioMixahead: 0.2, fpsMax: 144))
    check(cfg.contains("snd_mixahead \"0.2\""), "autoexec sets snd_mixahead")
    check(cfg.contains("fps_max \"144\""), "autoexec sets fps_max")
    check(cfg.contains("[MacStrike] autoexec loaded"), "autoexec has the marker echo")
    let noCap = SourceTweaks.autoexecContents(.init(audioMixahead: 0.1, fpsMax: nil))
    check(!noCap.contains("fps_max"), "no fps_max line when uncapped")
    check(SourceTweaks.isKnownSourceGame(SteamApp.cs2), "CS2 is a known Source game")
    check(!SourceTweaks.isKnownSourceGame(SteamApp.gtaV), "GTA V is not treated as Source")

    // writeAutoexec into a simulated install.
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("st-\(UUID().uuidString)")
    let b = Bottle(name: "CS2", prefixPath: tmp, graphicsBackend: .d3dmetal)
    let cfgDir = tmp.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/game/csgo/cfg")
    check((try? SourceTweaks.writeAutoexec(for: SteamApp.cs2, in: b)) as? URL == nil,
          "no cfg dir yet => nothing written")
    try fm.createDirectory(at: cfgDir, withIntermediateDirectories: true)
    let written = try SourceTweaks.writeAutoexec(for: SteamApp.cs2, in: b)
    check(written != nil && fm.fileExists(atPath: written!.path), "autoexec.cfg written when game installed")
    try? fm.removeItem(at: tmp)
}

print("\nLicenseManager (pure parsing):")
do {
    // Gumroad: valid purchase.
    let ok = #"{"success":true,"uses":1,"purchase":{"email":"a@b.com","refunded":false,"disputed":false,"chargebacked":false}}"#.data(using: .utf8)!
    let lic = try LicenseManager.parse(ok, provider: .gumroad(permalink: "p"), key: "ABC-123")
    check(lic.key == "ABC-123" && lic.email == "a@b.com", "gumroad valid key parses")

    // Gumroad: refunded -> rejected.
    let refunded = #"{"success":true,"purchase":{"refunded":true}}"#.data(using: .utf8)!
    var threw = false
    do { _ = try LicenseManager.parse(refunded, provider: .gumroad(permalink: "p"), key: "X") }
    catch { threw = true }
    check(threw, "gumroad refunded purchase rejected")

    // Gumroad: not found -> rejected.
    let bad = #"{"success":false,"message":"That license does not exist."}"#.data(using: .utf8)!
    threw = false
    do { _ = try LicenseManager.parse(bad, provider: .gumroad(permalink: "p"), key: "X") }
    catch { threw = true }
    check(threw, "gumroad unknown key rejected")

    // Lemon Squeezy: activated.
    let ls = #"{"activated":true,"instance":{"id":"inst_1"},"meta":{"customer_email":"c@d.com"}}"#.data(using: .utf8)!
    let lic2 = try LicenseManager.parse(ls, provider: .lemonSqueezy, key: "LS-1")
    check(lic2.instanceID == "inst_1" && lic2.email == "c@d.com", "lemonsqueezy activation parses")

    // Config gating.
    let unset = LicenseConfig(provider: .gumroad(permalink: "REPLACE_WITH_YOUR_GUMROAD_PRODUCT_ID"))
    check(!unset.isConfigured, "placeholder product id => not configured")
    check(LicenseConfig(provider: .lemonSqueezy).isConfigured, "lemonsqueezy is always configured")

    // Persistence round-trip + offline grace.
    let fm = FileManager.default
    let path = fm.temporaryDirectory.appendingPathComponent("lic-\(UUID().uuidString).json")
    let mgr = LicenseManager(config: LicenseConfig(provider: .lemonSqueezy), storageURL: path)
    check(mgr.cachedStatus() == .unlicensed, "no file => unlicensed")
    let now = Date()
    let saved = License(key: "K", email: nil, instanceID: nil, activatedAt: now, lastValidated: now)
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    try enc.encode(saved).write(to: path)
    check(mgr.cachedStatus().isPro, "cached license => Pro")
    mgr.deactivate()
    check(mgr.cached() == nil, "deactivate clears the license")
}

print("\nTrial:")
do {
    let len: TimeInterval = 60 * 60 * 24 * 7
    let start = Date()
    check(LicenseManager.trialDaysLeft(startedAt: start, now: start, length: len) == 7, "fresh trial = 7 days")
    let day3 = start.addingTimeInterval(60 * 60 * 24 * 3)
    check(LicenseManager.trialDaysLeft(startedAt: start, now: day3, length: len) == 4, "after 3 days = 4 left")
    let after = start.addingTimeInterval(len + 1)
    check(LicenseManager.trialDaysLeft(startedAt: start, now: after, length: len) == 0, "expired = 0")

    // entitlement flow on a configured build (lemonSqueezy is always configured).
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("ent-\(UUID().uuidString)")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let m = LicenseManager(config: LicenseConfig(provider: .lemonSqueezy),
                           storageURL: dir.appendingPathComponent("license.json"))
    let e = m.entitlement()
    check(e.hasPro, "first run: trial grants Pro")
    if case .trial(let d) = e { check(d == 7, "first run shows 7-day trial") } else { check(false, "first run is a trial") }
    check(m.trial() != nil, "trial persisted on first entitlement check")

    // community build (unconfigured) => always Pro, no trial file.
    let m2 = LicenseManager(config: LicenseConfig(provider: .gumroad(permalink: "REPLACE_WITH_YOUR_GUMROAD_PRODUCT_ID")),
                            storageURL: dir.appendingPathComponent("license2.json"))
    check(m2.entitlement() == .community && m2.entitlement().hasPro, "unconfigured build is community (all open)")
    try? fm.removeItem(at: dir)
}

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

print("ProcessDetection / launch targets:")
do {
    // launchd is always running on macOS — a reliable positive control.
    check(ProcessDetection.isRunning("launchd"), "detects a process that is running")
    check(!ProcessDetection.isRunning("macstrike-no-such-process-xyz"),
          "reports a bogus process name as not running")

    check(GameCatalog.cs2.processName == "cs2.exe", "cs2 launch target is cs2.exe")
    check(GameCatalog.gtaV.processName == "GTA5.exe", "GTA V launch target is GTA5.exe")

    let custom = Game.custom(name: "Thing", exePath: "/games/Thing/thing.exe")
    check(custom.processName == "thing.exe", "a custom game watches its own exe name")

    check(SteamProcess.client == "steam.exe", "the Steam client process name")
}

print("Per-application DLL overrides:")
do {
    // Graphics translation DLLs must apply to the GAME only. Imposing them on the
    // whole prefix makes the Steam client load a translation d3d11/dxgi it never
    // asked for, and its CEF UI process dies — a black Steam window.
    let dlls = ["d3d11", "dxgi", "winemetal"]

    let reg = DllOverridePolicy.registryScript(for: "cs2.exe", dlls: dlls) ?? ""
    check(reg.contains(#"[Software\\Wine\\AppDefaults\\cs2.exe\\DllOverrides]"#),
          "writes under AppDefaults for the target exe")
    check(reg.contains("\"d3d11\"=\"native,builtin\""), "d3d11 is native-first for the game")
    check(reg.contains("\"dxgi\"=\"native,builtin\""), "dxgi is native-first for the game")
    check(reg.hasPrefix("REGEDIT4"), "is a valid .reg script")

    // A game with no translation DLLs installed yields no script.
    check(DllOverridePolicy.registryScript(for: "cs2.exe", dlls: []) == nil,
          "no DLLs means no registry script")

    // The launch environment must NOT carry graphics overrides when the policy
    // is per-app: that is the whole point.
    let b = Bottle(name: "CS2", prefixPath: URL(fileURLWithPath: "/tmp/b/CS2"),
                   graphicsBackend: .d3dmetal,
                   overridePolicy: .perApplication,
                   installedGraphicsDLLs: dlls)
    let env = LaunchEnvironment.make(for: b, wine: WineInstallation(root: URL(fileURLWithPath: "/opt/w")))
    check(env["WINEDLLOVERRIDES"] == nil,
          "per-app policy keeps graphics DLLs out of WINEDLLOVERRIDES")

    // The legacy prefix-wide policy still works, for bottles that want it.
    var wide = b
    wide.overridePolicy = .prefixWide
    let envWide = LaunchEnvironment.make(for: wide, wine: WineInstallation(root: URL(fileURLWithPath: "/opt/w")))
    check((envWide["WINEDLLOVERRIDES"] ?? "").contains("d3d11=n,b"),
          "prefix-wide policy still emits WINEDLLOVERRIDES")

    // Overlay blocking is a launch-time concern and stays in the environment.
    var overlay = b
    overlay.disableSteamOverlay = true
    let envOverlay = LaunchEnvironment.make(for: overlay, wine: WineInstallation(root: URL(fileURLWithPath: "/opt/w")))
    check((envOverlay["WINEDLLOVERRIDES"] ?? "").contains("gameoverlayrenderer="),
          "overlay blocking still applies under the per-app policy")
    check(!(envOverlay["WINEDLLOVERRIDES"] ?? "").contains("d3d11"),
          "...without dragging the graphics DLLs back in")

    check(Bottle(name: "x", prefixPath: URL(fileURLWithPath: "/t")).overridePolicy == .perApplication,
          "new bottles default to the per-app policy")
}

print("GStreamer dependency:")
do {
    // Wine's mfplat needs GStreamer with an H.264 decoder. Without it, the Steam
    // client's CEF helper takes an access violation and dies — a black window.
    // Verified on 2026-10-16: installing GStreamer 1.28.8 provides avdec_h264.
    check(GStreamerDependency.frameworkPath.path == "/Library/Frameworks/GStreamer.framework",
          "looks for the framework in /Library/Frameworks")
    check(GStreamerDependency.inspectTool.lastPathComponent == "gst-inspect-1.0",
          "uses gst-inspect-1.0 to probe plugins")

    // Stable releases have an even minor version; 1.29.x is a dev series.
    check(GStreamerDependency.isStableVersion("1.28.8"), "1.28.8 is stable")
    check(!GStreamerDependency.isStableVersion("1.29.2"), "1.29.2 (odd minor) is not stable")
    check(!GStreamerDependency.isStableVersion("nonsense"), "garbage is not a stable version")

    let url = GStreamerDependency.packageURL(version: "1.28.8")
    check(url.absoluteString
            == "https://gstreamer.freedesktop.org/data/pkg/osx/1.28.8/gstreamer-1.0-1.28.8-universal.pkg",
          "builds the official universal package URL")
    check(url.host == "gstreamer.freedesktop.org", "downloads only from the official host")

    // Parsing the directory index picks the newest STABLE version.
    let index = """
    <a href="1.26.0/">1.26.0/</a> <a href="1.28.7/">1.28.7/</a>
    <a href="1.28.8/">1.28.8/</a> <a href="1.29.2/">1.29.2/</a>
    """
    check(GStreamerDependency.latestStableVersion(fromIndex: index) == "1.28.8",
          "picks the newest stable, skipping the 1.29 dev series")
    check(GStreamerDependency.latestStableVersion(fromIndex: "no versions here") == nil,
          "an index with no versions yields nil")

    // The privileged install must go through macOS's own auth dialog.
    let script = GStreamerDependency.installAppleScript(pkgPath: "/tmp/g.pkg")
    check(script.contains("with administrator privileges"),
          "asks for rights via the native macOS prompt")
    check(script.contains("/tmp/g.pkg"), "installs the downloaded package")
}

print("")
if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
