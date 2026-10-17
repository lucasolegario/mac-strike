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
                emit("Creating bottle “\(bottle.name)”…")
                _ = try mgr.createBottle(bottle, runWineboot: wineUsable)
            }
            return true

        case .fetchDXMT:
            let installer = model.dxmtInstaller
            try await run { emit in
                let r = try installer.install { emit($0) }
                emit("DXMT \(r.tag) ready.")
            }
            return true

        case .installGraphics:
            let mgr = model.manager
            let dir = model.dxmtDLLDir
            let bottle = model.bottle(for: game)
            try await run { emit in
                var b = bottle
                var sources = DLLInstaller.Sources()
                switch b.graphicsBackend {
                case .d3dmetal: sources.d3dmetal = dir
                case .dxvk:     sources.dxvk = dir
                case .wined3d:  emit("wined3d: nothing to install"); return
                }
                let installed = try DLLInstaller(sources: sources)
                    .install(b.graphicsBackend, into: b)
                b.installedGraphicsDLLs = installed
                try mgr.save(b)
                emit("Installed: \(installed.joined(separator: ", "))")
            }
            return true

        case .installSteam:
            let steam = model.steam
            let bottle = model.bottle(for: game)
            try await run { emit in
                emit("Downloading SteamSetup.exe…")
                let p = try steam.install(into: bottle, silent: true)
                p.waitUntilExit()
                emit(SteamProvisioner.isInstalled(in: bottle)
                     ? "Steam installed."
                     : "Installer exited \(p.terminationStatus)")
            }
            return true

        case .installGame(let appID):
            // Steam owns this download. Open it, then watch for the game.
            let steam = model.steam
            let bottle = model.bottle(for: game)
            try await run { emit in
                emit("Opening Steam to install the game…")
                _ = try steam.play(appID: appID, in: bottle)
            }
            phase = .waitingForSteam
            emit("Waiting for the Steam install to finish…")
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
                emit("✓ Game detected.")
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
