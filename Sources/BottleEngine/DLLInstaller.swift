import Foundation

/// Installs a graphics backend's translation DLLs into a bottle.
///
/// The mechanism (the same the Apple GPTK installer uses): copy the backend's PE
/// DLLs into the prefix's `system32` (64-bit) and `syswow64` (32-bit)
/// directories, then force them "native" via `WINEDLLOVERRIDES` at launch
/// (already handled by `LaunchEnvironment`).
///
/// The DLL source trees follow the standard Wine PE layout:
///   <backend>/x86_64-windows/{d3d11,d3d12,dxgi}.dll   -> system32
///   <backend>/i386-windows/{...}.dll                  -> syswow64
public struct DLLInstaller: Sendable {

    /// Where the open-source backend DLLs live on disk. The user points these at
    /// an Apple GPTK extraction, a DXMT release, or a DXVK release.
    public struct Sources: Sendable {
        /// Dir containing `x86_64-windows/` and/or `i386-windows/` for D3DMetal.
        public var d3dmetal: URL?
        public var dxvk: URL?
        public var dxmt: URL?

        public init(d3dmetal: URL? = nil, dxvk: URL? = nil, dxmt: URL? = nil) {
            self.d3dmetal = d3dmetal
            self.dxvk = dxvk
            self.dxmt = dxmt
        }

        func root(for backend: GraphicsBackend) -> URL? {
            switch backend {
            case .d3dmetal: return d3dmetal
            case .dxvk:     return dxvk
            case .wined3d:  return nil
            }
        }
    }

    public let sources: Sources
    public init(sources: Sources) { self.sources = sources }

    public enum InstallError: Error, CustomStringConvertible {
        case noSourceConfigured(GraphicsBackend)
        case sourceMissing(URL)
        case nothingCopied(GraphicsBackend)
        public var description: String {
            switch self {
            case .noSourceConfigured(let b): return "No DLL source configured for backend '\(b.rawValue)'"
            case .sourceMissing(let u):      return "DLL source directory does not exist: \(u.path)"
            case .nothingCopied(let b):      return "No DLLs found to install for backend '\(b.rawValue)'"
            }
        }
    }

    /// Copy the backend's DLLs into `bottle`'s prefix. Returns the installed
    /// Windows-side DLL base names (e.g. ["d3d11","dxgi"]).
    @discardableResult
    public func install(_ backend: GraphicsBackend, into bottle: Bottle) throws -> [String] {
        guard backend != .wined3d else { return [] }
        guard let root = sources.root(for: backend) else {
            throw InstallError.noSourceConfigured(backend)
        }
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw InstallError.sourceMissing(root)
        }

        let drive = bottle.prefixPath.appendingPathComponent("drive_c/windows")
        let targets: [(archDir: String, winDir: String)] = [
            ("x86_64-windows", "system32"),
            ("i386-windows", bottle.architecture == .win64 ? "syswow64" : "system32"),
        ]

        var installed = Set<String>()
        for (archDir, winDir) in targets {
            let srcDir = root.appendingPathComponent(archDir)
            guard FileManager.default.fileExists(atPath: srcDir.path) else { continue }
            let dstDir = drive.appendingPathComponent(winDir)
            try FileManager.default.createDirectory(at: dstDir, withIntermediateDirectories: true)
            let dlls = (try? FileManager.default.contentsOfDirectory(at: srcDir, includingPropertiesForKeys: nil)) ?? []
            for dll in dlls where dll.pathExtension.lowercased() == "dll" {
                let dst = dstDir.appendingPathComponent(dll.lastPathComponent)
                try? FileManager.default.removeItem(at: dst)
                try FileManager.default.copyItem(at: dll, to: dst)
                installed.insert(dll.deletingPathExtension().lastPathComponent.lowercased())
            }
        }
        guard !installed.isEmpty else { throw InstallError.nothingCopied(backend) }
        return installed.sorted()
    }
}
