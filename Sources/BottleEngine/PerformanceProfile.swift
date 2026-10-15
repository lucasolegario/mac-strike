import Foundation

/// Tunables that affect in-game performance. These are the knobs that decide
/// how close you get to native performance.
///
/// Honest notes:
///  - `msync` is the single biggest win and is on by default.
///  - Shader caching avoids recompile stutter on repeat runs; big for CS2.
///  - `silenceDebug` (WINEDEBUG=-all) removes logging overhead in hot paths.
///  - The HUD / MoltenVK knobs are diagnostics or marginal; off by default.
///  Some "turbo" options trade stability for speed — measure, don't assume.
public struct PerformanceProfile: Codable, Sendable {
    /// Keep a persistent Metal/DXVK shader cache in the bottle (avoids stutter).
    public var shaderCache: Bool
    /// WINEDEBUG=-all — removes Wine's debug-channel overhead.
    public var silenceDebug: Bool
    /// DXVK async pipeline compilation (DXVK/DXMT path only). Reduces stutter.
    public var asyncShaders: Bool
    /// Show the Metal performance HUD (FPS/frame time) for measurement.
    public var metalHUD: Bool
    /// Force the discrete/high-power GPU on multi-GPU Macs.
    public var preferHighPowerGPU: Bool
    /// Let MoltenVK use argument buffers / prefill (DXVK→MoltenVK path).
    public var moltenVKFastMath: Bool

    public init(
        shaderCache: Bool = true,
        silenceDebug: Bool = true,
        asyncShaders: Bool = true,
        metalHUD: Bool = false,
        preferHighPowerGPU: Bool = true,
        moltenVKFastMath: Bool = true
    ) {
        self.shaderCache = shaderCache
        self.silenceDebug = silenceDebug
        self.asyncShaders = asyncShaders
        self.metalHUD = metalHUD
        self.preferHighPowerGPU = preferHighPowerGPU
        self.moltenVKFastMath = moltenVKFastMath
    }

    // Forward-compatible decoding: unknown-older configs get sane defaults.
    enum CodingKeys: String, CodingKey {
        case shaderCache, silenceDebug, asyncShaders, metalHUD, preferHighPowerGPU, moltenVKFastMath
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shaderCache = try c.decodeIfPresent(Bool.self, forKey: .shaderCache) ?? true
        silenceDebug = try c.decodeIfPresent(Bool.self, forKey: .silenceDebug) ?? true
        asyncShaders = try c.decodeIfPresent(Bool.self, forKey: .asyncShaders) ?? true
        metalHUD = try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false
        preferHighPowerGPU = try c.decodeIfPresent(Bool.self, forKey: .preferHighPowerGPU) ?? true
        moltenVKFastMath = try c.decodeIfPresent(Bool.self, forKey: .moltenVKFastMath) ?? true
    }

    /// Safe, balanced defaults.
    public static let balanced = PerformanceProfile()

    /// Everything on, HUD on for benchmarking. "As fast as we can push it."
    public static let turbo = PerformanceProfile(
        shaderCache: true, silenceDebug: true, asyncShaders: true,
        metalHUD: true, preferHighPowerGPU: true, moltenVKFastMath: true)

    /// Environment contributions. `backend` and `cacheDir` tailor the keys that
    /// only make sense for a given translation layer.
    public func environment(backend: GraphicsBackend, cacheDir: URL) -> [String: String] {
        var env: [String: String] = [:]

        if silenceDebug { env["WINEDEBUG"] = "-all" }
        if metalHUD { env["MTL_HUD_ENABLED"] = "1" }
        if preferHighPowerGPU { env["MTL_PREFER_HIGH_POWER_GPU"] = "1" }

        if shaderCache {
            switch backend {
            case .dxvk:
                env["DXVK_STATE_CACHE"] = "1"
                env["DXVK_STATE_CACHE_PATH"] = cacheDir.path
            case .d3dmetal:
                // D3DMetal / Metal keep a function cache; point it at the bottle.
                env["MTL_SHADER_CACHE_PATH"] = cacheDir.path
                env["D3DM_SHADER_CACHE_PATH"] = cacheDir.path
            case .wined3d:
                env["__GL_SHADER_DISK_CACHE"] = "1"
            }
        }
        if asyncShaders {
            switch backend {
            case .dxvk: env["DXVK_ASYNC"] = "1"
            case .d3dmetal: env["DXMT_METALLIB_CACHE"] = "1"
            case .wined3d: break
            }
        }
        if moltenVKFastMath && backend == .dxvk {
            env["MVK_CONFIG_FAST_MATH_ENABLED"] = "1"
            env["MVK_CONFIG_PREFILL_METAL_COMMAND_BUFFERS"] = "1"
        }
        return env
    }
}
