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
                    Picker("Ao passar o mouse", selection: hoverStyle) {
                        Text("Compacto, para os lados").tag(HoverStyle.compact)
                        Text("Expandir para baixo").tag(HoverStyle.expand)
                        Text("Nada").tag(HoverStyle.none)
                    }
                    Text("No compacto, a ilha mostra a atividade e os controles na altura do notch. Clique para abrir o painel completo.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Reduzir animações", isOn: $preferences.reduceMotion)
                    Toggle("Som ao terminar temporizador", isOn: $preferences.soundEnabled)
                }
                if PowerMonitor.hasBattery {
                    Section("Carregador") {
                        Toggle("Mostrar ao conectar ou desconectar", isOn: $preferences.powerNotice)
                        Toggle("Avisar carga completa", isOn: $preferences.powerChargedNotice)
                        Toggle("Avisar bateria fraca (20% e 10%)", isOn: $preferences.powerLowNotice)
                        Text("Aparece na ilha por alguns segundos e some sozinho.").font(.caption).foregroundStyle(.secondary)
                    }
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
                Section("Tocando agora") {
                    Toggle("Ler o Tocando agora do macOS", isOn: $preferences.systemMediaEnabled)
                    Text("Mostra e controla o que o Mac está tocando: Música, Spotify, YouTube Music, navegadores e outros apps que aparecem na Central de Controle. Não pede Automação. Com esta opção, Spotify e navegador abaixo ficam só como reserva.")
                        .font(.caption).foregroundStyle(.secondary)
                    if preferences.systemMediaEnabled { connectionStatus(.system) }
                }
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
                Section("Atalhos rápidos") {
                    ForEach(Array(preferences.keepAwakePresets.enumerated()), id: \.offset) { index, minutes in
                        HStack {
                            Stepper(value: Binding(get: { minutes }, set: { updatePreset(at: index, to: $0, from: minutes) }),
                                    in: KeepAwakePresets.range) {
                                LabeledContent(KeepAwakeFormat.label(minutes: minutes), value: minutes == preferences.keepAwakeDefault ? "Padrão" : "")
                            }
                            Button { removePreset(at: index) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .disabled(preferences.keepAwakePresets.count <= 1)
                                .accessibilityLabel("Remover \(KeepAwakeFormat.label(minutes: minutes))")
                        }
                    }
                    Button("Adicionar atalho") {
                        preferences.keepAwakePresets = KeepAwakePresets.normalized(preferences.keepAwakePresets + [KeepAwakePresets.next(after: preferences.keepAwakePresets)])
                    }
                    .disabled(preferences.keepAwakePresets.count >= KeepAwakePresets.maximumCount)
                    Text("Até \(KeepAwakePresets.maximumCount) durações aparecem na aba, além de “Sempre” e “Outro”, que aceita minutos, horas ou dias.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Comportamento") {
                    Picker("Botão Ligar usa", selection: $preferences.keepAwakeDefault) {
                        ForEach(Array(Set(preferences.keepAwakePresets + [preferences.keepAwakeDefault])).filter { $0 > 0 }.sorted(), id: \.self) { minutes in
                            Text(KeepAwakeFormat.label(minutes: minutes)).tag(minutes)
                        }
                        Text("Sem limite").tag(0)
                    }
                    Toggle("Permitir que a tela apague", isOn: $preferences.keepAwakeAllowDisplaySleep)
                    Toggle("Desligar com bateria abaixo de 20%", isOn: $preferences.keepAwakeBatteryCutoff)
                    Toggle("Mostrar na ilha recolhida", isOn: $preferences.keepAwakeShowCollapsed)
                    Text("Usa a mesma asserção de energia do caffeinate, sem processo extra. Fechar a tampa ainda coloca o Mac para dormir. Ao terminar o prazo ou sair do Notch, o Mac volta a dormir normalmente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Acordado", systemImage: "cup.and.saucer") }

            Form {
                Section("Avisos de assistentes") {
                    Toggle("Mostrar avisos na ilha", isOn: $preferences.agentsEnabled)
                    Toggle("Pausar avisos (compartilhando a tela)", isOn: $preferences.agentsPaused)
                        .disabled(!preferences.agentsEnabled)
                    Stepper(value: $preferences.agentPermissionWait, in: 10...120, step: 5) {
                        LabeledContent("Aguardar resposta na ilha", value: "\(preferences.agentPermissionWait) s")
                    }
                    .disabled(!preferences.agentsEnabled)
                    Picker("Alerta", selection: $preferences.agentAlertMode) {
                        Text("Notificação com som").tag(AgentAlertMode.sound)
                        Text("Notificação sem som").tag(AgentAlertMode.banner)
                        Text("Silencioso").tag(AgentAlertMode.silent)
                    }
                    .disabled(!preferences.agentsEnabled)
                    HStack {
                        Picker("Som", selection: $preferences.agentAlertSound) {
                            ForEach(Self.alertSounds, id: \.self) { Text($0).tag($0) }
                        }
                        Button { model.playAgentSound() } label: { Image(systemName: "speaker.wave.2") }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Ouvir som")
                    }
                    .disabled(!preferences.agentsEnabled || preferences.agentAlertMode != .sound)
                    .onChange(of: preferences.agentAlertSound) { _, _ in model.playAgentSound() }
                    Toggle("Alertar também nas conclusões", isOn: $preferences.agentAlertCompletions)
                        .disabled(!preferences.agentsEnabled || preferences.agentAlertMode == .silent)
                    Text("Pedidos de permissão e perguntas sempre seguem o alerta escolhido. No modo silencioso, o aviso aparece só na ilha.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Os hooks rodam um comando local, sem gastar tokens. Sem resposta na ilha, ou com os avisos pausados, o pedido volta para o próprio assistente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Chamadas") {
                    Toggle("Ajustar avisos durante chamadas", isOn: $preferences.callAdjust)
                    Picker("Durante chamadas", selection: $preferences.callAlertMode) {
                        Text("Silencioso").tag(CallAlertMode.silent)
                        Text("Notificação sem som").tag(CallAlertMode.banner)
                        Text("Pausar avisos").tag(CallAlertMode.pause)
                    }
                    .disabled(!preferences.callAdjust)
                    Picker("Detectar por", selection: $preferences.callUsesMicrophone) {
                        Text("Câmera ou microfone").tag(true)
                        Text("Só câmera").tag(false)
                    }
                    .disabled(!preferences.callAdjust)
                    Text("Vale quando outro app usa a câmera ou o microfone; o Notch só observa o estado, sem acessar imagem ou áudio. O microfone também detecta ditado e gravações. Pausar avisos devolve os pedidos ao próprio assistente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!preferences.agentsEnabled)
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

            Form {
                Section("Próxima reunião") {
                    Toggle("Mostrar próxima reunião", isOn: Binding(get: { preferences.meetingsEnabled }, set: { on in
                        if on { Task { await model.enableMeetings() } } else { preferences.meetingsEnabled = false }
                    }))
                    if model.calendarDenied {
                        Text("O macOS negou o acesso ao Calendário. Libere o Notch em Privacidade e Segurança → Calendários.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Abrir Ajustes de Calendários") { CalendarService.openPrivacySettings() }
                    }
                    Picker("Avisar antes", selection: $preferences.meetingLeadMinutes) {
                        ForEach(MeetingSchedule.leadOptions, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .disabled(!preferences.meetingsEnabled)
                    Picker("Quais eventos", selection: $preferences.meetingsLinkOnly) {
                        Text("Só com link de vídeo").tag(true)
                        Text("Todos com horário").tag(false)
                    }
                    .disabled(!preferences.meetingsEnabled)
                    Text("Lê os eventos das próximas horas do app Calendário, sem alterar nada. Reconhece links do Zoom, Meet, Teams, Webex, Whereby, Jitsi e FaceTime.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if preferences.meetingsEnabled && !model.calendars.isEmpty {
                    Section("Calendários") {
                        ForEach(model.calendars) { calendar in
                            Toggle(calendar.title, isOn: Binding(
                                get: { !preferences.meetingExcludedCalendars.contains(calendar.id) },
                                set: { on in
                                    var excluded = Set(preferences.meetingExcludedCalendars)
                                    if on { excluded.remove(calendar.id) } else { excluded.insert(calendar.id) }
                                    preferences.meetingExcludedCalendars = excluded.sorted()
                                }))
                        }
                    }
                }
            }.formStyle(.grouped).tabItem { Label("Agenda", systemImage: "calendar") }

            Form {
                Section("Bandeja") {
                    Toggle("Aceitar arquivos arrastados até o notch", isOn: $preferences.shelfEnabled)
                    Picker("Remover itens após", selection: $preferences.shelfExpiryHours) {
                        ForEach(ShelfExpiry.options, id: \.self) { Text(ShelfExpiry.label(hours: $0)).tag($0) }
                    }
                    Picker("Ao arrastar para fora", selection: $preferences.shelfDragMoves) {
                        Text("Copiar (⌘ move)").tag(false)
                        Text("Mover (⌥ copia)").tag(true)
                    }
                    Toggle("Remover da bandeja ao soltar em outro lugar", isOn: $preferences.shelfRemoveAfterDrop)
                    Toggle("Mostrar na ilha recolhida", isOn: $preferences.shelfShowCollapsed)
                    if !model.shelf.items.isEmpty {
                        Button("Limpar bandeja (\(model.shelf.items.count))") { model.shelf.clear() }
                    }
                    Text("A bandeja guarda referências: o arquivo continua onde está e, se for apagado, o item some. Só imagens, links e textos vindos do navegador viram cópias numa pasta do Notch, apagadas junto com o item.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Prints") {
                    Toggle("Adicionar prints à bandeja", isOn: $preferences.screenshotsToShelf)
                    Toggle("Mostrar aviso na ilha", isOn: $preferences.screenshotNotice)
                        .disabled(!preferences.screenshotsToShelf)
                    Toggle("Incluir gravações de tela", isOn: $preferences.screenshotRecordings)
                        .disabled(!preferences.screenshotsToShelf)
                    Text("Observa a pasta definida em Captura de Tela (padrão: Mesa); o macOS pode pedir acesso a ela.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!preferences.shelfEnabled)
                Section("Downloads") {
                    Toggle("Avisar downloads concluídos", isOn: $preferences.downloadsNotify)
                    Toggle("Adicionar à bandeja automaticamente", isOn: $preferences.downloadsToShelf)
                        .disabled(!preferences.shelfEnabled)
                    Text("Observa só a pasta Downloads, sem consultas periódicas; o macOS pode pedir acesso a ela.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Bandeja", systemImage: "tray.full") }

            VStack(spacing: 14) {
                Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44, weight: .light))
                Text("Notch").font(.title)
                Text("Seu espaço. Sua música.").foregroundStyle(.secondary)
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") · Nativo para macOS").font(.caption).foregroundStyle(.secondary)
                Text("Sem anúncios, conta ou telemetria.").font(.callout)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(width: 620, height: 520)
        .onAppear { login.refresh(); hooks.refresh(); model.refreshMeetings(); NSApp.activate(ignoringOtherApps: true) }
        .onChange(of: scenePhase) { _, phase in if phase == .active { login.refresh(); hooks.refresh(); model.refreshMeetings() } }
    }

    private enum HoverStyle { case compact, expand, none }

    private var hoverStyle: Binding<HoverStyle> {
        Binding(get: {
            guard preferences.expandOnHover else { return .none }
            return preferences.compactHover ? .compact : .expand
        }, set: { style in
            preferences.expandOnHover = style != .none
            if style != .none { preferences.compactHover = style == .compact }
        })
    }

    private static let alertSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
                                      "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"]

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

    /// Steps follow the preset's scale; a value already in the list is skipped over.
    private func updatePreset(at index: Int, to value: Int, from old: Int) {
        var presets = preferences.keepAwakePresets
        guard presets.indices.contains(index) else { return }
        var next = KeepAwakePresets.step(old, up: value > old)
        while presets.contains(next) && next != old {
            let further = KeepAwakePresets.step(next, up: value > old)
            if further == next { return }
            next = further
        }
        if preferences.keepAwakeDefault == old { preferences.keepAwakeDefault = next }
        presets[index] = next
        preferences.keepAwakePresets = KeepAwakePresets.normalized(presets)
    }

    private func removePreset(at index: Int) {
        var presets = preferences.keepAwakePresets
        guard presets.count > 1, presets.indices.contains(index) else { return }
        presets.remove(at: index)
        preferences.keepAwakePresets = presets
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
