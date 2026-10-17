import Foundation

/// Detects and installs GStreamer, which Wine needs to decode video.
///
/// Why this exists: Wine's Media Foundation layer (`mfplat`) delegates video
/// decoding to `winegstreamer`, which needs a real GStreamer on the host. With
/// no GStreamer installed, the Steam client's CEF helper asks for an H.264
/// decoder, `h264_decoder_create` fails, and the process takes an access
/// violation (`c0000005`) and dies — leaving a **black Steam window** with no
/// tray icon.
///
/// Diagnosed 2026-10-16 from a `WINEDEBUG=+seh` trace:
///   `err:winediag:h264_decoder_create GStreamer doesn't support H.264 decoding`
///   followed by two `c0000005` faults around `mfplat`.
/// Installing GStreamer 1.28.8 provides `avdec_h264` (libav) and `openh264dec`.
///
/// This is what lets MacStrike run the Steam client on a fully open Wine stack,
/// with no proprietary runtime involved.
public enum GStreamerDependency {

    /// Where the macOS package installs the framework.
    public static var frameworkPath: URL {
        URL(fileURLWithPath: "/Library/Frameworks/GStreamer.framework")
    }

    /// The plugin-inspection tool inside the framework.
    public static var inspectTool: URL {
        frameworkPath.appendingPathComponent("Commands/gst-inspect-1.0")
    }

    /// Official download host. Nothing is fetched from anywhere else.
    public static let downloadHost = "gstreamer.freedesktop.org"

    /// Is GStreamer installed at all?
    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: frameworkPath.path)
    }

    // MARK: - Pure helpers (unit-tested)

    /// GStreamer uses even minor versions for stable releases: 1.28.x is stable,
    /// 1.29.x is a development series.
    public static func isStableVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".")
        guard parts.count >= 2, let minor = Int(parts[1]) else { return false }
        return minor % 2 == 0
    }

    /// The universal runtime package URL for `version`.
    public static func packageURL(version: String) -> URL {
        URL(string: "https://\(downloadHost)/data/pkg/osx/\(version)/"
            + "gstreamer-1.0-\(version)-universal.pkg")!
    }

    /// Newest stable version listed in the download directory index.
    public static func latestStableVersion(fromIndex html: String) -> String? {
        let pattern = #"(\d+\.\d+\.\d+)/"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        var versions: [String] = []
        re.enumerateMatches(in: html, range: range) { match, _, _ in
            guard let match, let r = Range(match.range(at: 1), in: html) else { return }
            versions.append(String(html[r]))
        }
        return versions
            .filter(isStableVersion)
            .max { a, b in
                a.compare(b, options: .numeric) == .orderedAscending
            }
    }

    /// The AppleScript that installs `pkgPath` through macOS's own
    /// authentication dialog.
    ///
    /// Installing into `/Library/Frameworks` needs admin rights. Rather than
    /// asking the user to run a shell command, MacStrike triggers the standard
    /// macOS prompt: they type their password into the system dialog, and the
    /// app never sees it.
    public static func installAppleScript(pkgPath: String) -> String {
        "do shell script \"installer -pkg \\\"\(pkgPath)\\\" -target /\""
            + " with administrator privileges"
    }

    // MARK: - Probing

    /// Does the installed GStreamer actually provide an H.264 decoder?
    ///
    /// Presence of the framework is not enough — the decoder lives in the
    /// "restricted"/libav plugin set.
    public static func hasH264Decoder() -> Bool {
        guard isInstalled,
              FileManager.default.isExecutableFile(atPath: inspectTool.path) else { return false }
        let p = Process()
        p.executableURL = inspectTool
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let listing = String(decoding: data, as: UTF8.self)
        return listing.contains("avdec_h264") || listing.contains("openh264dec")
    }

    /// Everything needed for Wine to decode the video the Steam client plays.
    public static var isSatisfied: Bool { hasH264Decoder() }
}
