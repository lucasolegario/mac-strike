import Foundation

/// Downloads and installs the open-source macOS Wine build (Gcenx) into
/// `<support>/wine`, the same layout `scripts/setup-wine.sh` produces.
///
/// Release assets are `.tar.xz` tarballs named like `wine-staging-11.18-osx64.tar.xz`.
/// Inside, the Wine tree sits at some depth (often `.../Contents/Resources/wine`),
/// so we locate it by finding `bin/wine` and copying that directory's parent.
public struct WineInstaller: Sendable {

    public static let releasesAPI = URL(string:
        "https://api.github.com/repos/Gcenx/macOS_Wine_builds/releases/latest")!

    /// Directory holding `wine/`, `downloads/` (e.g. ~/Library/Application Support/MacStrike).
    public let supportDir: URL
    /// Release channel: "staging" (default) or "devel".
    public let channel: String

    public init(supportDir: URL, channel: String = "staging") {
        self.supportDir = supportDir
        self.channel = channel
    }

    public enum WineError: Error, CustomStringConvertible {
        case network(String)
        case noAsset
        case extractionFailed(String)
        case badArchive(String)
        public var description: String {
            switch self {
            case .network(let m):          return "Erro de rede: \(m)"
            case .noAsset:                 return "Nenhum .tar.xz encontrado na última release do Wine"
            case .extractionFailed(let m): return "Falha ao extrair o Wine: \(m)"
            case .badArchive(let m):       return "Layout inesperado no arquivo do Wine: \(m)"
            }
        }
    }

    /// Where Wine gets installed.
    public var wineRoot: URL { supportDir.appendingPathComponent("wine") }

    /// Is a usable Wine already installed?
    public var isInstalled: Bool { WineInstallation(root: wineRoot).isUsable }

    // MARK: - Pure helpers (unit-tested)

    /// Parse GitHub's "latest release" JSON and pick the tarball for `channel`.
    /// Falls back to the first `.tar.xz` when the channel has no match.
    public static func pickAsset(
        fromReleaseJSON data: Data, channel: String
    ) throws -> (tag: String, url: URL) {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else {
            throw WineError.badArchive("release JSON sem assets")
        }
        let tag = (obj["tag_name"] as? String) ?? "latest"
        let tarballs: [String] = assets
            .compactMap { $0["browser_download_url"] as? String }
            .filter { $0.hasSuffix(".tar.xz") }
        let chosen = tarballs.first { $0.contains("wine-\(channel)-") } ?? tarballs.first
        guard let chosen, let url = URL(string: chosen) else { throw WineError.noAsset }
        return (tag, url)
    }

    /// Find the Wine tree inside an extracted archive: the parent of the
    /// directory containing `bin/wine`.
    public static func wineSourceDir(in extractedRoot: URL) throws -> URL {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: extractedRoot,
                                         includingPropertiesForKeys: nil) else {
            throw WineError.badArchive("não consegui percorrer o arquivo extraído")
        }
        for case let url as URL in walker {
            // Looking for <something>/bin/wine
            guard url.lastPathComponent == "wine" else { continue }
            let parent = url.deletingLastPathComponent()
            guard parent.lastPathComponent == "bin" else { continue }
            return parent.deletingLastPathComponent()
        }
        throw WineError.badArchive("não encontrei bin/wine no arquivo extraído")
    }

    // MARK: - Network / fs steps

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
        if let err { throw WineError.network(err) }
        guard let data else { throw WineError.network("resposta vazia") }
        return try Self.pickAsset(fromReleaseJSON: data, channel: channel)
    }

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
        if let err { throw WineError.network(err) }
        guard let tmp else { throw WineError.network("nenhum arquivo retornado") }
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.moveItem(at: tmp, to: dst)
    }

    func extract(_ tarball: URL, into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        p.arguments = ["-xJf", tarball.path, "-C", dir.path]   // -J = xz
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw WineError.extractionFailed("tar saiu com \(p.terminationStatus)")
        }
    }

    // MARK: - Orchestration

    public struct Result: Sendable {
        public let tag: String
        public let root: URL
    }

    /// Full install: query the latest release, download, extract, copy the Wine
    /// tree into `<support>/wine`. A no-op when Wine is already installed.
    @discardableResult
    public func install(progress: (@Sendable (String) -> Void)? = nil) throws -> Result {
        let fm = FileManager.default
        if isInstalled {
            progress?("Wine já instalado — nada a fazer.")
            return Result(tag: "existente", root: wineRoot)
        }

        progress?("Consultando a última release do Wine…")
        let (tag, assetURL) = try fetchLatestAsset()

        let downloads = supportDir.appendingPathComponent("downloads")
        let tarball = downloads.appendingPathComponent("wine-\(tag).tar.xz")
        progress?("Baixando \(assetURL.lastPathComponent) (~190 MB)…")
        try download(assetURL, to: tarball)

        let staging = downloads.appendingPathComponent("wine-\(tag)-extracted")
        try? fm.removeItem(at: staging)
        progress?("Extraindo…")
        try extract(tarball, into: staging)

        let source = try Self.wineSourceDir(in: staging)
        progress?("Instalando em \(wineRoot.lastPathComponent)…")
        try? fm.removeItem(at: wineRoot)
        try fm.createDirectory(at: wineRoot, withIntermediateDirectories: true)
        // Copy the tree's *contents* so wineRoot ends up with bin/, lib/, …
        for entry in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try fm.copyItem(at: entry, to: wineRoot.appendingPathComponent(entry.lastPathComponent))
        }
        try? fm.removeItem(at: staging)

        guard isInstalled else {
            throw WineError.badArchive("instalação terminou sem bin/wine utilizável")
        }
        progress?("Wine \(tag) pronto.")
        return Result(tag: tag, root: wineRoot)
    }
}
