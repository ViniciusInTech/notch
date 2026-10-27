import SwiftUI
import AppKit
import NotchCore

struct IslandView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var artwork: ArtworkStore
    @ObservedObject var geometry: IslandGeometry
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
                .frame(height: geometry.notchHeight)
                .contentShape(Rectangle())
                .onTapGesture { model.expanded.toggle() }
                .accessibilityLabel("Ilha do Notch")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.expanded.toggle() }
            if geometry.expandedContentVisible {
                expandedContent
                    .frame(width: geometry.expandedWidth, height: geometry.expandedHeight - geometry.notchHeight, alignment: .top)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).combined(with: .offset(y: -6))
                    ))
                    .allowsHitTesting(model.expanded)
            }
        }
        .padding(.horizontal, IslandLayout.shoulderWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.black)
        .clipShape(NotchOutline(bottomRadius: model.expanded ? 24 : 14))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(preferences.reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.16), value: geometry.expandedContentVisible)
        .animation(preferences.reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.16), value: model.expanded)
    }

    private var compactHeader: some View {
        HStack(spacing: 0) {
            Group {
                if model.active && !model.expanded {
                    if model.activityOrder.items.count == 2 {
                        activityIndicator(model.activityOrder.items[0])
                    } else if model.countdown.isActive || model.completionVisible {
                        Image(systemName: "timer").foregroundStyle(.orange)
                    } else { ArtworkView(artwork: artwork, size: 26) }
                } else { Color.clear }
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: geometry.notchWidth)
            Group {
                if model.active && !model.expanded {
                    if model.activityOrder.items.count == 2 {
                        activityIndicator(model.activityOrder.items[1])
                    } else if model.countdown.isActive { timerIndicator }
                    else if model.completionVisible { Image(systemName: "checkmark").foregroundStyle(.orange) }
                    else { waves }
                } else { Color.clear }
            }.frame(maxWidth: .infinity)
        }.accessibilityElement(children: .combine)
    }

    @ViewBuilder private func activityIndicator(_ activity: IslandActivity) -> some View {
        if activity == .music {
            HStack(spacing: 7) { ArtworkView(artwork: artwork, size: 23); waves }
                .accessibilityLabel("Música em reprodução")
        } else {
            HStack(spacing: 5) {
                Image(systemName: "timer").font(.system(size: 11)).foregroundStyle(.orange)
                timerIndicator
            }
        }
    }

    private var timerIndicator: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(time(model.countdown.remaining(at: context.date)))
                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.orange)
        }.accessibilityLabel("Tempo restante")
    }

    private var waves: some View {
        AlbumWaveform(accent: artwork.accent, isPlaying: model.media?.isPlaying == true,
                      reduceMotion: preferences.reduceMotion || systemReduceMotion)
            .frame(width: 24, height: 18)
            .accessibilityLabel("Ondas nas cores da capa")
    }

    private var tabs: [IslandActivity] {
        let started = model.activityOrder.items
        return started + [IslandActivity.music, .timer].filter { !started.contains($0) }
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach(tabs, id: \.rawValue) { activity in
                    Button { model.timerPage = activity == .timer } label: {
                        HStack(spacing: 5) {
                            Image(systemName: activity == .music ? "music.note" : "timer")
                            if geometry.expandedWidth >= 400 { Text(activity == .music ? "Música" : "Pomodoro") }
                            if activity == .timer && model.countdown.isActive && geometry.expandedWidth >= 430 { timerIndicator }
                            if activity == .music && model.media?.isPlaying == true {
                                Circle().fill(.green).frame(width: 4, height: 4)
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background((model.timerPage == (activity == .timer)) ? .white.opacity(0.12) : .clear, in: Capsule())
                    }
                    .accessibilityLabel(activity == .music ? "Música" : "Pomodoro")
                    .accessibilityAddTraits(model.timerPage == (activity == .timer) ? .isSelected : [])
                }
                Spacer(minLength: 2)
                SettingsLink { Image(systemName: "gearshape") }
                    .accessibilityLabel("Abrir configurações")
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                    .help("Sair do Notch").accessibilityLabel("Quit — Encerrar Notch")
                Button { model.expanded = false } label: { Image(systemName: "chevron.up") }
                    .accessibilityLabel("Recolher ilha")
            }
            .font(.system(size: 11)).buttonStyle(.plain)

            if model.timerPage {
                PomodoroControls(model: model)
            } else if let media = model.media {
                HStack(spacing: 16) {
                    ArtworkView(artwork: artwork, size: 92)
                    MediaControls(media: media, model: model)
                }.frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    ArtworkView(artwork: artwork, size: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sua música aparece aqui").font(.system(size: 14, weight: .medium))
                        Text(model.errors.isEmpty ? "Inicie a reprodução no Spotify ou navegador." : "Confira as permissões em Conexões nas configurações.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }.frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 16)
    }
}

private struct ArtworkView: View {
    @ObservedObject var artwork: ArtworkStore
    let size: CGFloat

    var body: some View {
        Group {
            if let image = artwork.image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    Color(white: 0.1)
                    Image(systemName: "music.note").font(.system(size: size * 0.35, weight: .light)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 30 ? 9 : 4))
        .accessibilityLabel("Capa da música")
    }
}

private struct MediaControls: View {
    let media: MediaSnapshot
    @ObservedObject var model: AppModel
    @StateObject private var controls = MediaSeekState()

    var body: some View {
        VStack(spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                Text(media.title).font(.system(size: 14, weight: .semibold)).lineLimit(1).help(media.title)
                Text(media.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let position = media.position(at: context.date)
                VStack(spacing: 0) {
                    if media.canSeek {
                        Slider(value: Binding(get: { controls.seeking ? controls.seek : position }, set: { controls.seek = $0 }), in: 0...max(1, media.duration)) { editing in
                            if editing { controls.seek = position }
                            controls.seeking = editing
                            if !editing { model.perform(.seek(controls.seek)) }
                        }.controlSize(.mini).accessibilityLabel("Posição da música")
                    }
                    HStack {
                        Text(time(controls.seeking ? controls.seek : position))
                        Spacer()
                        Text(media.canSeek ? "−" + time(max(0, media.duration - position)) : "Ao vivo")
                    }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 22) {
                Button { model.perform(.previous) } label: { Image(systemName: "backward.end.fill") }
                    .disabled(!media.canSkip).accessibilityLabel("Música anterior")
                Button { model.perform(.togglePlayback) } label: {
                    Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22)).frame(width: 32, height: 28)
                }.accessibilityLabel(media.isPlaying ? "Pausar" : "Reproduzir")
                Button { model.perform(.next) } label: { Image(systemName: "forward.end.fill") }
                    .disabled(!media.canSkip).accessibilityLabel("Próxima música")
            }.font(.system(size: 16)).buttonStyle(.plain)
        }.disabled(model.commandBusy)
    }
}

private struct PomodoroControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ForEach(PomodoroPhase.allCases, id: \.rawValue) { phase in
                    Button { model.selectPomodoroPhase(phase) } label: {
                        Text(phase.title).font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(model.pomodoro.phase == phase ? .white.opacity(0.12) : .clear, in: Capsule())
                    }.disabled(model.countdown.isActive)
                }
                Spacer(minLength: 0)
                Text("\(model.pomodoro.completedSessions % 4)/4").font(.system(size: 10)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
            HStack(alignment: .center, spacing: 16) {
                Group {
                    if model.countdown.isActive {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(time(model.countdown.remaining(at: context.date)))
                        }
                    } else { Text("\(model.pomodoro.phase.minutes):00") }
                }.font(.system(size: 40, weight: .medium, design: .rounded)).monospacedDigit()
                Spacer(minLength: 0)
                VStack(spacing: 7) {
                    Button {
                        if model.countdown.isActive { model.toggleTimer() } else { model.startPomodoro() }
                    } label: {
                        Label(model.countdown.isActive ? (model.countdown.isPaused ? "Continuar" : "Pausar") : "Iniciar",
                              systemImage: model.countdown.isActive && !model.countdown.isPaused ? "pause.fill" : "play.fill")
                            .font(.system(size: 11, weight: .medium)).frame(width: 92, height: 28)
                            .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                    }
                    if model.countdown.isActive {
                        Button("Encerrar") { model.cancelTimer() }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            Text(model.countdown.isActive ? (model.countdown.isPaused ? "Pausado" : "A música continua tocando enquanto o tempo passa.") : (model.completionVisible ? "Etapa concluída. Inicie a próxima quando quiser." : "25 minutos por sessão · pausa longa a cada 4 sessões"))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func time(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds.isFinite ? ceil(seconds) : 0))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
    return String(format: "%d:%02d", total / 60, total % 60)
}

@MainActor private final class MediaSeekState: ObservableObject {
    @Published var seek = 0.0
    @Published var seeking = false
}
