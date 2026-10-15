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
func bottle(_ backend: GraphicsBackend, sync: Bool = true) -> Bottle {
    Bottle(name: "test",
           prefixPath: URL(fileURLWithPath: "/tmp/bottles/test"),
           architecture: .win64,
           graphicsBackend: backend,
           synchronizationEnabled: sync)
}

print("LaunchEnvironment recipe:")
do {
    let env = LaunchEnvironment.make(for: bottle(.d3dmetal), wine: wine)
    check(env["WINEPREFIX"] == "/tmp/bottles/test", "WINEPREFIX is set")
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(ov.contains("d3d11=n,b") && ov.contains("d3d12=n,b") && ov.contains("dxgi=n,b"),
          "d3dmetal overrides d3d11/d3d12/dxgi")
    check(env["WINEMSYNC"] == "1", "sync maps to WINEMSYNC=1")
    check(env["ROSETTA_ADVERTISE_AVX"] == "1", "advertises AVX under Rosetta")
    check(env["DOTNET_EnableWriteXorExecute"] == "0", ".NET W^X fixup")
    check(env["WINELOADER"] == "/opt/gamebottle/wine/bin/wine", "WINELOADER path")
    check(env["WINESERVER"] == "/opt/gamebottle/wine/bin/wineserver", "WINESERVER path")
}
do {
    let env = LaunchEnvironment.make(for: bottle(.dxvk), wine: wine)
    let ov = env["WINEDLLOVERRIDES"] ?? ""
    check(ov.contains("d3d11=n,b") && ov.contains("dxgi=n,b"), "dxvk overrides d3d/dxgi")
}
do {
    let env = LaunchEnvironment.make(for: bottle(.wined3d), wine: wine)
    check(env["WINEDLLOVERRIDES"] == nil, "wined3d has no DLL overrides")
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
    check(ov.contains("winemetal=n,b") && ov.contains("d3d10core=n,b"), "overrides use installed DXMT DLLs")
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

print("")
if failures == 0 {
    print("All checks passed.")
    exit(0)
} else {
    print("\(failures) check(s) failed.")
    exit(1)
}
