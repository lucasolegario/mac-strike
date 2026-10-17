import Foundation
import BottleEngine

// pt-BR copy for setup steps. Kept in the GUI so BottleEngine stays
// logic-only, with no user-facing strings to localise.
extension SetupStep {
    var title: String {
        switch self {
        case .installWine:     return "Instalando o motor"
        case .createBottle:    return "Preparando o ambiente"
        case .fetchDXMT:       return "Baixando a tradução gráfica"
        case .installGraphics: return "Ativando os gráficos"
        case .installSteam:    return "Instalando a Steam"
        case .installGame:     return "Instalando o jogo"
        case .ready:           return "Tudo pronto"
        }
    }

    var subtitle: String {
        switch self {
        case .installWine:
            return "Baixando o Wine open source (~190 MB). Pode deixar rodando."
        case .createBottle:
            return "Criando o ambiente Windows isolado deste jogo."
        case .fetchDXMT:
            return "Baixando o DXMT, que traduz Direct3D para Metal."
        case .installGraphics:
            return "Copiando as DLLs de tradução para o ambiente do jogo."
        case .installSteam:
            return "Baixando e instalando o cliente da Steam."
        case .installGame:
            return "A Steam vai abrir para baixar o jogo. Instale por lá e volte — "
                 + "o MacStrike detecta sozinho quando terminar."
        case .ready:
            return "Esse jogo está pronto para rodar."
        }
    }

    var iconName: String {
        switch self {
        case .installWine:     return "cpu"
        case .createBottle:    return "cube.box"
        case .fetchDXMT:       return "sparkles"
        case .installGraphics: return "wand.and.stars"
        case .installSteam:    return "arrow.down.circle"
        case .installGame:     return "gamecontroller"
        case .ready:           return "checkmark.seal.fill"
        }
    }
}
