import Foundation

/// Points at a Wine installation on disk and derives the paths the launcher needs.
///
/// You point `root` at an open-source Wine for macOS — the Apple Game Porting
/// Toolkit, a WineHQ build, or a Gcenx build. The tree must contain `bin/`,
/// `lib/` and (usually) `lib64/`.
public struct WineInstallation: Sendable {
    /// Root of the Wine tree (contains `bin/`, `lib/`, `lib64/`).
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var binDirectory: URL { root.appendingPathComponent("bin") }

    /// `wine64` if present, else `wine`.
    public var loader: URL {
        let wine64 = binDirectory.appendingPathComponent("wine64")
        return FileManager.default.fileExists(atPath: wine64.path)
            ? wine64
            : binDirectory.appendingPathComponent("wine")
    }

    public var server: URL { binDirectory.appendingPathComponent("wineserver") }

    /// Colon-separated search path for Wine's PE/so DLLs, assembled from
    /// `lib64/wine` and `lib/wine`.
    public var dllPath: String {
        var parts: [String] = []
        for base in ["lib64", "lib"] {
            let wine = root.appendingPathComponent(base).appendingPathComponent("wine")
            if FileManager.default.fileExists(atPath: wine.path) {
                parts.append(wine.path)
            }
        }
        return parts.joined(separator: ":")
    }

    /// True if the `wine`/`wine64` loader is actually present on disk.
    public var isUsable: Bool {
        FileManager.default.isExecutableFile(atPath: loader.path)
    }
}
