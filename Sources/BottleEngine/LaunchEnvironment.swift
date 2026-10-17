import Foundation

/// Builds the environment a bottle is launched with.
///
/// This assembles the variables Wine needs to run a Windows game with the right
/// graphics translation and performance settings. It is a pure function
/// (disk/Process-free) so it stays unit-testable.
public enum LaunchEnvironment {

    /// Assemble the environment dictionary for `bottle` on `wine`.
    ///
    /// Precedence (low -> high): engine paths, macOS/Rosetta fixups, DLL
    /// overrides, performance profile, the user's `extraEnvironment`.
    public static func make(for bottle: Bottle, wine: WineInstallation) -> [String: String] {
        var env: [String: String] = [:]

        // --- The WINEPREFIX itself -------------------------------------------
        env["WINEPREFIX"] = bottle.prefixPath.path

        // --- Fast synchronization --------------------------------------------
        // WINEMSYNC uses macOS Mach semaphores for Win32 sync primitives — the
        // big frame-rate win for games. Without it, threads fall back to slow
        // server-side waits.
        if bottle.synchronizationEnabled {
            env["WINEMSYNC"] = "1"
        }

        // --- Engine paths -----------------------------------------------------
        env["WINELOADER"] = wine.loader.path
        env["WINESERVER"] = wine.server.path
        let dllPath = wine.dllPath
        if !dllPath.isEmpty { env["WINEDLLPATH"] = dllPath }

        // --- macOS / Rosetta fixups ------------------------------------------
        // Advertise AVX under Rosetta 2 — modern games (and the Steam client)
        // check for it. On by default unless the user overrides it.
        env["ROSETTA_ADVERTISE_AVX"] = "1"
        // .NET 7/8 launchers crash under Rosetta without this.
        env["DOTNET_EnableWriteXorExecute"] = "0"

        // --- DLL overrides for the graphics backend ---------------------------
        // Force the game to load the backend's d3d/dxgi DLLs ("native, then
        // builtin") instead of Wine's wined3d. Prefer the DLLs actually installed
        // (DXMT vs Apple GPTK ship different sets); fall back to the nominal list.
        //
        // Only under the prefix-wide policy. The default is per-application: the
        // overrides are registered for the game executable alone, because forcing
        // a translation d3d11/dxgi on the Steam client kills its CEF UI process
        // (black Steam window). See DllOverridePolicy.
        var overrideParts: [String] = []
        if bottle.overridePolicy == .prefixWide {
            let overrides = bottle.installedGraphicsDLLs.isEmpty
                ? bottle.graphicsBackend.overriddenDLLs
                : bottle.installedGraphicsDLLs
            overrideParts = overrides.map { "\($0)=n,b" }
        }
        // Block the Steam overlay by disabling its injected DLL (empty override
        // = "do not load"). Removes the overlay's CPU cost under Wine.
        if bottle.disableSteamOverlay {
            overrideParts.append("gameoverlayrenderer64=")
            overrideParts.append("gameoverlayrenderer=")
        }
        if !overrideParts.isEmpty {
            env["WINEDLLOVERRIDES"] = overrideParts.joined(separator: ";")
        }

        // --- Performance profile (shader cache, async, HUD, GPU) -------------
        for (k, v) in bottle.performance.environment(
            backend: bottle.graphicsBackend, cacheDir: bottle.shaderCacheURL) {
            env[k] = v
        }

        // --- User overrides win -----------------------------------------------
        for (k, v) in bottle.extraEnvironment { env[k] = v }

        return env
    }
}
