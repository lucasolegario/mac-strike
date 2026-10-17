import SwiftUI
import BottleEngine

/// A single game's screen: hero art, readiness, and the primary action.
struct GameDetailView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var onBack: () -> Void

    @State private var showingWizard = false

    private var ready: Bool { model.isReady(for: game) }
    private var progress: Double { model.progress(for: game) }
    private var next: SetupStep { model.nextStep(for: game) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                backButton
                hero
                if ready { readyPanel } else { setupPanel }
            }
            .padding(26)
        }
        .sheet(isPresented: $showingWizard) {
            SetupWizardView(game: game)
                .environmentObject(model)
        }
    }

    private var backButton: some View {
        Button(action: onBack) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                Text("Jogos").font(.system(size: 13))
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            Theme.gradient(from: game.accentFrom, to: game.accentTo)
            VStack(alignment: .leading, spacing: 6) {
                Text(ready ? "PRONTO PARA JOGAR" : "PRECISA DE CONFIGURAÇÃO")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.75))
                Text(game.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(22)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    private var readyPanel: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Tudo configurado")
                    .font(.system(size: 15, weight: .semibold))
                Text("O ambiente deste jogo está completo.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { model.play(game) } label: {
                Label("Jogar", systemImage: "play.fill")
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(18)
        .auroraCard()
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Configuração")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            ProgressView(value: progress)
                .tint(Theme.accent)

            HStack(spacing: 11) {
                Image(systemName: next.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Próximo: \(next.title)")
                        .font(.system(size: 13, weight: .medium))
                    Text(next.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            Button { showingWizard = true } label: {
                Label("Configurar", systemImage: "wand.and.stars")
            }
            .buttonStyle(AuroraButtonStyle())
        }
        .padding(18)
        .auroraCard()
    }
}
