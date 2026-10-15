import Foundation

/// Tweaks Steam's own configuration inside a bottle.
///
/// The Steam in-game overlay injects into the game and, under Wine, spends real
/// CPU that causes audio underruns and extra heat. Turning it off helps both.
/// The setting lives in each user's `localconfig.vdf`.
///
/// ⚠️ Steam must be **closed** when this runs, or it overwrites the file on exit.
public enum SteamConfig {

    /// All `userdata/<id>/config/localconfig.vdf` files in the bottle.
    public static func localConfigFiles(in bottle: Bottle) -> [URL] {
        let userdata = bottle.prefixPath
            .appendingPathComponent("drive_c/Program Files (x86)/Steam/userdata")
        let fm = FileManager.default
        guard let ids = try? fm.contentsOfDirectory(at: userdata, includingPropertiesForKeys: nil)
        else { return [] }
        return ids
            .map { $0.appendingPathComponent("config/localconfig.vdf") }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    /// Set `EnableGameOverlay` to "0" in VDF text. Returns the new text and whether
    /// anything changed. Pure; unit-tested.
    public static func disableOverlayInVDF(_ text: String) -> (text: String, changed: Bool) {
        guard let re = try? NSRegularExpression(
            pattern: "(\"EnableGameOverlay\"\\s*)\"1\"", options: []) else { return (text, false) }
        let range = NSRange(text.startIndex..., in: text)
        let matches = re.numberOfMatches(in: text, options: [], range: range)
        guard matches > 0 else { return (text, false) }
        let out = re.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1\"0\"")
        return (out, out != text)
    }

    /// Disable the overlay in every localconfig.vdf in the bottle. Returns the
    /// number of files changed. Steam must not be running.
    @discardableResult
    public static func disableOverlay(in bottle: Bottle) throws -> Int {
        var changed = 0
        for file in localConfigFiles(in: bottle) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let result = disableOverlayInVDF(text)
            if result.changed {
                try result.text.write(to: file, atomically: true, encoding: .utf8)
                changed += 1
            }
        }
        return changed
    }
}
