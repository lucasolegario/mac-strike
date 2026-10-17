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
    /// The Windows process to watch for when launching, e.g. "cs2.exe".
    /// Lets the GUI report "waiting for the game" honestly instead of guessing.
    public let processName: String?

    public init(
        id: String,
        name: String,
        bottleName: String,
        steamAppID: Int?,
        backend: GraphicsBackend = .d3dmetal,
        accentFrom: String,
        accentTo: String,
        supported: Bool = true,
        exePath: String? = nil,
        processName: String? = nil
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
        self.processName = processName
    }

    /// A user-added game backed by a bare `.exe`. Runs in a shared "Custom" bottle.
    public static func custom(name: String, exePath: String) -> Game {
        Game(id: "custom:\(name)",
             name: name,
             bottleName: "Custom",
             steamAppID: nil,
             accentFrom: "#3A3F55",
             accentTo: "#22263A",
             exePath: exePath,
             processName: URL(fileURLWithPath: exePath).lastPathComponent)
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
        accentTo: "#14203A",
        processName: "cs2.exe")

    /// Placeholder — not supported yet, shown as "em breve".
    public static let gtaV = Game(
        id: "gtav",
        name: "Grand Theft Auto V",
        bottleName: "GTAV",
        steamAppID: SteamApp.gtaV,
        accentFrom: "#6B5A24",
        accentTo: "#3F3016",
        supported: false,
        processName: "GTA5.exe")

    public static let builtins: [Game] = [cs2, gtaV]

    public static func game(id: String) -> Game? {
        builtins.first { $0.id == id }
    }
}
