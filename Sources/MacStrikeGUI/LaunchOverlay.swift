import SwiftUI
import BottleEngine

/// Full-window overlay shown while a game is starting.
///
/// Launching takes tens of seconds and nothing visible happens on screen, so
/// without this the app looks frozen. Each stage here corresponds to something
/// actually observed (Steam running, game running), never a timer.
struct LaunchOverlay: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    private var phase: LaunchPhase { model.launchPhase }
    private var failed: Bool {
        if case .failed = phase { return true }
        return false
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                indicator

                VStack(spacing: 7) {
                    Text(phase.title(game: game))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(failed ? Theme.warn : Theme.textPrimary)
                    Text(phase.subtitle(game: game))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 300)

                stages

                Button(failed ? "Fechar" : "Cancelar") { model.dismissLaunch() }
                    .buttonStyle(AuroraButtonStyle(prominent: failed))
            }
            .padding(30)
            .frame(width: 400)
            .background(Theme.bgRaised)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var indicator: some View {
        switch phase {
        case .running:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.ok)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.warn)
        default:
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.1)
        }
    }

    /// The two observable stages, so the user can see where it is.
    @ViewBuilder
    private var stages: some View {
        if game.steamAppID != nil, !failed {
            HStack(spacing: 10) {
                stage("Steam", done: phase != .startingSteam,
                      active: phase == .startingSteam)
                Rectangle()
                    .fill(Theme.stroke)
                    .frame(width: 26, height: 1)
                stage(game.name, done: phase == .running,
                      active: phase == .waitingForGame)
            }
        }
    }

    private func stage(_ label: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(done ? Theme.ok.opacity(0.18)
                               : (active ? Theme.accent.opacity(0.2) : Theme.card))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.ok)
                } else if active {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(done || active ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
    }
}
