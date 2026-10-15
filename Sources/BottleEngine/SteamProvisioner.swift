import Foundation

/// Installs and drives the **Windows** Steam client *inside a bottle*.
/// Nothing here is native macOS: Steam and the games it installs are Windows
/// binaries running under Wine + the graphics translation layer.
public struct SteamProvisioner: Sendable {

    /// Official Steam Windows installer (small NSIS stub; it fetches the real
    /// client on first run).
    public static let installerURL = URL(string:
        "https://cdn.fastly.steamstatic.com/client/installer/SteamSetup.exe")!

    public let launcher: GameLauncher
    public init(launcher: GameLauncher) { self.launcher = launcher }

    // MARK: - Paths

    /// Candidate install locations (64-bit Windows puts 32-bit Steam under x86).
    public static func steamExeCandidates(in bottle: Bottle) -> [URL] {
        let c = bottle.prefixPath.appendingPathComponent("drive_c")
        return [
            c.appendingPathComponent("Program Files (x86)/Steam/steam.exe"),
            c.appendingPathComponent("Program Files/Steam/steam.exe"),
        ]
    }

    /// The Windows-side path Wine uses to launch Steam, or nil if not installed.
    public static func installedSteamExe(in bottle: Bottle) -> URL? {
        steamExeCandidates(in: bottle).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func isInstalled(in bottle: Bottle) -> Bool {
        installedSteamExe(in: bottle) != nil
    }

    /// Where we cache the downloaded installer inside the bottle.
    public static func installerPath(in bottle: Bottle) -> URL {
        bottle.prefixPath.appendingPathComponent("cache/SteamSetup.exe")
    }

    // MARK: - Download

    public enum SteamError: Error, CustomStringConvertible {
        case downloadFailed(String)
        case notInstalled
        public var description: String {
            switch self {
            case .downloadFailed(let m): return "Failed to download SteamSetup.exe: \(m)"
            case .notInstalled: return "Steam is not installed in this bottle yet (run `steam install`)."
            }
        }
    }

    /// Download the installer into the bottle cache if not already present.
    @discardableResult
    public func downloadInstaller(into bottle: Bottle, force: Bool = false) throws -> URL {
        let dst = Self.installerPath(in: bottle)
        if !force, FileManager.default.fileExists(atPath: dst.path) { return dst }
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sem = DispatchSemaphore(value: 0)
        var resultError: String?
        var tempURL: URL?
        let task = URLSession.shared.downloadTask(with: Self.installerURL) { url, response, error in
            if let error { resultError = error.localizedDescription }
            else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                resultError = "HTTP \(http.statusCode)"
            } else { tempURL = url }
            sem.signal()
        }
        task.resume()
        sem.wait()

        if let resultError { throw SteamError.downloadFailed(resultError) }
        guard let tempURL else { throw SteamError.downloadFailed("no file returned") }
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tempURL, to: dst)
        return dst
    }

    // MARK: - Actions

    /// Download (if needed) and run the installer. `/S` does a silent NSIS install.
    @discardableResult
    public func install(into bottle: Bottle, silent: Bool = true) throws -> Process {
        let installer = try downloadInstaller(into: bottle)
        let args = silent ? ["/S"] : []
        return try launcher.launch(bottle: bottle, exePath: installer.path, arguments: args)
    }

    /// Launch the installed Steam client.
    @discardableResult
    public func launchSteam(in bottle: Bottle) throws -> Process {
        guard let exe = Self.installedSteamExe(in: bottle) else { throw SteamError.notInstalled }
        return try launcher.launch(bottle: bottle, exePath: exe.path, arguments: Self.cefWorkaroundArgs)
    }

    /// Steam renders its UI with CEF (embedded Chromium). Its GPU compositing path
    /// breaks under Wine and shows a **black window**. These flags disable it — a
    /// common Wine workaround. Not a game-render issue.
    public static let cefWorkaroundArgs = [
        "-cef-disable-gpu",
        "-cef-disable-gpu-compositing",
        "-no-cef-sandbox",
    ]

    /// Launch a Steam game by app ID (CS2 = 730) via `steam.exe -applaunch <id>`.
    ///
    /// For known Source games, this also writes an `autoexec.cfg` with the audio/
    /// FPS tweaks and passes `+exec autoexec` so they load on start. Pass
    /// `tweaks: nil` to skip that.
    @discardableResult
    public func play(appID: Int, in bottle: Bottle,
                     tweaks: SourceTweaks.Settings? = SourceTweaks.Settings()) throws -> Process {
        guard let exe = Self.installedSteamExe(in: bottle) else { throw SteamError.notInstalled }
        var gameArgs = ["-applaunch", String(appID)]
        if let tweaks, SourceTweaks.isKnownSourceGame(appID) {
            _ = try? SourceTweaks.writeAutoexec(for: appID, in: bottle, settings: tweaks)
            gameArgs += ["+exec", "autoexec"]
        }
        return try launcher.launch(bottle: bottle, exePath: exe.path,
                                   arguments: Self.cefWorkaroundArgs + gameArgs)
    }

    /// The shell-equivalent command to play an app ID (for logging / dry runs).
    public func describePlay(appID: Int, in bottle: Bottle) -> String {
        let exe = Self.installedSteamExe(in: bottle)?.path
            ?? Self.steamExeCandidates(in: bottle)[0].path
        return launcher.describeCommand(bottle: bottle, exePath: exe,
                                        arguments: Self.cefWorkaroundArgs + ["-applaunch", String(appID)])
    }
}

/// Well-known Steam app IDs for convenience.
public enum SteamApp {
    public static let cs2 = 730
    public static let gtaV = 271590
}
