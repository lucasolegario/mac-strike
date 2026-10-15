import Foundation

/// Launches a Windows executable inside a bottle, building the `Process` with
/// the assembled launch environment.
public struct GameLauncher: Sendable {
    public let wine: WineInstallation

    public init(wine: WineInstallation) {
        self.wine = wine
    }

    /// Build (but do not start) the process that runs `exePath` in `bottle`.
    /// Exposed separately so it can be inspected/tested without executing Wine.
    public func makeProcess(
        bottle: Bottle,
        exePath: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil
    ) -> Process {
        let process = Process()
        process.executableURL = wine.loader
        process.arguments = [exePath] + arguments
        if let wd = workingDirectory {
            process.currentDirectoryURL = wd
        } else {
            // Default to the directory containing the exe (games expect this).
            process.currentDirectoryURL = URL(fileURLWithPath: exePath).deletingLastPathComponent()
        }
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in LaunchEnvironment.make(for: bottle, wine: wine) { merged[k] = v }
        process.environment = merged
        return process
    }

    /// Launch the game and return immediately (does not block on the game).
    @discardableResult
    public func launch(
        bottle: Bottle,
        exePath: String,
        arguments: [String] = []
    ) throws -> Process {
        guard wine.isUsable else { throw BottleError.wineNotFound(path: wine.loader.path) }
        let process = makeProcess(bottle: bottle, exePath: exePath, arguments: arguments)
        try process.run()
        return process
    }

    /// The exact shell-equivalent command, for logging / "copy as command".
    public func describeCommand(bottle: Bottle, exePath: String, arguments: [String] = []) -> String {
        let env = LaunchEnvironment.make(for: bottle, wine: wine)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        let args = ([exePath] + arguments).map { "\"\($0)\"" }.joined(separator: " ")
        return "\(env) \"\(wine.loader.path)\" \(args)"
    }
}
