import SwiftUI
import BottleEngine

/// Step-by-step setup for one game.
///
/// The runner needs `AppModel`, which isn't available in `init`, so it is
/// created on first appearance and parked in `RunnerBox`.
struct SetupWizardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let game: Game

    /// Holds the runner so it can be built after the environment exists.
    @MainActor final class RunnerBox: ObservableObject {
        @Published var runner: SetupRunner?
    }

    @StateObject private var runnerBox = RunnerBox()
    @State private var showLog = false

    init(game: Game) { self.game = game }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let runner = runnerBox.runner {
                content(runner).padding(26)
                Divider().overlay(Theme.stroke)
                footer(runner)
            } else {
                ProgressView().padding(40)
            }
        }
        .frame(width: 460)
        .background(Theme.backgroundWash)
        .foregroundStyle(Theme.textPrimary)
        .onAppear {
            guard runnerBox.runner == nil else { return }
            let r = SetupRunner(model: model, game: game)
            runnerBox.runner = r
            r.start()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("CONFIGURANDO")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Theme.textSecondary)
                Text(game.name).font(.system(size: 15, weight: .semibold))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
    }

    @ViewBuilder
    private func content(_ runner: SetupRunner) -> some View {
        VStack(spacing: 16) {
            ring(runner)
            switch runner.phase {
            case .done:
                stepText(title: "Tudo pronto",
                         subtitle: "Esse jogo está configurado. Pode fechar e jogar.")
            case .failed(let message):
                stepText(title: "Algo deu errado", subtitle: message, tint: Theme.warn)
            case .waitingForSteam:
                stepText(title: "Instale o jogo pela Steam",
                         subtitle: runner.currentStep.subtitle)
            case .running, .idle:
                stepText(title: runner.currentStep.title,
                         subtitle: runner.currentStep.subtitle)
            }
            if showLog { logPanel(runner) }
        }
    }

    private func ring(_ runner: SetupRunner) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.02, runner.progress))
                .stroke(Theme.accentGradient,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: runner.progress)
            VStack(spacing: 2) {
                if runner.phase == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Theme.ok)
                } else {
                    Image(systemName: runner.currentStep.iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textPrimary)
                    Text("passo \(runner.stepNumber)/\(runner.totalSteps)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: 136, height: 136)
    }

    private func stepText(title: String, subtitle: String,
                          tint: Color = Theme.textPrimary) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 320)
    }

    private func logPanel(_ runner: SetupRunner) -> some View {
        ScrollView {
            Text(runner.log.isEmpty ? "—" : runner.log)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(height: 110)
        .padding(10)
        .auroraCard(radius: Theme.radiusSmall)
    }

    private func footer(_ runner: SetupRunner) -> some View {
        HStack {
            Button(showLog ? "Ocultar detalhes" : "Ver detalhes") { showLog.toggle() }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            switch runner.phase {
            case .idle:
                Button("Começar") { runner.start() }
                    .buttonStyle(AuroraButtonStyle())
            case .running:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Button("Cancelar") { runner.cancel() }
                        .buttonStyle(AuroraButtonStyle(prominent: false))
                }
            case .waitingForSteam:
                Button("Cancelar") { runner.cancel() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            case .failed:
                Button("Tentar de novo") { runner.retry() }
                    .buttonStyle(AuroraButtonStyle())
            case .done:
                Button("Fechar") { dismiss() }
                    .buttonStyle(AuroraButtonStyle())
            }
        }
        .padding(18)
    }
}
