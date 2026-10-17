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
