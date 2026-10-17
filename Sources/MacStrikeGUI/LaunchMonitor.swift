import Foundation
import BottleEngine

/// What the app is doing between "Jogar" being clicked and the game appearing.
///
/// Launching is slow (tens of seconds) and indirect — Wine starts Steam, Steam
/// starts the game — so the UI reports each stage it can actually observe.
enum LaunchPhase: Equatable {
    case idle
    /// The launch command has been fired; Steam has not shown up yet.
    case startingSteam
    /// Steam is up; waiting for the game process to appear.
    case waitingForGame
    /// The game process is running. The overlay shows this briefly, then clears.
    case running
    /// Gave up waiting, or the launch threw.
    case failed(String)

    /// pt-BR copy for the overlay. UI strings stay Portuguese; code is en-US.
    func title(game: Game) -> String {
        switch self {
        case .idle:          return ""
        case .startingSteam: return "Abrindo a Steam…"
        case .waitingForGame: return "Abrindo \(game.name)…"
        case .running:       return "\(game.name) aberto"
        case .failed:        return "Não consegui abrir o jogo"
        }
    }

    func subtitle(game: Game) -> String {
        switch self {
        case .idle:
            return ""
        case .startingSteam:
            return "O cliente da Steam está subindo. Isso leva alguns segundos."
        case .waitingForGame:
            return "A Steam está carregando o jogo. A primeira vez é mais lenta, "
                 + "porque os shaders são compilados."
        case .running:
            return "Bom jogo!"
        case .failed(let message):
            return message
        }
    }
}

/// Timings for the launch watch. Generous: a cold CS2 start under Wine with an
/// empty shader cache can take well over a minute.
enum LaunchTimeout {
    /// How long to wait for the Steam client to appear.
    static let steam: TimeInterval = 90
    /// How long to wait for the game itself, once Steam is up.
    static let game: TimeInterval = 240
    /// Poll interval.
    static let pollNanoseconds: UInt64 = 2_000_000_000
    /// How long "running" stays on screen before the overlay clears.
    static let successLinger: UInt64 = 2_500_000_000
}
