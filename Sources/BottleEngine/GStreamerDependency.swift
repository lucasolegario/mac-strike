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

    /// The H.264 decoders Wine's `winegstreamer` can use, ranked.
    ///
    /// Ranking matters: decoding in software burns CPU, and under Wine that
    /// shows up as heat and as audio underruns in games. macOS can decode H.264
    /// on the GPU through VideoToolbox, so that path comes first.
    public enum H264Decoder: String, CaseIterable, Sendable {
        /// Apple VideoToolbox — hardware decode, via GStreamer's `applemedia`.
        case videoToolbox
        /// libav/FFmpeg software decoder.
        case libav
        /// Cisco OpenH264 software decoder.
        case openH264

        /// Does this decoder run on the GPU?
        public var isHardware: Bool { self == .videoToolbox }

        /// Element names as `gst-inspect-1.0` lists them.
        public var elementNames: [String] {
            switch self {
            case .videoToolbox: return ["vtdec", "vtdec_hw"]
            case .libav:        return ["avdec_h264"]
            case .openH264:     return ["openh264dec"]
            }
        }

        /// Best first. Hardware decode beats software.
        public static var preferenceOrder: [H264Decoder] {
            [.videoToolbox, .libav, .openH264]
        }

        /// Which decoders appear in a `gst-inspect-1.0` listing.
        public static func available(inListing listing: String) -> [H264Decoder] {
            allCases.filter { decoder in
                decoder.elementNames.contains { listing.contains($0) }
            }
        }

        /// The best decoder present in a listing, or nil if none is.
        public static func best(inListing listing: String) -> H264Decoder? {
            let present = available(inListing: listing)
            return preferenceOrder.first { present.contains($0) }
        }
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

    /// The plugin listing from `gst-inspect-1.0`, or nil if it cannot run.
    static func pluginListing() -> String? {
        guard isInstalled,
              FileManager.default.isExecutableFile(atPath: inspectTool.path) else { return nil }
        let p = Process()
        p.executableURL = inspectTool
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// The best H.264 decoder actually installed, or nil if there is none.
    ///
    /// Presence of the framework is not enough: a GStreamer without any H.264
    /// decoder still leaves Wine's `mfplat` unable to create one, which is what
    /// crashes the Steam client.
    public static func installedH264Decoder() -> H264Decoder? {
        guard let listing = pluginListing() else { return nil }
        return H264Decoder.best(inListing: listing)
    }

    /// Everything needed for Wine to decode the video the Steam client plays.
    public static var isSatisfied: Bool { installedH264Decoder() != nil }
}
