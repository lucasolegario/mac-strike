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
