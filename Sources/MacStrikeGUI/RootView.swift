import SwiftUI
import BottleEngine

enum AppSection: String, CaseIterable, Identifiable {
    case games, settings, pro
    var id: String { rawValue }
    var label: String {
        switch self {
        case .games:    return "Jogos"
        case .settings: return "Ajustes"
        case .pro:      return "Pro"
        }
    }
    var icon: String {
        switch self {
        case .games:    return "gamecontroller.fill"
        case .settings: return "slider.horizontal.3"
        case .pro:      return "star.fill"
        }
    }
}

/// The app shell: a slim icon rail on the left, the active section on the right.
struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var section: AppSection = .games
    @State private var selectedGame: Game?

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(Theme.stroke)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backgroundWash.ignoresSafeArea())
        .foregroundStyle(Theme.textPrimary)
        .overlay {
            if let game = model.launchingGame, model.launchPhase != .idle {
                LaunchOverlay(game: game)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.launchPhase)
        .alert("Erro", isPresented: .constant(model.lastError != nil)) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var rail: some View {
        VStack(spacing: 10) {
            Text("MS")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.bottom, 10)

            ForEach(AppSection.allCases) { s in
                Button {
                    section = s
                    if s != .games { selectedGame = nil }
                } label: {
                    Image(systemName: s.icon)
                        .font(.system(size: 15))
                        .frame(width: 34, height: 34)
                        .foregroundStyle(section == s ? .white : Theme.textSecondary)
                        .background {
                            if section == s {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Theme.accentGradient)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(s.label)
            }
            Spacer()
        }
        .padding(.vertical, 18)
        .frame(width: 62)
        .background(Color.white.opacity(0.02))
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .games:
            if let game = selectedGame {
                GameDetailView(game: game) { selectedGame = nil }
            } else {
                LibraryView { selectedGame = $0 }
            }
        case .settings:
            SettingsView()
        case .pro:
            ProView()
        }
    }
}
