import SwiftUI
import AppKit
import NotchCore

private let timerTint = Color(red: 1, green: 0.62, blue: 0.04)
private let attentionTint = Color(red: 1, green: 0.84, blue: 0.04)

/// What each side of the collapsed island shows; changing it swaps the view with a scale and blur transition.
private enum CompactSlot: Hashable {
    case artwork, waves, ring, time, music, timer, check, completionText, warning, authorize
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
        let shape = geometry.shapeSize
        VStack(spacing: 0) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
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
        if model.showsAttention { return .warning }
        if model.completionVisible { return .check }
        let items = model.activityOrder.items
        if items.count == 2 { return items[0] == .music ? .music : .timer }
        return model.countdown.isActive ? .ring : .artwork
    }

    private var rightSlot: CompactSlot? {
        guard model.active else { return nil }
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
                PomodoroPanel(model: model, visible: visible, reduce: reduce).transition(panelTransition)
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
        model.countdown.isActive ? time(model.countdown.remaining(at: date)) : "\(model.pomodoro.phase.minutes):00"
    }

    private var subtitle: String {
        let phase = model.pomodoro.phase
        if model.countdown.isActive {
            if model.countdown.isPaused { return "Pausado" }
            if !model.timerIsPomodoro { return "Timer personalizado" }
        } else if model.completionVisible {
            return "\(model.completionTitle) · inicie quando quiser"
        }
        switch phase {
        case .work: return "Foco · sessão \(model.pomodoro.completedSessions % 4 + 1) de 4"
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
                    Text("\(phase.shortTitle) \(phase.minutes)")
                        .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? timerTint : Color.white.opacity(0.55))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(selected ? timerTint.opacity(0.16) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(model.countdown.isActive)
                .accessibilityLabel("\(phase.title), \(phase.minutes) minutos")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var sessionDots: some View {
        let done = model.pomodoro.completedSessions
        let filled = model.pomodoro.phase == .longBreak && done > 0 && done.isMultiple(of: 4) ? 4 : done % 4
        let current = model.pomodoro.phase == .work && model.countdown.isActive && model.timerIsPomodoro ? filled : nil
        return HStack(spacing: 4) {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(index < filled || index == current ? timerTint : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .background(Circle().fill(timerTint.opacity(index == current ? 0.25 : 0)).frame(width: 11, height: 11))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(filled) de 4 sessões concluídas")
    }
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

@MainActor private final class HoverState: ObservableObject {
    @Published var inside = false
}
