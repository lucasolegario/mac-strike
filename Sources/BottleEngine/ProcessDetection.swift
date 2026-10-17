import Foundation

/// Well-known Windows process names that run inside a bottle.
public enum SteamProcess {
    /// The Steam client itself.
    public static let client = "steam.exe"
}

/// Checks whether a named process is currently running.
///
/// Launching a game is slow and indirect: MacStrike starts Wine, Wine starts
/// Steam, and Steam eventually starts the game. None of those hand back a
/// "ready" signal, so the only honest way to report progress is to watch for
/// the processes themselves to appear.
public enum ProcessDetection {

    /// Is a process whose command line contains `name` running?
    ///
    /// Uses `pgrep -f` so it matches Windows executables running under Wine,
    /// which appear in the command line rather than as the process name.
    public static func isRunning(_ name: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", name]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return false
        }
        p.waitUntilExit()
        // pgrep exits 0 when at least one process matched, 1 when none did.
        return p.terminationStatus == 0
    }
}
