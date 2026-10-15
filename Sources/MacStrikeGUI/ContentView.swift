import SwiftUI
import UniformTypeIdentifiers
import BottleEngine

struct ContentView: View {
    @EnvironmentObject var store: BottleStore
    @State private var selection: Bottle.ID?
    @State private var showingNew = false
    @State private var showingLicense = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(store.bottles, selection: $selection) { bottle in
                    Label(bottle.name, systemImage: "cube.box").tag(bottle.id)
                }
                SetupStatusBar()
            }
            .navigationTitle("MacStrike")
            .toolbar {
                ToolbarItem { Button { showingNew = true } label: { Image(systemName: "plus") } }
            }
        } detail: {
            if let bottle = store.bottle(selection) {
                BottleDetailView(bottle: bottle)
            } else {
                PlaceholderView()
            }
        }
        .overlay(alignment: .bottom) { if store.busy { BusyBar() } }
        .sheet(isPresented: $showingNew) { NewBottleSheet() }
        .sheet(isPresented: $showingLicense) { LicenseSheet() }
        .alert("Erro", isPresented: .constant(store.lastError != nil)) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingLicense = true } label: {
                    Label(store.entitlementLabel,
                          systemImage: store.isPro ? "checkmark.seal.fill" : "seal")
                }.tint(store.isPro ? .green : .accentColor)
            }
        }
    }
}

struct LicenseSheet: View {
    @EnvironmentObject var store: BottleStore
    @Environment(\.dismiss) var dismiss
    @State private var key = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("MacStrike Pro", systemImage: "checkmark.seal.fill").font(.title2.bold())

            switch store.entitlement {
            case .trial(let days):
                Text("Trial ativo — \(days) dia\(days == 1 ? "" : "s") restante\(days == 1 ? "" : "s").")
                    .foregroundStyle(.blue)
            case .trialExpired:
                Text("Seu trial de 7 dias terminou. Ative uma licença para continuar com o Pro.")
                    .foregroundStyle(.orange)
            default:
                EmptyView()
            }

            switch store.licenseStatus {
            case .active(let l):
                Text("Licença ativa ✓").foregroundStyle(.green)
                if let email = l.email { Text(email).font(.caption).foregroundStyle(.secondary) }
                Button("Remover licença", role: .destructive) { store.deactivateLicense() }
            default:
                Text("Ative sua licença lifetime para desbloquear os recursos Pro.")
                    .font(.callout).foregroundStyle(.secondary)
                TextField("Chave de licença", text: $key)
                    .textFieldStyle(.roundedBorder).disabled(store.activating)
                if !store.licensingConfigured {
                    Text("⚠︎ Este build ainda não tem o produto configurado (veja LicenseConfig).")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    if store.activating { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Ativar") { store.activateLicense(key) }
                        .buttonStyle(.borderedProminent)
                        .disabled(key.isEmpty || store.activating || !store.licensingConfigured)
                }
            }
            Divider()
            HStack { Spacer(); Button("Fechar") { dismiss() } }
        }
        .padding(20).frame(width: 420)
    }
}

// MARK: - Setup / status

struct SetupStatusBar: View {
    @EnvironmentObject var store: BottleStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusRow(ok: store.wineReady, label: store.wineReady ? "Wine pronto" : "Wine ausente (rode setup-wine.sh)")
            HStack {
                StatusRow(ok: store.dxmtInstalled(), label: store.dxmtInstalled() ? "DXMT baixado" : "DXMT ausente")
                Spacer()
                Button("Baixar DXMT") { store.fetchDXMT() }.disabled(store.busy).font(.caption)
            }
        }
        .padding(10)
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4))
    }
}

struct StatusRow: View {
    let ok: Bool; let label: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct BusyBar: View {
    @EnvironmentObject var store: BottleStore
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(store.busyLabel).font(.callout)
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }
}

// MARK: - Detail

struct BottleDetailView: View {
    @EnvironmentObject var store: BottleStore
    let bottle: Bottle
    @State private var exePath = ""

    var body: some View {
        Form {
            Section("Bottle") {
                LabeledContent("Nome", value: bottle.name)
                LabeledContent("Arquitetura", value: bottle.architecture.rawValue)
                LabeledContent("Gráficos", value: bottle.graphicsBackend.rawValue)
                LabeledContent("Performance", value: bottle.performance.metalHUD ? "turbo" : "balanced")
                LabeledContent("DLLs instaladas",
                    value: bottle.installedGraphicsDLLs.isEmpty ? "—" : bottle.installedGraphicsDLLs.joined(separator: ", "))
            }

            Section("1 · Gráficos (DXMT)") {
                Button("Instalar DLLs do DXMT no bottle") { store.installGraphics(bottle) }
                    .disabled(store.busy || !store.dxmtInstalled())
                if !store.dxmtInstalled() {
                    Text("Baixe o DXMT primeiro (barra à esquerda).").font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("2 · Steam + CS2") {
                let installed = store.steamInstalled(bottle)
                StatusRow(ok: installed, label: installed ? "Steam instalada" : "Steam não instalada")
                HStack {
                    Button("Instalar Steam") { store.steamInstall(bottle) }.disabled(store.busy || !store.wineReady)
                    Button("Abrir Steam") { store.steamRun(bottle) }.disabled(store.busy || !installed)
                    Button("Jogar CS2") { store.steamPlay(bottle, appID: SteamApp.cs2) }
                        .disabled(store.busy || !installed).buttonStyle(.borderedProminent)
                }
                if !store.wineReady {
                    Text("Wine ausente — rode scripts/setup-wine.sh.").font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Rodar um .exe qualquer") {
                HStack {
                    TextField("Caminho do .exe no bottle", text: $exePath)
                    Button("Escolher…") { chooseExe() }
                }
                Button("Lançar") { store.launch(bottle, exePath: exePath) }
                    .disabled(exePath.isEmpty || store.busy || !store.wineReady)
            }

            if !store.log.isEmpty {
                Section("Log") {
                    ScrollView { Text(store.log).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                        .frame(height: 120)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(bottle.name)
    }

    private func chooseExe() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .data]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { exePath = url.path }
    }
}

struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.box").font(.largeTitle).foregroundStyle(.secondary)
            Text("Selecione um bottle").font(.headline)
            Text("Crie um com +, baixe o DXMT, instale a Steam e jogue CS2.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}

struct NewBottleSheet: View {
    @EnvironmentObject var store: BottleStore
    @Environment(\.dismiss) var dismiss
    @State private var name = "CS2"
    @State private var backend: GraphicsBackend = .d3dmetal
    @State private var turbo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Novo bottle").font(.headline)
            TextField("Nome", text: $name)
            Picker("Backend gráfico", selection: $backend) {
                ForEach(GraphicsBackend.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Toggle(isOn: $turbo) {
                HStack(spacing: 6) {
                    Text("Perfil turbo (HUD + tudo ligado)")
                    if !store.isPro {
                        Text("PRO").font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.yellow.opacity(0.25)).clipShape(Capsule())
                    }
                }
            }
            .disabled(!store.isPro)
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }
                Button("Criar") {
                    store.create(name: name, backend: backend, turbo: turbo); dismiss()
                }.keyboardShortcut(.defaultAction).disabled(name.isEmpty)
            }
        }
        .padding(20).frame(width: 380)
        .onAppear { turbo = store.isPro }
    }
}
