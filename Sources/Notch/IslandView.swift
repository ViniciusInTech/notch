import SwiftUI
import AppKit
import NotchCore

private let timerTint = Color(red: 1, green: 0.62, blue: 0.04)
private let attentionTint = Color(red: 1, green: 0.84, blue: 0.04)
private let doneTint = Color(red: 0.3, green: 0.85, blue: 0.45)
private let awakeTint = Color(red: 0.37, green: 0.83, blue: 0.77)
private let meetingTint = Color(red: 0.39, green: 0.82, blue: 1)
private let joinTint = Color(red: 0.04, green: 0.52, blue: 1)
private let shelfTint = Color(red: 0.75, green: 0.61, blue: 1)
private let lowTint = Color(red: 1, green: 0.41, blue: 0.38)

/// What each side of the collapsed island shows; changing it swaps the view with a scale and blur transition.
private enum CompactSlot: Hashable {
    case artwork, waves, ring, time, music, timer, check, completionText, warning, authorize, agent, agentLabel, awake, awakeTime
    case meeting, meetingTime, call, callLabel, shelf, shelfCount, notice, noticeLabel
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
        // The window reaches past the screen's top edge; drawing starts at the screen edge.
        .padding(.top, IslandGeometry.edgeOverlap)
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
                .overlay(alignment: .topLeading) {
                    if model.inCall && preferences.callAdjust { mutedGlyph(size: size * 0.42) }
                }
                .contentShape(Circle())
                .onTapGesture { model.openAgentCard() }
                .offset(x: geometry.shapeSize.width / 2 + IslandComposition.bubbleGap + size / 2, y: layout.bubbleMinY)
                .animation(geometry.shapeAnimation, value: geometry.shapeSize)
                .transition(reduce ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
        }
    }

    /// Marks a notification that arrived silently during a call.
    private func mutedGlyph(size: CGFloat) -> some View {
        Image(systemName: "bell.slash.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.75))
            .frame(width: size, height: size)
            .background(Circle().fill(.black))
            .offset(x: -size * 0.15, y: -size * 0.1)
            .accessibilityLabel("Silenciado durante a chamada")
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
        } else if model.compactShown, let panel = model.compactPanel {
            CompactBand(panel: panel, model: model, preferences: preferences, artwork: artwork,
                        notchWidth: geometry.notchWidth, reduce: reduce)
                .frame(width: geometry.compactWidth)
                .id(panel)
                .transition(reduce ? .opacity : AnyTransition(.blurReplace))
        } else {
            HStack(spacing: 0) {
                ear(leftSlot, cup: cupBadge == .left)
                Color.clear.frame(width: geometry.notchWidth)
                ear(rightSlot, cup: cupBadge == .right, meeting: meetingBadge, shelf: shelfBadge)
            }
            .animation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: [leftSlot, rightSlot])
            .animation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: cupBadge)
            .animation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: meetingBadge)
            .animation(reduce ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: shelfBadge)
            .accessibilityElement(children: .combine)
        }
    }

    private var leftSlot: CompactSlot? {
        guard model.active else { return nil }
        if model.agentInIsland { return .agent }
        if model.callNoticeVisible { return .call }
        if model.notice != nil { return .notice }
        if model.showsAttention { return .warning }
        if model.completionVisible { return .check }
        let items = model.activityOrder.items
        if items.isEmpty && model.meeting != nil { return .meeting }
        if items.isEmpty && model.keepAwakeVisible { return .awake }
        if items.isEmpty && model.shelfVisible && model.media?.isPlaying != true { return .shelf }
        if items.count == 2 { return items[0] == .music ? .music : .timer }
        return model.countdown.isActive ? .ring : .artwork
    }

    private var rightSlot: CompactSlot? {
        guard model.active else { return nil }
        if model.agentInIsland { return .agentLabel }
        if model.callNoticeVisible { return .callLabel }
        if model.notice != nil { return .noticeLabel }
        if model.showsAttention { return .authorize }
        if model.completionVisible { return .completionText }
        let items = model.activityOrder.items
        if items.isEmpty && model.meeting != nil { return .meetingTime }
        if items.isEmpty && model.keepAwakeVisible { return .awakeTime }
        if items.isEmpty && model.shelfVisible && model.media?.isPlaying != true { return .shelfCount }
        if items.count == 2 { return items[1] == .music ? .music : .timer }
        return model.countdown.isActive ? .time : .waves
    }

    private enum EarSide { case left, right }

    /// Keep Awake beside music or a timer: a small cup on the outer edge of the right ear,
    /// next to the waves or the time.
    private var cupBadge: EarSide? {
        guard model.keepAwakeVisible, !model.completionVisible, !model.showsAttention, !model.agentInIsland,
              !model.callNoticeVisible, model.notice == nil,
              !(model.activityOrder.items.isEmpty && model.meeting == nil) else { return nil }
        return .right
    }

    /// The shelf beside another activity: a small tray with the count on the right ear.
    private var shelfBadge: Bool {
        guard model.shelfVisible, !model.completionVisible, !model.showsAttention, !model.agentInIsland,
              !model.callNoticeVisible, model.notice == nil else { return false }
        return !model.activityOrder.items.isEmpty || model.meeting != nil || model.keepAwakeVisible
    }

    /// The meeting beside music or a timer: a small calendar with the minutes left, like the cup.
    private var meetingBadge: Bool {
        model.meeting != nil && !model.activityOrder.items.isEmpty && !model.completionVisible
            && !model.showsAttention && !model.agentInIsland && !model.callNoticeVisible && model.notice == nil
    }

    private func ear(_ slot: CompactSlot?, cup: Bool, meeting: Bool = false, shelf: Bool = false) -> some View {
        HStack(spacing: 6) {
            if cup && slot != nil && cupBadge == .left { cupGlyph }
            ZStack {
                if let slot {
                    slotView(slot)
                        .id(slot)
                        .transition(reduce ? .opacity : .modifier(active: EarEntrance(shown: false), identity: EarEntrance(shown: true)))
                }
            }
            if cup && slot != nil && cupBadge == .right { cupGlyph }
            if meeting && slot != nil { meetingGlyph }
            if shelf && slot != nil {
                HStack(spacing: 2) {
                    Image(systemName: "tray.full.fill").font(.system(size: 9.5, weight: .semibold))
                    Text("\(model.shelf.items.count)").font(.system(size: 10, weight: .bold)).monospacedDigit()
                }
                .foregroundStyle(shelfTint)
                .transition(reduce ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                .accessibilityLabel("\(model.shelf.items.count) itens na bandeja")
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var meetingGlyph: some View {
        if let meeting = model.meeting {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 2) {
                    Image(systemName: "calendar").font(.system(size: 9.5, weight: .semibold))
                    if meeting.phase == .soon {
                        Text("\(meeting.minutesLeft(at: context.date))").font(.system(size: 10, weight: .bold)).monospacedDigit()
                    }
                }
                .foregroundStyle(meeting.phase == .now ? timerTint : meetingTint)
            }
            .transition(reduce ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            .accessibilityLabel(meeting.phase == .now ? "\(meeting.meeting.title) agora" : "\(meeting.meeting.title) em breve")
        }
    }

    private var cupGlyph: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: 9.5, weight: .semibold)).foregroundStyle(awakeTint)
            .transition(reduce ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            .accessibilityLabel("Mantendo o Mac acordado")
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
        case .awake:
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(awakeTint)
                .accessibilityLabel("Mantendo o Mac acordado")
        case .awakeTime:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let remaining = model.keepAwake?.remaining(at: context.date) {
                    CountingText(text: KeepAwakeFormat.compact(remaining), reduce: reduce)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(awakeTint)
                } else {
                    Image(systemName: "infinity").font(.system(size: 12, weight: .bold)).foregroundStyle(awakeTint)
                }
            }
            .accessibilityLabel("Tempo acordado restante")
        case .meeting:
            if let meeting = model.meeting {
                HStack(spacing: 6) {
                    if meeting.phase == .now { Circle().fill(timerTint).frame(width: 6, height: 6) }
                    else { Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(meetingTint) }
                    Text(meeting.meeting.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                }
                .padding(.leading, 4)
            }
        case .meetingTime:
            if let meeting = model.meeting {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(meeting.phase == .now ? "agora" : "em \(meeting.minutesLeft(at: context.date)) min")
                        .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(meeting.phase == .now ? timerTint : meetingTint)
                        .lineLimit(1)
                }
            }
        case .call:
            HStack(spacing: 4) {
                Image(systemName: "video.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(doneTint)
                Text("Em chamada").font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .callLabel:
            HStack(spacing: 4) {
                Image(systemName: preferences.callAlertMode == .banner ? "speaker.slash.fill" : "bell.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(preferences.callAlertMode.label).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white.opacity(0.7))
        case .shelf:
            Image(systemName: "tray.full.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(shelfTint)
                .accessibilityLabel("Bandeja")
        case .shelfCount:
            Text("\(model.shelf.items.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(shelfTint)
                .accessibilityLabel("\(model.shelf.items.count) itens")
        case .notice:
            if let notice = model.notice { NoticeLeading(notice: notice, shelf: model.shelf) }
        case .noticeLabel:
            if let notice = model.notice { NoticeTrailing(notice: notice) }
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

    private var tabs: [IslandPage] {
        let started = model.activityOrder.items.map { $0 == .music ? IslandPage.music : .timer }
        return started + [IslandPage.music, .timer].filter { !started.contains($0) } + [.keepAwake]
            + (preferences.shelfEnabled ? [.shelf] : [])
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { activity in
                let selected = model.page == activity
                Button {
                    withAnimation(reduce ? nil : .spring(response: 0.34, dampingFraction: 0.8)) { model.page = activity }
                } label: {
                    Image(systemName: activity.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                        .frame(width: 30, height: 22)
                        .background {
                            if selected { Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: tabNamespace) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if activity == .music && model.media?.isPlaying == true { activityDot(.green) }
                            else if activity == .timer && model.countdown.isActive { activityDot(timerTint) }
                            else if activity == .keepAwake && model.keepAwake != nil { activityDot(awakeTint) }
                            else if activity == .shelf && !model.shelf.items.isEmpty { activityDot(shelfTint) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(activity.title)
                .accessibilityLabel(activity.title)
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
            if model.shelfDropTarget {
                DropPanel(count: model.shelf.items.count).transition(panelTransition)
            } else if model.page == .shelf {
                ShelfPanel(model: model, shelf: model.shelf, visible: visible, reduce: reduce).transition(panelTransition)
            } else if model.page == .timer {
                PomodoroPanel(model: model, preferences: preferences, visible: visible, reduce: reduce).transition(panelTransition)
            } else if model.page == .keepAwake {
                KeepAwakePanel(model: model, preferences: preferences, visible: visible, reduce: reduce).transition(panelTransition)
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

// MARK: - Keep awake

/// Same rhythm as the other tabs: ring, time and control in one row; quick durations below.
/// "Outro" swaps the row for a quantity and unit, keeping the island's height.
private struct KeepAwakePanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    let visible: Bool
    let reduce: Bool
    @StateObject private var draft = KeepAwakeDraft()
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ZStack {
                        ProgressRing(progress: model.keepAwake?.progress(at: context.date) ?? 0, lineWidth: 4, reduce: reduce, tint: awakeTint)
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(model.keepAwake == nil ? Color.white.opacity(0.45) : awakeTint)
                    }
                }
                .frame(width: 50, height: 50)
                .accessibilityHidden(true)
                .reveal(visible, order: 1, reduce: reduce)

                VStack(alignment: .leading, spacing: 0) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        headline(at: context.date)
                    }
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .reveal(visible, order: 2, reduce: reduce)
                Spacer(minLength: 6)
                controls.reveal(visible, order: 2, reduce: reduce)
            }
            ZStack(alignment: .leading) {
                if model.keepAwakeEditing { editor.transition(.opacity) } else { presets.transition(.opacity) }
            }
            .frame(height: 22)
            .animation(reduce ? nil : .easeOut(duration: 0.15), value: model.keepAwakeEditing)
            .reveal(visible, order: 3, reduce: reduce)
        }
        .onAppear { draft.load(preferences) }
    }

    @ViewBuilder private func headline(at date: Date) -> some View {
        if let session = model.keepAwake, let remaining = session.remaining(at: date) {
            CountingText(text: KeepAwakeFormat.clock(remaining), reduce: reduce)
                .font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(awakeTint)
                .accessibilityLabel("Tempo acordado restante")
        } else {
            Text(model.keepAwake == nil ? "Desligado" : "Sem limite")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(model.keepAwake == nil ? Color.white : awakeTint)
                .frame(height: 31, alignment: .leading)
        }
    }

    private var subtitle: String {
        guard let session = model.keepAwake else { return "O Mac dorme normalmente" }
        let screen = preferences.keepAwakeAllowDisplaySleep ? "a tela pode apagar" : "tela acesa"
        guard let deadline = session.deadline else { return "Até você desligar · \(screen)" }
        return "Até \(until(deadline)) · \(screen)"
    }

    @ViewBuilder private var controls: some View {
        if model.keepAwake != nil {
            Button { model.stopKeepAwake() } label: {
                Image(systemName: "stop.fill").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(0.1)))
            }
            .buttonStyle(PressableStyle())
            .help("Desligar")
            .accessibilityLabel("Desligar manter acordado")
        } else {
            let minutes = preferences.keepAwakeDefault
            Button { model.startKeepAwake(minutes: minutes) } label: { Label("Ligar", systemImage: "play.fill") }
                .buttonStyle(PillButtonStyle(fill: awakeTint, height: 30))
                .help(minutes > 0 ? "Manter acordado por \(KeepAwakeFormat.label(minutes: minutes))" : "Manter acordado sem limite")
        }
    }

    private var presets: some View {
        let current = model.keepAwake?.minutes
        let customMinutes = preferences.keepAwakeCustomUnit.minutes(preferences.keepAwakeCustomQuantity)
        let customSelected = preferences.keepAwakeCustomUsed && current == customMinutes && !preferences.keepAwakePresets.contains(customMinutes)
        return HStack(spacing: 2) {
            ForEach(preferences.keepAwakePresets, id: \.self) { minutes in
                chip(KeepAwakeFormat.chip(minutes: minutes), selected: current == minutes,
                     accessibility: KeepAwakeFormat.label(minutes: minutes)) { model.startKeepAwake(minutes: minutes) }
            }
            chip("Sempre", selected: current == 0, accessibility: "Sem limite") { model.startKeepAwake(minutes: 0) }
            Spacer(minLength: 6)
            Button {
                draft.load(preferences)
                model.keepAwakeEditing = true
                DispatchQueue.main.async { typing = true }
            } label: {
                Text(preferences.keepAwakeCustomUsed ? KeepAwakeFormat.chip(minutes: customMinutes) : "Outro")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(customSelected ? awakeTint : Color.white.opacity(0.75))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(customSelected ? awakeTint.opacity(0.16) : .clear, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Escolher outra duração")
            .accessibilityLabel("Outra duração")
        }
    }

    private func chip(_ title: String, selected: Bool, accessibility: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? awakeTint : Color.white.opacity(0.55))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(selected ? awakeTint.opacity(0.16) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Manter acordado por \(accessibility)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var editor: some View {
        HStack(spacing: 6) {
            TextField("", text: Binding(get: { draft.text }, set: { draft.text = String($0.filter(\.isNumber).prefix(5)) }))
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .multilineTextAlignment(.center)
                .focused($typing)
                .onSubmit(apply)
                .frame(width: 40, height: 20)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("Quantidade")
            HStack(spacing: 0) {
                ForEach(KeepAwakeUnit.allCases, id: \.self) { unit in
                    let selected = draft.unit == unit
                    Button { draft.unit = unit } label: {
                        Text(unit.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
                            .padding(.horizontal, 8).frame(height: 16)
                            .background(selected ? Color.white.opacity(0.18) : .clear, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(unit.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(2)
            .background(.white.opacity(0.08), in: Capsule())
            Spacer(minLength: 4)
            Text(draft.minutes.map { "Até \(until(Date().addingTimeInterval(Double($0) * 60)))" } ?? "")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            Button("Ligar", action: apply)
                .buttonStyle(PillButtonStyle(fill: awakeTint, height: 20))
                .disabled(draft.minutes == nil)
            Button { model.keepAwakeEditing = false } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.08)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Cancelar")
        }
        .onExitCommand { model.keepAwakeEditing = false }
    }

    private func apply() {
        guard let quantity = Int(draft.text), quantity > 0 else { return }
        let clamped = min(draft.unit.maximumQuantity, quantity)
        preferences.keepAwakeCustomQuantity = clamped
        preferences.keepAwakeCustomUnit = draft.unit
        preferences.keepAwakeCustomUsed = true
        model.startKeepAwake(minutes: draft.unit.minutes(clamped))
    }

    /// The interface is in Portuguese, so dates follow it rather than the system's language.
    private func until(_ date: Date) -> String {
        let style = Date.FormatStyle(locale: Locale(identifier: "pt_BR"))
        return Calendar.current.isDateInToday(date)
            ? date.formatted(style.hour().minute())
            : date.formatted(style.weekday(.abbreviated).day().month(.twoDigits).hour().minute())
    }
}

@MainActor private final class KeepAwakeDraft: ObservableObject {
    @Published var text = ""
    @Published var unit = KeepAwakeUnit.hours

    var minutes: Int? { Int(text).flatMap { $0 > 0 ? unit.minutes($0) : nil } }

    func load(_ preferences: Preferences) {
        text = String(preferences.keepAwakeCustomQuantity)
        unit = preferences.keepAwakeCustomUnit
    }
}

extension KeepAwakeUnit {
    var title: String {
        switch self { case .minutes: return "min"; case .hours: return "h"; case .days: return "dias" }
    }
}

private extension IslandPage {
    var symbol: String {
        switch self {
        case .music: return "music.note"; case .timer: return "timer"; case .keepAwake: return "cup.and.saucer.fill"
        case .shelf: return "tray.full.fill"
        }
    }

    var title: String {
        switch self {
        case .music: return "Música"; case .timer: return "Pomodoro"; case .keepAwake: return "Manter acordado"
        case .shelf: return "Bandeja"
        }
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
    var tint = timerTint

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
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
    /// Dark text on light fills; a saturated fill takes white text instead.
    var dark = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: fill == nil ? .semibold : .bold))
            .foregroundStyle(fill == nil || !dark ? Color.white.opacity(fill == nil ? 0.85 : 1) : Color.black.opacity(0.85))
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

extension CallAlertMode {
    var label: String {
        switch self { case .silent: return "Silencioso"; case .banner: return "Sem som"; case .pause: return "Pausados" }
    }
}

// MARK: - Compact hover

/// The island widened at the notch height: one activity on the left, its controls on the right.
private struct CompactBand: View {
    let panel: CompactPanel
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var artwork: ArtworkStore
    let notchWidth: CGFloat
    let reduce: Bool

    var body: some View {
        HStack(spacing: 0) {
            leading.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            Color.clear.frame(width: notchWidth)
            trailing.frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 8)
        }
    }

    @ViewBuilder private var leading: some View {
        switch panel {
        case .music:
            if let media = model.media {
                HStack(spacing: 8) {
                    ArtworkView(artwork: artwork, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(media.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(media.canSeek ? "\(media.artist) · \(time(media.position(at: context.date))) / \(time(media.duration))" : media.artist)
                                .monospacedDigit()
                        }
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        case .timer:
            HStack(spacing: 7) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 7) {
                        ProgressRing(progress: model.timerProgress(at: context.date), lineWidth: 2.4, reduce: reduce)
                            .frame(width: 14, height: 14)
                        CountingText(text: time(model.countdown.remaining(at: context.date)), reduce: reduce)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(timerTint)
                    }
                }
                Text(timerSubtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        case .keepAwake:
            HStack(spacing: 7) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(awakeTint)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let remaining = model.keepAwake?.remaining(at: context.date) {
                        CountingText(text: KeepAwakeFormat.compact(remaining), reduce: reduce)
                    } else {
                        Text("Sempre")
                    }
                }
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(awakeTint)
            }
            .accessibilityElement(children: .combine)
        case .drop:
            dropZone {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 11, weight: .semibold))
                Text("Solte para guardar")
            }
        case .download:
            if let url = model.recentDownload {
                HStack(spacing: 8) {
                    ShelfIcon(path: url.path, shelf: model.shelf, size: 22)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(url.lastPathComponent).font(.system(size: 11.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Text(downloadSubtitle(url)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        case .shelf:
            HStack(spacing: 7) {
                ForEach(model.shelf.items.prefix(4)) { item in ShelfThumb(item: item, shelf: model.shelf, size: 22) }
            }
        case .meeting:
            if let meeting = model.meeting {
                HStack(spacing: 8) {
                    if meeting.phase == .now { Circle().fill(timerTint).frame(width: 7, height: 7) }
                    else { Image(systemName: "calendar").font(.system(size: 13, weight: .semibold)).foregroundStyle(meetingTint) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(meeting.meeting.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        Text(meetingSubtitle(meeting.meeting)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 2) {
            trailingControls
            if panel != .drop && model.compactPanels.count > 1 {
                Button { model.cycleCompactPanel() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.55)).frame(width: 20, height: 26)
                }
                .buttonStyle(.plain)
                .help("Próxima atividade")
                .accessibilityLabel("Mostrar a próxima atividade")
            }
        }
    }

    @ViewBuilder private var trailingControls: some View {
        switch panel {
        case .drop:
            dropZone {
                Text(model.shelf.items.isEmpty ? "Bandeja vazia" : "Bandeja · \(model.shelf.items.count) \(model.shelf.items.count == 1 ? "item" : "itens")")
            }
        case .download:
            HStack(spacing: 2) {
                Button("Abrir") { model.openRecentDownload() }.buttonStyle(PillButtonStyle(height: 22))
                iconButton("magnifyingglass", size: 11, label: "Mostrar no Finder") { model.revealRecentDownload() }
                iconButton("tray.and.arrow.down.fill", size: 11, label: "Guardar na bandeja") { model.shelveRecentDownload() }
                    .foregroundStyle(shelfTint)
            }
        case .shelf:
            let items = model.shelf.items
            HStack(spacing: 6) {
                ForEach(items.dropFirst(4).prefix(2)) { item in ShelfThumb(item: item, shelf: model.shelf, size: 22) }
                if items.count > 6 { Text("+\(items.count - 6)").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8)) }
                iconButton("xmark", size: 10, label: "Limpar bandeja") { model.shelf.clear() }
            }
        case .music:
            if let media = model.media {
                HStack(spacing: 2) {
                    iconButton("backward.end.fill", size: 12, label: "Música anterior") { model.perform(.previous) }
                        .disabled(!media.canSkip)
                    iconButton(media.isPlaying ? "pause.fill" : "play.fill", size: 14, label: media.isPlaying ? "Pausar" : "Reproduzir") {
                        model.perform(.togglePlayback)
                    }
                    iconButton("forward.end.fill", size: 12, label: "Próxima música") { model.perform(.next) }
                        .disabled(!media.canSkip)
                }
                .disabled(model.commandBusy)
            }
        case .timer:
            HStack(spacing: 2) {
                iconButton(model.countdown.isPaused ? "play.fill" : "pause.fill", size: 13,
                           label: model.countdown.isPaused ? "Continuar" : "Pausar") { model.toggleTimer() }
                if model.timerIsPomodoro {
                    iconButton("forward.end.fill", size: 12, label: "Pular etapa") { model.skipPomodoroPhase() }
                }
                iconButton("xmark", size: 11, label: "Encerrar") { model.cancelTimer() }
            }
        case .keepAwake:
            HStack(spacing: 4) {
                if model.keepAwake?.isIndefinite == false {
                    Button("+1 h") { model.extendKeepAwake(minutes: 60) }
                        .buttonStyle(PillButtonStyle(height: 22))
                        .accessibilityLabel("Mais uma hora acordado")
                }
                iconButton("power", size: 12, label: "Desligar") { model.stopKeepAwake() }
            }
        case .meeting:
            HStack(spacing: 4) {
                if model.meeting?.meeting.link != nil {
                    Button { model.joinMeeting() } label: {
                        Label("Entrar", systemImage: "video.fill").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PillButtonStyle(fill: joinTint, height: 22, dark: false))
                }
                iconButton("xmark", size: 11, label: "Dispensar") { model.dismissMeeting() }
            }
        }
    }

    private func dropZone<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6, content: content)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity).frame(height: 24)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .padding(.trailing, 4)
    }

    private func downloadSubtitle(_ url: URL) -> String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return size.map { "\(ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)) · Downloads" } ?? "Downloads"
    }

    private func iconButton(_ symbol: String, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).frame(width: 26, height: 26)
        }
        .buttonStyle(IconButtonStyle())
        .help(label)
        .accessibilityLabel(label)
    }

    private var timerSubtitle: String {
        if model.countdown.isPaused { return "Pausado" }
        guard model.timerIsPomodoro else { return "Timer" }
        let settings = preferences.pomodoro
        switch model.pomodoro.phase {
        case .work: return "Foco · \(min(model.pomodoro.completedSessions + 1, settings.sessions)) de \(settings.sessions)"
        case .shortBreak: return "Pausa"
        case .longBreak: return "Pausa longa"
        }
    }

    private func meetingSubtitle(_ meeting: Meeting) -> String {
        let hours = "\(meeting.start.formatted(date: .omitted, time: .shortened))–\(meeting.end.formatted(date: .omitted, time: .shortened))"
        return meeting.link == nil ? hours : hours + " · vídeo"
    }
}

// MARK: - Shelf

/// A file's preview, from Quick Look once ready; the type's icon until then.
private struct ShelfIcon: View {
    let path: String
    @ObservedObject var shelf: ShelfStore
    let size: CGFloat

    var body: some View {
        Image(nsImage: shelf.thumbnail(for: ShelfItem(path: path)))
            .resizable().aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
    }
}

/// A shelf item that can be dragged out, clicked to open or right-clicked for more.
private struct ShelfThumb: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    let size: CGFloat

    var body: some View {
        ShelfIcon(path: item.path, shelf: shelf, size: size)
            .overlay(ShelfDragHandle(item: item, shelf: shelf))
            .help(item.name)
            .accessibilityLabel(item.name)
    }
}

private struct ShelfDragHandle: NSViewRepresentable {
    let item: ShelfItem
    let shelf: ShelfStore

    func makeNSView(context: Context) -> HandleView { HandleView() }

    func updateNSView(_ view: HandleView, context: Context) {
        view.item = item
        view.shelf = shelf
    }

    final class HandleView: NSView {
        var item: ShelfItem?
        weak var shelf: ShelfStore?
        private var pressed: NSPoint?
        private var dragging = false

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            pressed = event.locationInWindow
            dragging = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragging, let pressed, let item else { return }
            let point = event.locationInWindow
            guard hypot(point.x - pressed.x, point.y - pressed.y) > 3 else { return }
            dragging = true
            ShelfDragCoordinator.shared.begin(item, from: self, event: event)
        }

        override func mouseUp(with event: NSEvent) {
            defer { pressed = nil }
            guard !dragging, let item, let url = shelf?.resolvedURL(item) else { return }
            NSWorkspace.shared.open(url)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            menu.addItem(withTitle: "Abrir", action: #selector(open), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Mostrar no Finder", action: #selector(reveal), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Remover da bandeja", action: #selector(remove), keyEquivalent: "").target = self
            return menu
        }

        @objc private func open() {
            if let item, let url = shelf?.resolvedURL(item) { NSWorkspace.shared.open(url) }
        }

        @objc private func reveal() {
            if let item, let url = shelf?.resolvedURL(item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }

        @objc private func remove() {
            if let item { shelf?.remove(item.id) }
        }
    }
}

/// The shelf tab of the open island: items in a row, then share and clear.
private struct ShelfPanel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var shelf: ShelfStore
    let visible: Bool
    let reduce: Bool

    var body: some View {
        HStack(spacing: 10) {
            if shelf.items.isEmpty {
                Image(systemName: "tray").font(.system(size: 28, weight: .light)).foregroundStyle(shelfTint)
                    .frame(width: 50, height: 50)
                    .reveal(visible, order: 1, reduce: reduce)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bandeja vazia").font(.system(size: 13.5, weight: .semibold))
                    Text("Arraste arquivos até o notch para guardar e puxe de volta onde quiser.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                .reveal(visible, order: 2, reduce: reduce)
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(shelf.items) { item in
                            VStack(spacing: 4) {
                                ShelfThumb(item: item, shelf: shelf, size: 36)
                                Text(item.name).font(.system(size: 9.5)).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle).frame(width: 58)
                            }
                            .frame(width: 60)
                        }
                    }
                }
                .reveal(visible, order: 1, reduce: reduce)
                VStack(spacing: 6) {
                    ShareLink(items: shelf.items.map(\.url)) {
                        Label("Compartilhar", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PillButtonStyle(height: 24))
                    Button("Limpar") { shelf.clear() }.buttonStyle(PillButtonStyle(height: 24))
                }
                .fixedSize()
                .reveal(visible, order: 2, reduce: reduce)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - Notices

private struct NoticeLeading: View {
    let notice: IslandNotice
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        switch notice {
        case .screenshot(let count, let path):
            ZStack {
                if count > 1 {
                    ShelfIcon(path: path, shelf: shelf, size: 22).opacity(0.5).offset(x: 5, y: -2)
                }
                ShelfIcon(path: path, shelf: shelf, size: 22)
            }
            .accessibilityLabel("Captura de tela")
        case .download(let path):
            HStack(spacing: 6) {
                ShelfIcon(path: path, shelf: shelf, size: 18)
                Text((path as NSString).lastPathComponent).font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 74)
            }
        case .power(let event):
            HStack(spacing: 4) {
                switch event {
                case .connected:
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(doneTint)
                    Text("Carregando").foregroundStyle(doneTint)
                case .charged:
                    Image(systemName: "bolt.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(doneTint)
                    Text("Carregado").foregroundStyle(doneTint)
                case .disconnected(_, let minutes):
                    Text("Na bateria")
                    if let minutes { Text("· \(minutes / 60)h\(String(format: "%02d", minutes % 60))").foregroundStyle(.secondary) }
                case .low:
                    Text("Bateria fraca").foregroundStyle(lowTint)
                }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .lineLimit(1)
        }
    }
}

private struct NoticeTrailing: View {
    let notice: IslandNotice

    var body: some View {
        switch notice {
        case .screenshot(let count, _):
            Text(count > 1 ? "\(count) prints" : "Na bandeja")
                .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(shelfTint).lineLimit(1)
        case .download:
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 11, weight: .semibold))
                Text("Baixado").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(doneTint)
        case .power(let event):
            let level = Self.level(event)
            let tint: Color = { if case .low = event { return lowTint }; if case .disconnected = event { return .white }; return doneTint }()
            HStack(spacing: 4) {
                Text("\(level)%").font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                Image(systemName: Self.symbol(level: level, charging: { if case .connected = event { return true }; return false }()))
                    .font(.system(size: 13)).foregroundStyle(tint)
            }
            .foregroundStyle(tint == .white ? Color.white : tint)
        }
    }

    private static func level(_ event: PowerEvent) -> Int {
        switch event {
        case .connected(let level), .disconnected(let level, _), .low(let level): return level
        case .charged: return 100
        }
    }

    private static func symbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

/// Shown while a drag is near: the whole open area receives the drop, below the top edge.
private struct DropPanel: View {
    let count: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20, weight: .semibold)).foregroundStyle(shelfTint)
            Text("Solte para guardar na bandeja").font(.system(size: 13, weight: .semibold))
            Text(count == 0 ? "Fica só a referência ao arquivo" : "\(count) \(count == 1 ? "item" : "itens") na bandeja")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(shelfTint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(shelfTint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .accessibilityElement(children: .combine)
    }
}
