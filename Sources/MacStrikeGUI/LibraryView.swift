import SwiftUI
import UniformTypeIdentifiers
import BottleEngine

/// The game library: a grid of cards. Picking one opens its detail screen.
struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    var onSelect: (Game) -> Void

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.games) { game in
                        GameCard(game: game)
                            .onTapGesture { if game.supported { onSelect(game) } }
                    }
                    AddGameCard { name, path in
                        model.addCustomGame(name: name, exePath: path)
                    }
                }
            }
            .padding(26)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SUA BIBLIOTECA")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline) {
                Text("Jogos").font(.system(size: 26, weight: .bold))
                Spacer()
                Text(model.entitlementLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(model.isPro ? Theme.ok.opacity(0.15) : Theme.card)
                    .foregroundStyle(model.isPro ? Theme.ok : Theme.textSecondary)
                    .clipShape(Capsule())
            }
        }
    }
}

/// One game tile: gradient art, name, and a status badge driven by the plan.
struct GameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var hovering = false

    private var badge: (text: String, color: Color) {
        if !game.supported { return ("Em breve", Theme.textSecondary) }
        if model.isReady(for: game) { return ("Pronto", Theme.ok) }
        let pct = Int(model.progress(for: game) * 100)
        return pct == 0 ? ("Preparar", Theme.warn) : ("\(pct)% configurado", Theme.warn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Theme.gradient(from: game.accentFrom, to: game.accentTo)
                    .frame(height: 140)
                if game.supported {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .padding(10)
                        .opacity(hovering ? 1 : 0)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(game.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(badge.text)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(badge.color)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .auroraCard()
        .opacity(game.supported ? 1 : 0.55)
        .scaleEffect(hovering && game.supported ? 1.02 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// The trailing "+ Adicionar jogo" tile: picks an .exe and adds a custom game.
struct AddGameCard: View {
    var onAdd: (String, String) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
            Text("Adicionar jogo")
                .font(.system(size: 13, weight: .medium))
            Text("Escolha um .exe")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 212)
        .background(Color.white.opacity(hovering ? 0.05 : 0.02))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .onHover { hovering = $0 }
        .onTapGesture(perform: pick)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        panel.prompt = "Adicionar"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        onAdd(url.deletingPathExtension().lastPathComponent, url.path)
    }
}
