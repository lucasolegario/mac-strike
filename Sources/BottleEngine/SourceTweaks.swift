import Foundation

/// Writes a Source-engine `autoexec.cfg` into a bottle so performance/audio cvars
/// persist across launches — no need to type them in the game console.
///
/// Learned from running CS2 under Wine on macOS: a bigger audio mix-ahead buffer
/// absorbs transient underruns (the "robotic" crackle on sound peaks), and an FPS
/// cap reduces heat and audio-thread contention.
public enum SourceTweaks {

    public struct Settings: Codable, Sendable, Equatable {
        /// Audio mix-ahead buffer in seconds (Source `snd_mixahead`).
        public var audioMixahead: Double
        /// Framerate cap (Source `fps_max`); nil leaves it uncapped.
        public var fpsMax: Int?

        public init(audioMixahead: Double = 0.3, fpsMax: Int? = 144) {
            self.audioMixahead = audioMixahead
            self.fpsMax = fpsMax
        }
    }

    /// Steam app id -> cfg directory, relative to `steamapps/common`.
    public static let knownCfgDirs: [Int: String] = [
        SteamApp.cs2: "Counter-Strike Global Offensive/game/csgo/cfg",
    ]

    public static func isKnownSourceGame(_ appID: Int) -> Bool {
        knownCfgDirs[appID] != nil
    }

    /// The installed cfg directory for `appID` in `bottle`, or nil if not found.
    public static func cfgDir(for appID: Int, in bottle: Bottle) -> URL? {
        guard let rel = knownCfgDirs[appID] else { return nil }
        let dir = bottle.prefixPath
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common")
            .appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// The autoexec.cfg text for the given settings (pure; unit-tested).
    public static func autoexecContents(_ s: Settings) -> String {
        var lines = [
            "// MacStrike — audio/perf tweaks for running under Wine on macOS",
            "snd_mixahead \"\(s.audioMixahead)\"   // larger audio buffer: absorbs transient peaks (less crackle)",
        ]
        if let fps = s.fpsMax {
            lines.append("fps_max \"\(fps)\"   // cap framerate: lowers heat and audio-thread contention")
        }
        lines.append("echo \"[MacStrike] autoexec loaded\"")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Write autoexec.cfg for `appID` into `bottle`. Returns the file URL, or nil
    /// if the game's cfg directory isn't present (not installed there yet).
    @discardableResult
    public static func writeAutoexec(for appID: Int, in bottle: Bottle,
                                     settings: Settings = Settings()) throws -> URL? {
        guard let dir = cfgDir(for: appID, in: bottle) else { return nil }
        let url = dir.appendingPathComponent("autoexec.cfg")
        try Data(autoexecContents(settings).utf8).write(to: url, options: .atomic)
        return url
    }
}
