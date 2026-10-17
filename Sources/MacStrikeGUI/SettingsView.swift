import SwiftUI
import UniformTypeIdentifiers
import BottleEngine

/// Advanced settings: per-game bottle tuning, a bare .exe runner, and the log.
/// `turbo` is the one Pro-gated control.
struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    @State private var selectedID: String = GameCatalog.cs2.id
    @State private var backend: GraphicsBackend = .d3dmetal
    @State private var turbo = false
    @State private var exePath = ""

    private var game: Game {
        model.games.first { $0.id == selectedID } ?? GameCatalog.cs2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MODO AVANÇADO")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Theme.textSecondary)
                    Text("Ajustes").font(.system(size: 26, weight: .bold))
                }

                bottlePanel
                exePanel
                logPanel
            }
            .padding(26)
        }
        .onAppear(perform: syncFromBottle)
        .onChange(of: selectedID) { _ in syncFromBottle() }
    }

    private func syncFromBottle() {
        let b = model.bottle(for: game)
        backend = b.graphicsBackend
        turbo = b.performance.metalHUD
    }

    private var bottlePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ambiente do jogo").font(.system(size: 15, weight: .semibold))

            Picker("Jogo", selection: $selectedID) {
                ForEach(model.games) { Text($0.name).tag($0.id) }
            }

            Picker("Backend gráfico", selection: $backend) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }

            Toggle(isOn: $turbo) {
                HStack(spacing: 6) {
                    Text("Perfil turbo (HUD + tudo ligado)")
                    if !model.isPro {
                        Text("PRO")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Theme.warn.opacity(0.25))
                            .clipShape(Capsule())
                    }
                }
            }
            .disabled(!model.isPro)

            HStack(spacing: 10) {
                Button("Salvar") { model.updateBottle(for: game, backend: backend, turbo: turbo) }
                    .buttonStyle(AuroraButtonStyle())
                Button("Abrir pasta do bottle") { model.openBottleFolder(game) }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var exePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rodar um .exe neste ambiente").font(.system(size: 15, weight: .semibold))
            HStack {
                TextField("Caminho do .exe", text: $exePath)
                    .textFieldStyle(.roundedBorder)
                Button("Escolher…") { chooseExe() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
            Button("Lançar") { model.runExe(in: game, exePath: exePath) }
                .buttonStyle(AuroraButtonStyle())
                .disabled(exePath.isEmpty)
        }
        .padding(18)
        .auroraCard()
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Log").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("Limpar") { model.log = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ScrollView {
                Text(model.log.isEmpty ? "—" : model.log)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(height: 150)
        }
        .padding(18)
        .auroraCard()
    }

    private func chooseExe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { exePath = url.path }
    }
}
