import Foundation

/// Downloads and lays out the DXMT runtime (3Shain/dxmt) — the open-source,
/// no-Apple-ID D3D11->Metal translation layer.
///
/// Release layout (verified against v0.80):
///   <tag>/x86_64-windows/{d3d11,dxgi,d3d10core,winemetal,...}.dll   (PE, 64-bit)
///   <tag>/i386-windows/{...}.dll                                    (PE, 32-bit)
///   <tag>/x86_64-unix/winemetal.so                                  (Wine-side bridge)
///
/// We place the PE trees under `<support>/dlls/d3dmetal/` (ready for
/// `DLLInstaller` / `macstrike install-graphics`) and drop `winemetal.so` into the
/// Wine install's unix DLL dir, which DXMT needs to talk to Metal.
public struct DXMTInstaller: Sendable {

    public static let releasesAPI = URL(string:
        "https://api.github.com/repos/3Shain/dxmt/releases/latest")!

    /// Directory holding `dlls/`, `downloads/` (e.g. ~/Library/Application Support/MacStrike).
    public let supportDir: URL
    /// The Wine install that receives `winemetal.so` (optional).
    public let wine: WineInstallation?

    public init(supportDir: URL, wine: WineInstallation? = nil) {
        self.supportDir = supportDir
        self.wine = wine
    }

    public enum DXMTError: Error, CustomStringConvertible {
        case network(String)
        case noAsset
        case extractionFailed(String)
        case badArchive(String)
        public var description: String {
            switch self {
            case .network(let m):        return "Network error: \(m)"
            case .noAsset:               return "No .tar.gz asset found in the latest DXMT release"
            case .extractionFailed(let m): return "Failed to extract DXMT archive: \(m)"
            case .badArchive(let m):     return "Unexpected DXMT archive layout: \(m)"
            }
        }
    }

    /// The d3dmetal DLL directory `install-graphics --from` should point at.
    public var dllDestination: URL {
        supportDir.appendingPathComponent("dlls/d3dmetal")
    }

    // MARK: - Pure helpers (unit-tested)

    /// Parse the GitHub "latest release" JSON and pick the downloadable tarball.
    public static func pickAsset(fromReleaseJSON data: Data) throws -> (tag: String, url: URL) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else {
            throw DXMTError.badArchive("release JSON missing assets")
        }
        let tag = (obj["tag_name"] as? String) ?? "latest"
        // Prefer a "builtin" tarball, else any .tar.gz.
        let urls: [String] = assets.compactMap { $0["browser_download_url"] as? String }
            .filter { $0.hasSuffix(".tar.gz") }
        let chosen = urls.first(where: { $0.contains("builtin") }) ?? urls.first
        guard let chosen, let url = URL(string: chosen) else { throw DXMTError.noAsset }
        return (tag, url)
    }

    /// The single top-level directory inside the extracted archive (e.g. "v0.80").
    public static func topLevelDir(in extractedRoot: URL) throws -> URL {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: extractedRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let dirs = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        // Archive extracted its contents directly (no wrapping dir).
        if FileManager.default.fileExists(atPath:
            extractedRoot.appendingPathComponent("x86_64-windows").path) {
            return extractedRoot
        }
        // Normal case: a single wrapping dir like "v0.80".
        if dirs.count == 1 { return dirs[0] }
        throw DXMTError.badArchive("expected one top-level dir, found \(dirs.count)")
    }

    // MARK: - Network / fs steps

    func download(_ url: URL, to dst: URL) throws {
        try FileManager.default.createDirectory(
            at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sem = DispatchSemaphore(value: 0)
        var err: String?
        var tmp: URL?
        var req = URLRequest(url: url)
        req.setValue("MacStrike", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: req) { u, resp, e in
            if let e { err = e.localizedDescription }
            else if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                err = "HTTP \(h.statusCode)"
            } else { tmp = u }
            sem.signal()
        }
        task.resume(); sem.wait()
        if let err { throw DXMTError.network(err) }
        guard let tmp else { throw DXMTError.network("no file returned") }
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
    }

    func fetchLatestAsset() throws -> (tag: String, url: URL) {
        let sem = DispatchSemaphore(value: 0)
        var err: String?
        var data: Data?
        var req = URLRequest(url: Self.releasesAPI)
        req.setValue("MacStrike", forHTTPHeaderField: "User-Agent")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let task = URLSession.shared.dataTask(with: req) { d, resp, e in
            if let e { err = e.localizedDescription }
            else if let h = resp as? HTTPURLResponse, !(200...299).contains(h.statusCode) {
                err = "HTTP \(h.statusCode)"
            } else { data = d }
            sem.signal()
        }
        task.resume(); sem.wait()
        if let err { throw DXMTError.network(err) }
        guard let data else { throw DXMTError.network("empty response") }
        return try Self.pickAsset(fromReleaseJSON: data)
    }

    func extract(_ tarball: URL, into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xzf", tarball.path, "-C", dir.path]
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw DXMTError.extractionFailed("tar exited \(p.terminationStatus)")
        }
    }

    // MARK: - Orchestration

    public struct Result: Sendable {
        public let tag: String
        public let dllDir: URL
        public let winemetalInstalled: Bool
    }

    /// Full install: fetch latest, extract, lay out PE DLLs, place winemetal.so.
    @discardableResult
    public func install(progress: (@Sendable (String) -> Void)? = nil) throws -> Result {
        let fm = FileManager.default
        progress?("Querying latest DXMT release…")
        let (tag, assetURL) = try fetchLatestAsset()

        let downloads = supportDir.appendingPathComponent("downloads")
        let tarball = downloads.appendingPathComponent("dxmt-\(tag).tar.gz")
        progress?("Downloading \(assetURL.lastPathComponent)…")
        try download(assetURL, to: tarball)

        let staging = downloads.appendingPathComponent("dxmt-\(tag)-extracted")
        try? fm.removeItem(at: staging)
        progress?("Extracting…")
        try extract(tarball, into: staging)
        let top = try Self.topLevelDir(in: staging)

        // Lay out PE DLL trees for install-graphics.
        try? fm.removeItem(at: dllDestination)
        try fm.createDirectory(at: dllDestination, withIntermediateDirectories: true)
        for arch in ["x86_64-windows", "i386-windows"] {
            let src = top.appendingPathComponent(arch)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: dllDestination.appendingPathComponent(arch))
        }
        guard fm.fileExists(atPath: dllDestination.appendingPathComponent("x86_64-windows").path) else {
            throw DXMTError.badArchive("no x86_64-windows DLLs in archive")
        }

        // Place winemetal.so into the Wine unix DLL dir, if we have a Wine install.
        var winemetalDone = false
        if let wine, wine.isUsable {
            let so = top.appendingPathComponent("x86_64-unix/winemetal.so")
            let destDir = wine.root.appendingPathComponent("lib/wine/x86_64-unix")
            if fm.fileExists(atPath: so.path), fm.fileExists(atPath: destDir.path) {
                let dst = destDir.appendingPathComponent("winemetal.so")
                try? fm.removeItem(at: dst)
                try fm.copyItem(at: so, to: dst)
                winemetalDone = true
                progress?("Installed winemetal.so into Wine.")
            } else {
                progress?("⚠︎ winemetal.so or Wine lib dir missing; skipped (DXMT may not load).")
            }
        } else {
            progress?("No usable Wine set; skipped winemetal.so (install Wine, then re-run).")
        }

        try? fm.removeItem(at: staging)
        return Result(tag: tag, dllDir: dllDestination, winemetalInstalled: winemetalDone)
    }
}
