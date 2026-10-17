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
