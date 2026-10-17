import SwiftUI
import BottleEngine

/// Licensing: trial state, activation, and what Pro unlocks.
struct ProView: View {
    @EnvironmentObject var model: AppModel
    @State private var key = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LICENÇA")
                        .font(.system(size: 10, weight: .semibold)).tracking(1.6)
                        .foregroundStyle(Theme.textSecondary)
                    Text("MacStrike Pro").font(.system(size: 26, weight: .bold))
                }

                statusPanel
                if case .active = model.licenseStatus { } else { activatePanel }
                perksPanel
            }
            .padding(26)
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 14) {
            Image(systemName: model.isPro ? "checkmark.seal.fill" : "seal")
                .font(.system(size: 22))
                .foregroundStyle(model.isPro ? Theme.ok : Theme.textSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if case .active = model.licenseStatus {
                Button("Remover licença") { model.deactivateLicense() }
                    .buttonStyle(AuroraButtonStyle(prominent: false))
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var headline: String {
        switch model.entitlement {
        case .licensed:        return "Licença ativa"
        case .trial(let d):    return "Trial — \(d) dia\(d == 1 ? "" : "s") restante\(d == 1 ? "" : "s")"
        case .trialExpired:    return "Trial encerrado"
        case .community:       return "Build community"
        }
    }

    private var detail: String {
        switch model.entitlement {
        case .licensed:
            if case .active(let l) = model.licenseStatus, let email = l.email { return email }
            return "Obrigado por apoiar o MacStrike."
        case .trial:
            return "Todos os recursos Pro liberados durante o trial."
        case .trialExpired:
            return "Ative uma licença lifetime para voltar ao Pro."
        case .community:
            return "Licenciamento não configurado neste build — tudo liberado."
        }
    }

    private var activatePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ativar licença").font(.system(size: 15, weight: .semibold))
            Text("Cole a chave que você recebeu na compra.")
                .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
            TextField("Chave de licença", text: $key)
                .textFieldStyle(.roundedBorder)
                .disabled(model.activating)
            if !model.licensingConfigured {
                Text("⚠︎ Este build ainda não tem o produto configurado (veja LicenseConfig).")
                    .font(.system(size: 11)).foregroundStyle(Theme.warn)
            }
            HStack {
                if model.activating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Ativar") { model.activateLicense(key) }
                    .buttonStyle(AuroraButtonStyle())
                    .disabled(key.isEmpty || model.activating || !model.licensingConfigured)
            }
        }
        .padding(18)
        .auroraCard()
    }

    private var perksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("O que o Pro desbloqueia").font(.system(size: 15, weight: .semibold))
            perk("bolt.fill", "Perfil turbo", "HUD do Metal, shaders assíncronos e GPU de alto desempenho.")
            perk("heart.fill", "Apoia o projeto", "Licença lifetime, sem assinatura recorrente.")
        }
        .padding(18)
        .auroraCard()
    }

    private func perk(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(body).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}
