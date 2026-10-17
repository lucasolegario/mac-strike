import SwiftUI
import BottleEngine

// Temporary placeholders — replaced by Tasks 9, 10 and 11.
// Delete each one as its real view lands.

struct GameDetailView: View {
    let game: Game
    var onBack: () -> Void
    var body: some View {
        VStack { Text(game.name); Button("Voltar", action: onBack) }
    }
}

struct SettingsView: View {
    var body: some View { Text("Ajustes") }
}

struct ProView: View {
    var body: some View { Text("Pro") }
}
