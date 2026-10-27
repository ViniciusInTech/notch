import SwiftUI
import AppKit
import NotchCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var login: LoginService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var input = TimerInput()

    var body: some View {
        TabView {
            Form {
                Section("Comportamento") {
                    Toggle("Expandir ao passar o mouse", isOn: $preferences.expandOnHover)
                    Toggle("Reduzir animações", isOn: $preferences.reduceMotion)
                    Toggle("Som ao terminar temporizador", isOn: $preferences.soundEnabled)
                }
                Section("Inicialização") {
                    Toggle("Iniciar ao fazer login", isOn: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                    if login.needsApproval {
                        Text("O macOS aguarda sua aprovação nos Itens de Início.").font(.caption)
                        Button("Abrir Itens de Início") { login.openSystemSettings() }
                    }
                    if let message = login.message { Text(message).font(.caption).foregroundStyle(.orange) }
                    Text("Mantenha o Notch.app em Aplicativos antes de habilitar esta opção.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Oferecer mover para Aplicativos", isOn: $preferences.offerMoveToApplications)
                }
            }.formStyle(.grouped).tabItem { Label("Geral", systemImage: "slider.horizontal.3") }

            Form {
                Section("Spotify") {
                    Toggle("Integrar com Spotify", isOn: $preferences.spotifyEnabled)
                    connectionStatus(.spotify)
                }
                Section("Navegador · opcional") {
                    Toggle("Mídia do navegador", isOn: $preferences.browserEnabled)
                    Picker("Navegador", selection: $preferences.browser) {
                        Text("Safari").tag(MediaSource.safari)
                        Text("Google Chrome").tag(MediaSource.chrome)
                    }.disabled(!preferences.browserEnabled)
                    Text("Lê somente áudio e vídeo HTML5 da aba ativa. Requer JavaScript via Apple Events habilitado no navegador. Players em iframes podem não funcionar.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.browserEnabled { connectionStatus(preferences.browser) }
                }
                Section {
                    HStack {
                        Button("Permissões de Automação") { model.openAutomationSettings() }
                        Button("Tentar novamente") { model.retryConnections() }
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Conexões", systemImage: "link") }

            Form {
                Section("Temporizador") {
                    HStack {
                        Text("Duração em minutos")
                        Spacer()
                        TextField("Minutos", value: $input.minutes, format: .number).frame(width: 65).textFieldStyle(.roundedBorder)
                        Stepper("Duração", value: $input.minutes, in: 1...1440).labelsHidden()
                    }
                    Button("Iniciar temporizador") { model.startTimer(minutes: input.minutes) }
                        .disabled(!input.minutes.isFinite || input.minutes < 1 || input.minutes > 1440)
                    if model.countdown.isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            LabeledContent(model.countdown.isPaused ? "Pausado" : "Tempo restante", value: time(model.countdown.remaining(at: context.date)))
                                .monospacedDigit()
                        }
                        HStack {
                            Button(model.countdown.isPaused ? "Continuar" : "Pausar") { model.toggleTimer() }
                            Button("Encerrar") { model.cancelTimer() }
                        }
                    }
                    Text("O tempo continua contando se o Mac dormir. O aviso aparece quando ele acordar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Timer", systemImage: "timer") }

            VStack(spacing: 14) {
                Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44, weight: .light))
                Text("Notch").font(.title)
                Text("Seu espaço. Sua música.").foregroundStyle(.secondary)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Nativo para macOS").font(.caption).foregroundStyle(.secondary)
                Text("Sem anúncios, conta ou telemetria.").font(.callout)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 510, height: 490)
        .onAppear { login.refresh(); NSApp.activate(ignoringOtherApps: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { login.refresh() } }
    }

    @ViewBuilder private func connectionStatus(_ source: MediaSource) -> some View {
        if let error = model.errors[source] {
            Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
        } else {
            Text(model.media?.source == source ? "Conectado" : "Aguardando reprodução no aplicativo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

@MainActor private final class TimerInput: ObservableObject {
    @Published var minutes = 25.0
}
