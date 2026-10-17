import Foundation

/// How a bottle's graphics-translation DLL overrides get applied.
///
/// This exists because of a concrete failure: translation DLLs (DXMT's `d3d11`,
/// `dxgi`, `winemetal`, …) belong to the **game**. Imposing them prefix-wide
/// through `WINEDLLOVERRIDES` also forces them on every other Windows process
/// in the bottle — including the Steam client, whose CEF UI process loads
/// `d3d11`/`dxgi` and then dies, leaving a black Steam window.
///
/// Measured on a clean bottle: with prefix-wide overrides the Steam client died
/// after ~5s; without them it completed its 241 MB self-update and started
/// normally.
public enum DllOverridePolicy: String, Codable, Sendable {
    /// Register the overrides for the game executable only, via
    /// `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides`. The default.
    case perApplication
    /// Put them in `WINEDLLOVERRIDES`, applying to the whole prefix.
    /// Kept for bottles that need it, and for single-process games.
    case prefixWide

    /// A `.reg` script registering `dlls` as native-first for `exe` only.
    ///
    /// Returns nil when there is nothing to register. Apply it with
    /// `wine regedit <file>`.
    public static func registryScript(for exe: String, dlls: [String]) -> String? {
        guard !dlls.isEmpty else { return nil }
        var lines = [
            "REGEDIT4",
            "",
            "; MacStrike — graphics translation DLLs for this game only.",
            "; Scoped per-application so other processes in the bottle (notably",
            "; the Steam client and its CEF helper) keep Wine's builtin DLLs.",
            "[Software\\\\Wine\\\\AppDefaults\\\\\(exe)\\\\DllOverrides]",
        ]
        for dll in dlls {
            lines.append("\"\(dll)\"=\"native,builtin\"")
        }
        lines.append("")
        return lines.joined(separator: "\r\n")
    }
}
