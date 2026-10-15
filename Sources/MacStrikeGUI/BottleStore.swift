import Foundation
import Combine
import BottleEngine

/// Observable app state + the bridge to BottleEngine. Long operations (downloads,
/// Wine runs) execute off the main thread and stream into `log`.
@MainActor
final class BottleStore: ObservableObject {
    @Published var bottles: [Bottle] = []
    @Published var busy = false
    @Published var busyLabel = ""
    @Published var log = ""
    @Published var lastError: String?

    let supportDir: URL
    let bottlesRoot: URL
    @Published var wine: WineInstallation

    init() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacStrike")
        self.supportDir = support
        self.bottlesRoot = support.appendingPathComponent("Bottles")
        self.wine = WineInstallation(root: support.appendingPathComponent("wine"))
        try? FileManager.default.createDirectory(at: bottlesRoot, withIntermediateDirectories: true)
        reload()
    }

    var manager: BottleManager { BottleManager(wine: wine) }
    var launcher: GameLauncher { GameLauncher(wine: wine) }
    var dxmtDLLDir: URL { supportDir.appendingPathComponent("dlls/d3dmetal") }
    var wineReady: Bool { wine.isUsable }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: bottlesRoot, includingPropertiesForKeys: nil)) ?? []
        bottles = dirs.compactMap { try? manager.load(prefixPath: $0) }.sorted { $0.name < $1.name }
    }

    func bottle(_ id: Bottle.ID?) -> Bottle? { bottles.first { $0.id == id } }

    private func logLine(_ s: String) { log += s + "\n" }

    /// Run `work` in the background with a busy indicator; `work` may emit log lines.
    private func run(_ label: String, _ work: @escaping @Sendable (@escaping @Sendable (String) -> Void) throws -> Void) {
        busy = true; busyLabel = label; logLine("▶ \(label)")
        Task.detached {
            do {
                try work { line in Task { @MainActor in self.logLine("  " + line) } }
                await MainActor.run { self.logLine("✓ \(label)"); self.finish() }
            } catch {
                await MainActor.run { self.lastError = "\(error)"; self.logLine("✗ \(error)"); self.finish() }
            }
        }
    }
    private func finish() { busy = false; busyLabel = ""; reload() }

    // MARK: - Actions

    func create(name: String, backend: GraphicsBackend, turbo: Bool) {
        let prefix = bottlesRoot.appendingPathComponent(name)
        let bottle = Bottle(name: name, prefixPath: prefix, graphicsBackend: backend,
                            performance: turbo ? .turbo : .balanced)
        let mgr = manager, usable = wine.isUsable
        run("Create bottle “\(name)”") { _ in
            try mgr.createBottle(bottle, runWineboot: usable)
        }
    }

    func fetchDXMT() {
        let installer = DXMTInstaller(supportDir: supportDir, wine: wine)
        run("Download DXMT") { emit in
            let r = try installer.install { emit($0) }
            emit("DXMT \(r.tag) ready at \(r.dllDir.lastPathComponent)")
        }
    }

    func installGraphics(_ bottle: Bottle) {
        let mgr = manager, dir = dxmtDLLDir
        run("Install graphics DLLs → \(bottle.name)") { emit in
            var b = bottle
            var sources = DLLInstaller.Sources()
            switch b.graphicsBackend {
            case .d3dmetal: sources.d3dmetal = dir
            case .dxvk:     sources.dxvk = dir
            case .wined3d:  emit("wined3d: nothing to install"); return
            }
            let installed = try DLLInstaller(sources: sources).install(b.graphicsBackend, into: b)
            b.installedGraphicsDLLs = installed
            try mgr.save(b)
            emit("Installed: \(installed.joined(separator: ", "))")
        }
    }

    func steamInstall(_ bottle: Bottle) {
        let steam = SteamProvisioner(launcher: launcher)
        run("Install Steam → \(bottle.name)") { emit in
            emit("Downloading SteamSetup.exe…")
            let p = try steam.install(into: bottle, silent: true)
            p.waitUntilExit()
            emit(SteamProvisioner.isInstalled(in: bottle) ? "Steam installed." : "Installer exit \(p.terminationStatus)")
        }
    }

    func steamRun(_ bottle: Bottle) {
        let steam = SteamProvisioner(launcher: launcher)
        run("Launch Steam → \(bottle.name)") { _ in _ = try steam.launchSteam(in: bottle) }
    }

    func steamPlay(_ bottle: Bottle, appID: Int) {
        let steam = SteamProvisioner(launcher: launcher)
        run("Play \(appID) → \(bottle.name)") { _ in _ = try steam.play(appID: appID, in: bottle) }
    }

    func launch(_ bottle: Bottle, exePath: String) {
        let l = launcher
        run("Run \(URL(fileURLWithPath: exePath).lastPathComponent)") { _ in
            _ = try l.launch(bottle: bottle, exePath: exePath)
        }
    }

    func launchCommand(_ bottle: Bottle, exePath: String) -> String {
        launcher.describeCommand(bottle: bottle, exePath: exePath)
    }

    func steamInstalled(_ bottle: Bottle) -> Bool { SteamProvisioner.isInstalled(in: bottle) }
    func dxmtInstalled() -> Bool {
        FileManager.default.fileExists(atPath: dxmtDLLDir.appendingPathComponent("x86_64-windows").path)
    }
}
