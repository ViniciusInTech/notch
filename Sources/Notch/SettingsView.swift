import SwiftUI
import AppKit
import NotchCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var login: LoginService
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var input = TimerInput()
    @StateObject private var hooks = HookStatus()

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
                Section("Pomodoro") {
                    minutesStepper("Foco", value: $preferences.pomodoroFocusMinutes, range: 1...180)
                    minutesStepper("Pausa curta", value: $preferences.pomodoroShortBreakMinutes, range: 1...60)
                    minutesStepper("Pausa longa", value: $preferences.pomodoroLongBreakMinutes, range: 1...120)
                    Stepper(value: $preferences.pomodoroSessions, in: PomodoroSettings.sessionRange) {
                        LabeledContent("Sessões de foco por ciclo", value: "\(preferences.pomodoroSessions)")
                    }
                    Toggle("Iniciar próxima etapa automaticamente", isOn: $preferences.pomodoroAutoStart)
                    Text("Com o início automático, foco e pausas se alternam até a pausa longa encerrar o ciclo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

            Form {
                Section("Avisos de assistentes") {
                    Toggle("Mostrar avisos na ilha", isOn: $preferences.agentsEnabled)
                    Toggle("Pausar avisos (compartilhando a tela)", isOn: $preferences.agentsPaused)
                        .disabled(!preferences.agentsEnabled)
                    Stepper(value: $preferences.agentPermissionWait, in: 10...120, step: 5) {
                        LabeledContent("Aguardar resposta na ilha", value: "\(preferences.agentPermissionWait) s")
                    }
                    .disabled(!preferences.agentsEnabled)
                    Text("Os hooks rodam um comando local, sem gastar tokens. Sem resposta na ilha, ou com os avisos pausados, o pedido volta para o próprio assistente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Hooks") {
                    ForEach(AgentKind.allCases, id: \.rawValue) { agent in hookRow(agent) }
                    if !AgentHookInstaller.helperExists {
                        Text("notch-hook não foi encontrado ao lado do app. Gere o app com scripts/build.sh.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let message = hooks.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
                    Text("Instalar altera o arquivo de hooks do usuário e guarda uma cópia em .notch-backup. Reinstale se mover o Notch.app de lugar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Assistentes", systemImage: "sparkles") }

            VStack(spacing: 14) {
                Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44, weight: .light))
                Text("Notch").font(.title)
                Text("Seu espaço. Sua música.").foregroundStyle(.secondary)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Nativo para macOS").font(.caption).foregroundStyle(.secondary)
                Text("Sem anúncios, conta ou telemetria.").font(.callout)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 510, height: 490)
        .onAppear { login.refresh(); hooks.refresh(); NSApp.activate(ignoringOtherApps: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { login.refresh(); hooks.refresh() } }
    }

    private func hookRow(_ agent: AgentKind) -> some View {
        let installed = hooks.installed.contains(agent)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                Text(agent.supportsPermissions ? "Permissões e conclusão · \(AgentHookInstaller.configURL(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"
                                               : "Só conclusão · \(AgentHookInstaller.configURL(agent).path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(installed ? "Remover" : "Instalar") { hooks.toggle(agent) }
                .disabled(!installed && !AgentHookInstaller.helperExists)
        }
    }

    private func minutesStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: "\(value.wrappedValue) min")
        }
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

@MainActor private final class HookStatus: ObservableObject {
    @Published private(set) var installed: Set<AgentKind> = []
    @Published private(set) var message: String?

    func refresh() { installed = Set(AgentKind.allCases.filter(AgentHookInstaller.isInstalled)) }

    func toggle(_ agent: AgentKind) {
        do {
            if installed.contains(agent) { try AgentHookInstaller.uninstall(agent) } else { try AgentHookInstaller.install(agent) }
            message = nil
        } catch {
            message = "\(agent.name): \(error.localizedDescription)"
        }
        refresh()
    }
}
