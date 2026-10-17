import Foundation

/// A Wine prefix plus the configuration needed to run Windows games in it.
/// Persisted as JSON (`bottle.json`) at the prefix root.
public struct Bottle: Codable, Sendable, Identifiable {
    public enum Architecture: String, Codable, Sendable {
        case win32
        case win64
    }

    public var id: UUID
    public var name: String
    /// Absolute path to the WINEPREFIX directory.
    public var prefixPath: URL
    public var architecture: Architecture
    /// Reported Windows version (maps to Wine's `winver`), e.g. "win10".
    public var windowsVersion: String
    public var graphicsBackend: GraphicsBackend
    /// Fast synchronization (emitted as WINEMSYNC at launch) — the big FPS win.
    public var synchronizationEnabled: Bool
    /// Performance tunables (shader cache, async, HUD, …).
    public var performance: PerformanceProfile
    /// Block the Steam in-game overlay by disabling its injected DLL. Saves a
    /// little CPU, but ⚠️ tampering with the overlay DLL can trip anti-cheat (VAC),
    /// so this is OFF by default and should stay off for VAC-protected games.
    public var disableSteamOverlay: Bool
    /// DLL base names actually installed by `install-graphics` (e.g. d3d11, dxgi,
    /// winemetal). When set, these drive `WINEDLLOVERRIDES` instead of the
    /// backend's nominal list — DXMT and Apple GPTK ship different DLL sets.
    public var installedGraphicsDLLs: [String]
    /// How the graphics-translation DLL overrides are applied. Per-application
    /// by default, so the Steam client is not forced to load them.
    public var overridePolicy: DllOverridePolicy
    /// Extra user-supplied environment overrides (highest precedence).
    public var extraEnvironment: [String: String]

    public init(
        id: UUID = UUID(),
        name: String,
        prefixPath: URL,
        architecture: Architecture = .win64,
        windowsVersion: String = "win10",
        graphicsBackend: GraphicsBackend = .d3dmetal,
        synchronizationEnabled: Bool = true,
        performance: PerformanceProfile = .balanced,
        disableSteamOverlay: Bool = false,
        overridePolicy: DllOverridePolicy = .perApplication,
        installedGraphicsDLLs: [String] = [],
        extraEnvironment: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.prefixPath = prefixPath
        self.architecture = architecture
        self.windowsVersion = windowsVersion
        self.graphicsBackend = graphicsBackend
        self.synchronizationEnabled = synchronizationEnabled
        self.performance = performance
        self.disableSteamOverlay = disableSteamOverlay
        self.overridePolicy = overridePolicy
        self.installedGraphicsDLLs = installedGraphicsDLLs
        self.extraEnvironment = extraEnvironment
    }

    /// Where the bottle's config lives on disk.
    public var configFileURL: URL {
        prefixPath.appendingPathComponent("bottle.json")
    }

    /// Persistent shader-cache directory inside the prefix.
    public var shaderCacheURL: URL {
        prefixPath.appendingPathComponent("cache/shaders")
    }

    // Forward-compatible decoding: newer fields default when absent from older
    // bottle.json files.
    enum CodingKeys: String, CodingKey {
        case id, name, prefixPath, architecture, windowsVersion
        case graphicsBackend, synchronizationEnabled, performance
        case disableSteamOverlay, overridePolicy, installedGraphicsDLLs, extraEnvironment
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        prefixPath = try c.decode(URL.self, forKey: .prefixPath)
        architecture = try c.decodeIfPresent(Architecture.self, forKey: .architecture) ?? .win64
        windowsVersion = try c.decodeIfPresent(String.self, forKey: .windowsVersion) ?? "win10"
        graphicsBackend = try c.decodeIfPresent(GraphicsBackend.self, forKey: .graphicsBackend) ?? .d3dmetal
        synchronizationEnabled = try c.decodeIfPresent(Bool.self, forKey: .synchronizationEnabled) ?? true
        performance = try c.decodeIfPresent(PerformanceProfile.self, forKey: .performance) ?? .balanced
        disableSteamOverlay = try c.decodeIfPresent(Bool.self, forKey: .disableSteamOverlay) ?? false
        overridePolicy = try c.decodeIfPresent(DllOverridePolicy.self, forKey: .overridePolicy) ?? .perApplication
        installedGraphicsDLLs = try c.decodeIfPresent([String].self, forKey: .installedGraphicsDLLs) ?? []
        extraEnvironment = try c.decodeIfPresent([String: String].self, forKey: .extraEnvironment) ?? [:]
    }
}
