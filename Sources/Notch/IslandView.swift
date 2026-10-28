import SwiftUI
import AppKit
import NotchCore

private let timerTint = Color(red: 1, green: 0.62, blue: 0.04)
private let attentionTint = Color(red: 1, green: 0.84, blue: 0.04)
private let doneTint = Color(red: 0.3, green: 0.85, blue: 0.45)

/// What each side of the collapsed island shows; changing it swaps the view with a scale and blur transition.
private enum CompactSlot: Hashable {
    case artwork, waves, ring, time, music, timer, check, completionText, warning, authorize, agent, agentLabel
}

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var artwork: ArtworkStore
    @ObservedObject var geometry: IslandGeometry
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Namespace private var tabNamespace

    private var reduce: Bool { preferences.reduceMotion || systemReduceMotion }

    var body: some View {
        ZStack(alignment: .top) {
            island
            agentBubble
            agentCard
        }
        .animation(reduce ? .easeOut(duration: 0.15) : .spring(response: 0.36, dampingFraction: 0.78), value: model.agentInBubble)
        .animation(reduce ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.82), value: model.agentCardOpen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
    }

    // MARK: Assistant layers

    /// Beside the island, with music or a timer still on it, like a second Dynamic Island activity.
    @ViewBuilder private var agentBubble: some View {
        let layout = geometry.composition
        if model.agentInBubble, let event = model.agentEvent {
            let size = layout.bubbleSize
            AgentBubble(event: event, size: size, reduce: reduce, progress: model.agentProgress,
                        queued: model.agentEvents.count > 1, framed: true)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .onTapGesture { model.openAgentCard() }
                .offset(x: geometry.shapeSize.width / 2 + IslandComposition.bubbleGap + size / 2, y: layout.bubbleMinY)
                .animation(geometry.shapeAnimation, value: geometry.shapeSize)
                .transition(reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
    }

    @ViewBuilder private var agentCard: some View {
        let layout = geometry.composition
        if model.agentCardOpen, let event = model.agentEvent, let card = layout.card {
            AgentCard(event: event, model: model)
                .id(event.id)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CardHeightKey.self, value: proxy.size.height)
                })
                .onPreferenceChange(CardHeightKey.self) { height in
                    if height > 0, abs(height - geometry.agentCardHeight) > 0.5 { geometry.agentCardHeight = height }
                }
                .offset(x: layout.cardMinX + card.width / 2, y: layout.cardMinY)
                .transition(reduce ? .opacity : .scale(scale: 0.85, anchor: .topTrailing).combined(with: .opacity))
        }
    }

    private var island: some View {
        let shape = geometry.shapeSize
        return VStack(spacing: 0) {
            topBand
                .frame(height: geometry.notchHeight)
                .contentShape(Rectangle())
                .onTapGesture { model.expanded.toggle() }
                .accessibilityLabel("Ilha do Notch")
                .accessibilityAddTraits(model.expanded ? [] : .isButton)
                .accessibilityAction { model.expanded.toggle() }
            if model.expanded {
                expandedContent
                    .frame(width: geometry.expandedWidth, height: geometry.expandedHeight - geometry.notchHeight, alignment: .top)
                    // Closing fades the content quickly so the shape never shrinks over visible text.
                    .transition(.opacity.animation(reduce ? nil : .easeOut(duration: 0.09)))
                    .allowsHitTesting(geometry.expandedContentVisible)
            }
        }
        // Content keeps its final width and is centered: the growing shape reveals it from the notch outward.
        .frame(width: max(0, shape.width - 2 * IslandLayout.shoulderWidth), height: shape.height, alignment: .top)
        .padding(.horizontal, IslandLayout.shoulderWidth)
        .background(.black)
        .clipShape(NotchOutline(bottomRadius: shape.height > geometry.notchHeight + 1 ? 22 : 12))
        .animation(geometry.shapeAnimation, value: shape)
    }

    // MARK: Top band

    @ViewBuilder private var topBand: some View {
        if model.expanded {
            HStack(spacing: 0) {
                tabSwitcher.frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: geometry.notchWidth)
                actions.frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(width: geometry.expandedWidth)
            .reveal(geometry.expandedContentVisible, order: 0, reduce: reduce)
        } else {
            HStack(spacing: 0) {
                ear(leftSlot)
                Color.clear.frame(width: geometry.notchWidth)
                ear(rightSlot)
            }
            .animation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: [leftSlot, rightSlot])
            .accessibilityElement(children: .combine)
        }
    }

    private var leftSlot: CompactSlot? {
        guard model.active else { return nil }
        if model.agentInIsland { return .agent }
        if model.showsAttention { return .warning }
        if model.completionVisible { return .check }
        let items = model.activityOrder.items
        if items.count == 2 { return items[0] == .music ? .music : .timer }
        return model.countdown.isActive ? .ring : .artwork
    }

    private var rightSlot: CompactSlot? {
        guard model.active else { return nil }
        if model.agentInIsland { return .agentLabel }
        if model.showsAttention { return .authorize }
        if model.completionVisible { return .completionText }
        let items = model.activityOrder.items
        if items.count == 2 { return items[1] == .music ? .music : .timer }
        return model.countdown.isActive ? .time : .waves
    }

    private func ear(_ slot: CompactSlot?) -> some View {
        ZStack {
            if let slot {
                slotView(slot)
                    .id(slot)
                    .transition(reduce ? .opacity : .modifier(active: EarEntrance(shown: false), identity: EarEntrance(shown: true)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func slotView(_ slot: CompactSlot) -> some View {
        switch slot {
        case .artwork: ArtworkView(artwork: artwork, size: 22)
        case .waves: waves
        case .ring: compactRing
        case .time: compactTime
        case .music:
            HStack(spacing: 7) { ArtworkView(artwork: artwork, size: 20); waves }
                .accessibilityLabel("Música em reprodução")
        case .timer: HStack(spacing: 6) { compactRing; compactTime }
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(timerTint)
                .symbolEffect(.pulse, options: .repeat(3), isActive: !reduce)
                .accessibilityLabel("Etapa concluída")
        case .completionText:
            Text(model.completionTitle)
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(timerTint)
                .lineLimit(1).minimumScaleFactor(0.8)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(attentionTint)
                .accessibilityLabel("Permissão necessária")
        case .authorize:
            Text("Autorizar").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(attentionTint).lineLimit(1)
        case .agent:
            if let event = model.agentEvent { AgentBubble(event: event, size: 20, reduce: reduce, progress: model.agentProgress) }
        case .agentLabel:
            if let event = model.agentEvent {
                let extra = model.agentEvents.count > 1 ? " +\(model.agentEvents.count - 1)" : ""
                Text(event.kind.label + extra)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(event.kind.tint)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    private var waves: some View {
        AlbumWaveform(accent: artwork.accent, isPlaying: model.media?.isPlaying == true, reduceMotion: reduce)
            .frame(width: 24, height: 18)
            .accessibilityLabel("Ondas nas cores da capa")
    }

    private var compactRing: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ProgressRing(progress: model.timerProgress(at: context.date), lineWidth: 2.4, reduce: reduce)
                .frame(width: 13, height: 13)
        }.accessibilityHidden(true)
    }

    private var compactTime: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            CountingText(text: time(model.countdown.remaining(at: context.date)), reduce: reduce)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(timerTint)
        }.accessibilityLabel("Tempo restante")
    }

    // MARK: Expanded header

    private var tabs: [IslandActivity] {
        let started = model.activityOrder.items
        return started + [IslandActivity.music, .timer].filter { !started.contains($0) }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.rawValue) { activity in
                let selected = model.timerPage == (activity == .timer)
                Button {
                    withAnimation(reduce ? nil : .spring(response: 0.34, dampingFraction: 0.8)) { model.timerPage = activity == .timer }
                } label: {
                    Image(systemName: activity == .music ? "music.note" : "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                        .frame(width: 30, height: 22)
                        .background {
                            if selected { Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: tabNamespace) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if activity == .music && model.media?.isPlaying == true { activityDot(.green) }
                            else if activity == .timer && model.countdown.isActive { activityDot(timerTint) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(activity == .music ? "Música" : "Pomodoro")
                .accessibilityLabel(activity == .music ? "Música" : "Pomodoro")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(.white.opacity(0.08), in: Capsule())
    }

    private func activityDot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 4, height: 4).padding(.top, 3).padding(.trailing, 4)
    }

    private var actions: some View {
        HStack(spacing: 0) {
            if preferences.agentsEnabled {
                Button { preferences.agentsPaused.toggle() } label: {
                    Image(systemName: preferences.agentsPaused ? "bell.slash.fill" : "bell.fill")
                        .font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
                        .foregroundStyle(preferences.agentsPaused ? attentionTint : .white.opacity(0.7))
                }
                .buttonStyle(IconButtonStyle())
                .help(preferences.agentsPaused ? "Retomar avisos dos assistentes" : "Pausar avisos dos assistentes")
                .accessibilityLabel(preferences.agentsPaused ? "Retomar avisos dos assistentes" : "Pausar avisos dos assistentes")
            }
            SettingsLink {
                Image(systemName: "slider.horizontal.3").font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("Configurações")
            .accessibilityLabel("Abrir configurações")
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11, weight: .semibold)).frame(width: 24, height: 24)
            }
            .buttonStyle(IconButtonStyle())
            .help("Sair do Notch")
            .accessibilityLabel("Sair do Notch")
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    // MARK: Expanded body

    @ViewBuilder private var expandedContent: some View {
        let visible = geometry.expandedContentVisible
        ZStack(alignment: .top) {
            if model.timerPage {
                PomodoroPanel(model: model, preferences: preferences, visible: visible, reduce: reduce).transition(panelTransition)
            } else if let media = model.media {
                MusicPanel(media: media, model: model, artwork: artwork, visible: visible, reduce: reduce).transition(panelTransition)
            } else {
                emptyMusic(visible: visible).transition(panelTransition)
            }
        }
        .padding(.horizontal, 18).padding(.top, 2).padding(.bottom, 10)
        .frame(maxHeight: .infinity)
    }

    private var panelTransition: AnyTransition { reduce ? .opacity : AnyTransition(.blurReplace) }

    private func emptyMusic(visible: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkView(artwork: artwork, size: 50).reveal(visible, order: 1, reduce: reduce)
            VStack(alignment: .leading, spacing: 3) {
                if let source = model.attention {
                    Text("Permissão necessária").font(.system(size: 13.5, weight: .semibold))
                    Text("Autorize o Notch a controlar o \(source.name) em Automação.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    HStack(spacing: 6) {
                        Button("Abrir Ajustes") { model.openAutomationSettings() }.buttonStyle(PillButtonStyle(fill: attentionTint, height: 24))
                        Button("Tentar novamente") { model.retryConnections() }.buttonStyle(PillButtonStyle(height: 24))
                    }.padding(.top, 4)
                } else {
                    Text("Sua música aparece aqui").font(.system(size: 13.5, weight: .semibold))
                    Text(model.errors.isEmpty ? "Inicie a reprodução no Spotify ou no navegador." : "Confira as permissões em Conexões nas configurações.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }.reveal(visible, order: 2, reduce: reduce)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Music

/// One row with cover, title and transport; the progress line underneath.
private struct MusicPanel: View {
    let media: MediaSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject var artwork: ArtworkStore
    let visible: Bool
    let reduce: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(artwork: artwork, size: 50)
                    .shadow(color: artwork.accent.color.opacity(artwork.image == nil ? 0 : 0.3), radius: 8, y: 3)
                    .reveal(visible, order: 1, reduce: reduce)
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).help(media.title)
                    HStack(spacing: 5) {
                        Text(media.artist).foregroundStyle(.secondary).lineLimit(1)
                        Text("·").foregroundStyle(.tertiary)
                        Text(media.source == .chrome ? "Chrome" : media.source.name)
                            .foregroundStyle(media.source == .spotify ? Color(red: 0.29, green: 0.87, blue: 0.5) : Color.secondary)
                            .fixedSize()
                    }
                    .font(.system(size: 11.5))
                }
                .reveal(visible, order: 2, reduce: reduce)
                Spacer(minLength: 6)
                transport.reveal(visible, order: 2, reduce: reduce)
            }
            ProgressScrubber(media: media, model: model, accent: artwork.accent.color, reduce: reduce)
                .reveal(visible, order: 3, reduce: reduce)
        }
        .disabled(model.commandBusy)
    }

    private var transport: some View {
        HStack(spacing: 10) {
            Button { model.perform(.previous) } label: {
                Image(systemName: "backward.end.fill").font(.system(size: 17)).frame(width: 36, height: 36)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(!media.canSkip).accessibilityLabel("Música anterior")
            Button { model.perform(.togglePlayback) } label: {
                Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .contentTransition(reduce ? .identity : .symbolEffect(.replace))
                    .foregroundStyle(.black)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(media.isPlaying ? "Pausar" : "Reproduzir")
            Button { model.perform(.next) } label: {
                Image(systemName: "forward.end.fill").font(.system(size: 17)).frame(width: 36, height: 36)
            }
            .buttonStyle(IconButtonStyle())
            .disabled(!media.canSkip).accessibilityLabel("Próxima música")
        }
    }
}

private struct ProgressScrubber: View {
    let media: MediaSnapshot
    @ObservedObject var model: AppModel
    let accent: Color
    let reduce: Bool
    @StateObject private var seek = MediaSeekState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = seek.seeking ? seek.seek : media.position(at: context.date)
            let fraction = media.canSeek ? min(1, max(0, position / media.duration)) : 0
            HStack(spacing: 8) {
                Text(time(position)).frame(minWidth: 30, alignment: .leading)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.16))
                        Capsule().fill(accent).frame(width: proxy.size.width * fraction)
                            .animation(seek.seeking || reduce || !media.isPlaying ? nil : .linear(duration: 1), value: fraction)
                    }
                    .frame(height: seek.hovering || seek.seeking ? 5 : 3)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        guard media.canSeek else { return }
                        seek.seeking = true
                        seek.seek = min(1, max(0, value.location.x / proxy.size.width)) * media.duration
                    }.onEnded { _ in
                        guard seek.seeking else { return }
                        model.perform(.seek(seek.seek))
                        seek.seeking = false
                    })
                }
                .frame(height: 12)
                .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { seek.hovering = inside && media.canSeek } }
                Text(media.canSeek ? "−" + time(max(0, media.duration - position)) : "Ao vivo")
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            .accessibilityElement()
            .accessibilityLabel("Posição da música")
            .accessibilityValue(time(position))
            .accessibilityAdjustableAction { direction in
                guard media.canSeek else { return }
                let step: Double = direction == .increment ? 10 : -10
                model.perform(.seek(min(media.duration, max(0, position + step))))
            }
        }
    }
}

// MARK: - Pomodoro

/// Same rhythm as the music panel: ring, time and controls in one row; phases and sessions below.
private struct PomodoroPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    let visible: Bool
    let reduce: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                        ProgressRing(progress: model.timerProgress(at: context.date), lineWidth: 4, reduce: reduce)
                        Image(systemName: phaseIcon).font(.system(size: 15, weight: .semibold)).foregroundStyle(timerTint)
                    }
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)
                .reveal(visible, order: 1, reduce: reduce)

                VStack(alignment: .leading, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CountingText(text: clock(at: context.date), reduce: reduce)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                    }
                    .accessibilityLabel("Tempo restante")
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .reveal(visible, order: 2, reduce: reduce)
                Spacer(minLength: 6)
                controls.reveal(visible, order: 2, reduce: reduce)
            }
            HStack(spacing: 0) {
                phases
                Spacer(minLength: 6)
                sessionDots
            }
            .reveal(visible, order: 3, reduce: reduce)
        }
    }

    private var phaseIcon: String {
        if model.countdown.isActive && !model.timerIsPomodoro { return "timer" }
        return model.pomodoro.phase == .work ? "brain.head.profile" : "cup.and.saucer.fill"
    }

    private func clock(at date: Date) -> String {
        model.countdown.isActive ? time(model.countdown.remaining(at: date)) : "\(settings.minutes(for: model.pomodoro.phase)):00"
    }

    private var settings: PomodoroSettings { preferences.pomodoro }

    private var subtitle: String {
        let phase = model.pomodoro.phase
        if model.countdown.isActive {
            if model.countdown.isPaused { return "Pausado" }
            if !model.timerIsPomodoro { return "Timer personalizado" }
        } else if model.completionVisible {
            return model.completionTitle == "Ciclo concluído" ? "Ciclo concluído · \(settings.sessions) sessões" : "\(model.completionTitle) · inicie quando quiser"
        }
        switch phase {
        case .work: return "Foco · sessão \(min(model.pomodoro.completedSessions + 1, settings.sessions)) de \(settings.sessions)"
        case .shortBreak: return "Pausa curta"
        case .longBreak: return "Pausa longa · ciclo completo"
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: 6) {
            if model.countdown.isActive {
                Button { model.cancelTimer() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.1)))
                }
                .buttonStyle(PressableStyle())
                .help("Encerrar")
                .accessibilityLabel("Encerrar")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                Button { model.toggleTimer() } label: {
                    Image(systemName: model.countdown.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .contentTransition(reduce ? .identity : .symbolEffect(.replace))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(timerTint))
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(model.countdown.isPaused ? "Continuar" : "Pausar")
            } else {
                Button { model.startPomodoro() } label: { Label("Iniciar", systemImage: "play.fill") }
                    .buttonStyle(PillButtonStyle(fill: timerTint, height: 30))
            }
        }
        .animation(reduce ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: model.countdown.isActive)
    }

    private var phases: some View {
        HStack(spacing: 2) {
            ForEach(PomodoroPhase.allCases, id: \.rawValue) { phase in
                let selected = model.pomodoro.phase == phase
                Button { model.selectPomodoroPhase(phase) } label: {
                    Text("\(phase.shortTitle) \(settings.minutes(for: phase))")
                        .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? timerTint : Color.white.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(selected ? timerTint.opacity(0.16) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.countdown.isActive)
                .accessibilityLabel("\(phase.title), \(settings.minutes(for: phase)) minutos")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var sessionDots: some View {
        let total = settings.sessions
        let filled = model.pomodoro.phase == .longBreak ? total : min(model.pomodoro.completedSessions, total)
        let current = model.pomodoro.phase == .work && model.countdown.isActive && model.timerIsPomodoro ? filled : nil
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(index < filled || index == current ? timerTint : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .background(Circle().fill(timerTint.opacity(index == current ? 0.25 : 0)).frame(width: 11, height: 11))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) de \(total) sessões concluídas")
    }
}

// MARK: - Assistants

private let questionTint = Color(red: 0.39, green: 0.68, blue: 1)

private struct CardHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The assistant's glyph with a badge: a raised hand asks permission, a question mark asks
/// for a choice, a speech bubble reports. Waiting requests carry a ring with the time left.
private struct AgentBubble: View {
    let event: AgentEvent
    let size: CGFloat
    let reduce: Bool
    var progress: ((Date) -> Double)?
    var queued = false
    /// Drawn as its own black circle beside the island, instead of inside an ear.
    var framed = false

    var body: some View {
        ZStack {
            if queued {
                Circle().fill(Color(white: 0.09))
                    .frame(width: size * 0.82, height: size * 0.82)
                    .offset(x: size * 0.4)
            }
            if framed { Circle().fill(.black) }
            if let progress, event.kind.waitsForAnswer {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                        Circle().stroke(event.kind.tint.opacity(0.22), lineWidth: 2)
                        Circle()
                            .trim(from: 0, to: min(1, max(0, progress(context.date))))
                            .stroke(event.kind.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(reduce ? nil : .linear(duration: 1), value: progress(context.date))
                    }
                    .padding(framed ? 2 : 0)
                }
            }
            glyph
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) { badge }
        .accessibilityElement()
        .accessibilityLabel("\(event.agent.name): \(event.kind.label)")
    }

    private var glyph: some View {
        Image(systemName: event.agent.symbol)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(event.agent.color)
    }

    private var badge: some View {
        Image(systemName: event.kind.badge)
            .font(.system(size: size * 0.22, weight: .heavy))
            .foregroundStyle(.black)
            .frame(width: size * 0.44, height: size * 0.44)
            .background(Circle().fill(event.kind.tint))
            .overlay(Circle().stroke(.black, lineWidth: max(1, size * 0.05)))
            .offset(x: size * 0.1, y: size * 0.08)
            .symbolEffect(.pulse, options: .repeating, isActive: event.kind.waitsForAnswer && !reduce)
    }
}

/// Mini chat under the bubble. It only changes when the user answers: the countdown is frozen
/// while it is open, and any choice or text in progress keeps it open after the pointer leaves.
private struct AgentCard: View {
    let event: AgentEvent
    @ObservedObject var model: AppModel
    @StateObject private var draft = AgentDraft()
    @FocusState private var typing: Bool

    private var page: Int {
        get { draft.page }
        nonmutating set { draft.page = newValue }
    }
    private var choices: [Int: Set<String>] {
        get { draft.choices }
        nonmutating set { draft.choices = newValue }
    }
    private var texts: [Int: String] {
        get { draft.texts }
        nonmutating set { draft.texts = newValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            switch event.kind {
            case .permission: permission
            case .question: question
            case .completion: completion
            }
        }
        .padding(14)
        .frame(width: IslandGeometry.cardWidth, alignment: .leading)
        .background(.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: hasDraft) { _, draft in model.agentDraft = draft }
    }

    private var hasDraft: Bool {
        typing || texts.values.contains { !$0.trimmed.isEmpty } || choices.values.contains { !$0.isEmpty }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AgentBubble(event: event, size: 30, reduce: true)
            VStack(alignment: .leading, spacing: 1) {
                (Text(event.agent.name).fontWeight(.semibold)
                 + Text(event.project.map { " · \($0)" } ?? "").foregroundColor(.secondary))
                    .font(.system(size: 13)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(event.kind.tint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if model.agentEvents.count > 1 {
                Text("+\(model.agentEvents.count - 1)")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.white.opacity(0.1), in: Capsule())
                    .help("Outros avisos na fila")
            }
        }
    }

    private var subtitle: String {
        switch event.kind {
        case .permission: return isPlan ? "Plano pronto para aprovar" : "Pedido de permissão · \(event.tool)"
        case .question:
            let header = event.questions[safe: page]?.header ?? ""
            let count = event.questions.count > 1 ? " · \(page + 1) de \(event.questions.count)" : ""
            return (header.isEmpty ? "Pergunta" : header) + count
        case .completion: return "Terminou"
        }
    }

    private var isPlan: Bool { event.tool == "ExitPlanMode" }

    // MARK: Permission

    @ViewBuilder private var permission: some View {
        let instruction = texts[0, default: ""]
        message {
            Text(prompt).font(.system(size: 12.5))
            if isPlan {
                ScrollView {
                    Text(event.detail).font(.system(size: 11.5)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            } else if !event.detail.isEmpty {
                Text(event.detail)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(5).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(white: 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            }
        }
        field(isPlan ? "Ou peça mudanças no plano…" : "Ou diga o que fazer em vez disso…", page: 0) {
            if !instruction.trimmed.isEmpty { model.answerAgent(.deny(instruction)) }
        }
        HStack(spacing: 6) {
            terminalButton
            Spacer()
            if instruction.trimmed.isEmpty {
                Button("Recusar") { model.answerAgent(.deny(nil)) }.buttonStyle(PillButtonStyle(height: 28))
                Button(isPlan ? "Aprovar" : "Permitir") { model.answerAgent(.allow) }
                    .buttonStyle(PillButtonStyle(fill: attentionTint, height: 28))
            } else {
                Button("Enviar instrução") { model.answerAgent(.deny(instruction)) }
                    .buttonStyle(PillButtonStyle(fill: attentionTint, height: 28))
            }
        }
    }

    private var prompt: String {
        if isPlan { return "Posso seguir com este plano?" }
        switch event.tool {
        case "Bash", "shell", "exec_command": return "Posso executar este comando?"
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "apply_patch": return "Posso alterar este arquivo?"
        case "WebFetch", "WebSearch": return "Posso acessar a web?"
        default: return "Posso usar \(event.tool)?"
        }
    }

    // MARK: Question

    @ViewBuilder private var question: some View {
        if let item = event.questions[safe: page] {
            message { Text(item.question).font(.system(size: 12.5)) }
            VStack(spacing: 4) {
                ForEach(Array(item.options.enumerated()), id: \.offset) { _, option in
                    optionRow(option, in: item)
                }
            }
            field("Outra resposta…", page: page) { advance() }
            HStack(spacing: 6) {
                terminalButton
                Spacer()
                if page > 0 {
                    Button("Voltar") { page -= 1 }.buttonStyle(PillButtonStyle(height: 28))
                }
                Button(page + 1 < event.questions.count ? "Próxima" : "Enviar") { advance() }
                    .buttonStyle(PillButtonStyle(fill: questionTint, height: 28))
                    .disabled(answer(for: page) == nil)
                    .opacity(answer(for: page) == nil ? 0.45 : 1)
            }
        }
    }

    private func optionRow(_ option: AgentOption, in item: AgentQuestion) -> some View {
        let selected = choices[page, default: []].contains(option.label)
        return Button {
            var set = choices[page, default: []]
            if item.multiSelect { if selected { set.remove(option.label) } else { set.insert(option.label) } }
            else { set = selected ? [] : [option.label] }
            choices[page] = set
            // A single single-choice question answers on tap, like a quick reply.
            if !item.multiSelect, event.questions.count == 1, !set.isEmpty, texts[page, default: ""].trimmed.isEmpty {
                model.answerAgent(.answer([item.question: option.label]))
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.multiSelect ? (selected ? "checkmark.square.fill" : "square")
                                                   : (selected ? "largecircle.fill.circle" : "circle"))
                    .font(.system(size: 13)).foregroundStyle(selected ? questionTint : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(.system(size: 12, weight: .semibold))
                    if !option.description.isEmpty {
                        Text(option.description).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? questionTint.opacity(0.16) : Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Written text wins over the picked options for that question.
    private func answer(for index: Int) -> String? {
        let text = texts[index, default: ""].trimmed
        if !text.isEmpty { return text }
        guard let item = event.questions[safe: index] else { return nil }
        let picked = item.options.map(\.label).filter { choices[index, default: []].contains($0) }
        return picked.isEmpty ? nil : picked.joined(separator: ", ")
    }

    private func advance() {
        guard answer(for: page) != nil else { return }
        if page + 1 < event.questions.count { page += 1; return }
        var answers: [String: String] = [:]
        for (index, item) in event.questions.enumerated() {
            guard let value = answer(for: index) else { page = index; return }
            answers[item.question] = value
        }
        model.answerAgent(.answer(answers))
    }

    // MARK: Completion

    @ViewBuilder private var completion: some View {
        message {
            ScrollView {
                Text(event.detail).font(.system(size: 12.5)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }
            .frame(maxHeight: 110)
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack {
            Spacer()
            Button("Dispensar") { model.answerAgent(nil) }.buttonStyle(PillButtonStyle(height: 28))
        }
    }

    // MARK: Pieces

    private func message<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) { content() }
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.11), in: UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 14,
                                                                        bottomTrailingRadius: 14, topTrailingRadius: 14, style: .continuous))
    }

    private func field(_ placeholder: String, page index: Int, submit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: Binding(get: { texts[index, default: ""] }, set: { texts[index] = $0 }), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .lineLimit(1...3)
            .focused($typing)
            .onSubmit(submit)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Hands the request back to the assistant's own prompt.
    private var terminalButton: some View {
        Button("Responder no terminal") { model.answerAgent(nil) }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

private extension AgentKind {
    var symbol: String {
        switch self {
        case .claude: return "asterisk"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow"
        }
    }

    var color: Color {
        switch self {
        case .claude: return Color(red: 0.88, green: 0.48, blue: 0.33)
        case .codex: return .white
        case .cursor: return Color(white: 0.85)
        }
    }
}

private extension AgentEventKind {
    var label: String {
        switch self { case .permission: return "Permissão"; case .question: return "Pergunta"; case .completion: return "Concluído" }
    }

    var badge: String {
        switch self { case .permission: return "hand.raised.fill"; case .question: return "questionmark"; case .completion: return "bubble.left.fill" }
    }

    var tint: Color {
        switch self { case .permission: return attentionTint; case .question: return questionTint; case .completion: return doneTint }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Shared pieces

private struct ArtworkView: View {
    @ObservedObject var artwork: ArtworkStore
    let size: CGFloat

    var body: some View {
        Group {
            if let image = artwork.image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    Color(white: 0.12)
                    Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? size * 0.18 : 5, style: .continuous))
        .accessibilityLabel("Capa da música")
    }
}

private struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let reduce: Bool

    var body: some View {
        ZStack {
            Circle().stroke(timerTint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(timerTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduce ? nil : .linear(duration: 1), value: progress)
        }
        .padding(lineWidth / 2)
    }
}

/// Digits roll instead of blinking when the value changes.
private struct CountingText: View {
    let text: String
    let reduce: Bool

    var body: some View {
        Text(text)
            .monospacedDigit()
            .contentTransition(reduce ? .identity : .numericText(countsDown: true))
            .animation(reduce ? nil : .snappy(duration: 0.3), value: text)
    }
}

private struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { IconButtonBody(configuration: configuration) }

    private struct IconButtonBody: View {
        let configuration: Configuration
        @StateObject private var hover = HoverState()
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .background(Circle().fill(.white.opacity(hover.inside && enabled ? 0.1 : 0)))
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover.inside)
                .contentShape(Circle())
                .onHover { hover.inside = $0 }
        }
    }
}

private struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct PillButtonStyle: ButtonStyle {
    var fill: Color?
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: fill == nil ? .semibold : .bold))
            .foregroundStyle(fill == nil ? Color.white.opacity(0.85) : Color.black.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(fill ?? Color.white.opacity(0.1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Opacity, blur and a small drop, staggered by order once the shape has started opening.
private struct Reveal: ViewModifier {
    let visible: Bool
    let order: Int
    let reduce: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .blur(radius: visible || reduce ? 0 : 6)
            .offset(y: visible || reduce ? 0 : -6)
            .animation(reduce ? .easeOut(duration: 0.15)
                       : .spring(response: 0.36, dampingFraction: 0.84).delay(Double(order) * 0.04), value: visible)
    }
}

private struct EarEntrance: ViewModifier {
    let shown: Bool

    func body(content: Content) -> some View {
        content.scaleEffect(shown ? 1 : 0.8).blur(radius: shown ? 0 : 3).opacity(shown ? 1 : 0)
    }
}

private extension View {
    func reveal(_ visible: Bool, order: Int, reduce: Bool) -> some View {
        modifier(Reveal(visible: visible, order: order, reduce: reduce))
    }
}

private extension PomodoroPhase {
    var shortTitle: String {
        switch self { case .work: return "Foco"; case .shortBreak: return "Pausa"; case .longBreak: return "Longa" }
    }
}

extension ArtworkAccent {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

func time(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds.isFinite ? ceil(seconds) : 0))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

@MainActor private final class MediaSeekState: ObservableObject {
    @Published var seek = 0.0
    @Published var seeking = false
    @Published var hovering = false
}

/// Choices and text typed in the mini chat, per question page.
@MainActor private final class AgentDraft: ObservableObject {
    @Published var page = 0
    @Published var choices: [Int: Set<String>] = [:]
    @Published var texts: [Int: String] = [:]
}

@MainActor private final class HoverState: ObservableObject {
    @Published var inside = false
}
