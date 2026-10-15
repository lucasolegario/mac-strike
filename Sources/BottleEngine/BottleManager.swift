import Foundation

public enum BottleError: Error, CustomStringConvertible {
    case wineNotFound(path: String)
    case prefixAlreadyExists(path: String)
    case bottleNotFound(path: String)
    case processFailed(command: String, exitCode: Int32)

    public var description: String {
        switch self {
        case .wineNotFound(let p):
            return "Wine loader not found or not executable at: \(p)"
        case .prefixAlreadyExists(let p):
            return "A bottle already exists at: \(p)"
        case .bottleNotFound(let p):
            return "No bottle found at: \(p)"
        case .processFailed(let cmd, let code):
            return "Command failed (exit \(code)): \(cmd)"
        }
    }
}

/// Creates, loads and persists bottles: initialises the Wine prefix and
/// persists its config.
public struct BottleManager: Sendable {
    public let wine: WineInstallation

    public init(wine: WineInstallation) {
        self.wine = wine
    }

    /// Initialise a new prefix on disk (`wineboot --init`) and persist its config.
    @discardableResult
    public func createBottle(_ bottle: Bottle, runWineboot: Bool = true) throws -> Bottle {
        if runWineboot && !wine.isUsable {
            throw BottleError.wineNotFound(path: wine.loader.path)
        }
        let fm = FileManager.default
        if fm.fileExists(atPath: bottle.configFileURL.path) {
            throw BottleError.prefixAlreadyExists(path: bottle.prefixPath.path)
        }
        try fm.createDirectory(at: bottle.prefixPath, withIntermediateDirectories: true)

        if runWineboot {
            var env = LaunchEnvironment.make(for: bottle, wine: wine)
            env["WINEARCH"] = bottle.architecture.rawValue
            try runProcess(wine.loader, ["wineboot", "--init"], environment: env)
        }
        try save(bottle)
        return bottle
    }

    public func save(_ bottle: Bottle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(bottle)
        try data.write(to: bottle.configFileURL, options: .atomic)
    }

    public func load(prefixPath: URL) throws -> Bottle {
        let configURL = prefixPath.appendingPathComponent("bottle.json")
        guard let data = try? Data(contentsOf: configURL) else {
            throw BottleError.bottleNotFound(path: prefixPath.path)
        }
        return try JSONDecoder().decode(Bottle.self, from: data)
    }

    // MARK: - Process helper

    @discardableResult
    func runProcess(_ executable: URL, _ arguments: [String],
                    environment: [String: String]) throws -> Int32 {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Inherit PATH etc., then overlay the bottle environment.
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in environment { merged[k] = v }
        process.environment = merged
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BottleError.processFailed(
                command: "\(executable.lastPathComponent) \(arguments.joined(separator: " "))",
                exitCode: process.terminationStatus)
        }
        return process.terminationStatus
    }
}
