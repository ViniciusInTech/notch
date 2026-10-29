import AppKit
import Combine
import SwiftUI
import NotchCore

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class IslandHostingView: NSHostingView<IslandView> {
    var pointerChanged: ((Bool) -> Void)?
    var pointerMoved: (() -> Void)?
    /// Screen-space test for the visible island; the window can be briefly larger while the shape animates.
    var islandContains: ((NSPoint) -> Bool)?
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(false) }
    // Catches a pointer already inside when the window resized under it and no enter event arrived.
    override func mouseMoved(with event: NSEvent) { pointerMoved?() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let window, let islandContains {
            let local = superview?.convert(point, to: nil) ?? point
            guard islandContains(window.convertPoint(toScreen: local)) else { return nil }
        }
        return super.hitTest(point)
    }
}

@MainActor final class IslandPanelController {
    private let model: AppModel
    private let panel: IslandPanel
    private let hosting: IslandHostingView
    private var subscriptions = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    private var intentTask: Task<Void, Never>?
    private var intentTarget: IslandComposition.Region?
    private var revealTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var pointerMonitors: [Any] = []
    private var lastExpanded = false
    private var targetFrame = NSRect.zero
    private var targetShape = CGSize.zero
    private var composition = IslandComposition(island: IslandSize(width: 0, height: 0), notchHeight: 32)
    private var centerX: CGFloat = 0
    private var screenTop: CGFloat = 0
    private let geometry = IslandGeometry()

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = IslandHostingView(rootView: IslandView(model: model, preferences: model.preferences, artwork: model.artwork, geometry: geometry))
        // The controller owns the window size; SwiftUI only draws the island inside it.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        hosting.pointerChanged = { [weak self] _ in self?.evaluatePointer() }
        hosting.pointerMoved = { [weak self] in self?.evaluatePointer() }
        hosting.islandContains = { [weak self] point in self.map { $0.region(at: point, margin: 0) != nil } ?? true }
        model.objectWillChange.merge(with: model.preferences.objectWillChange, geometry.$agentCardHeight.map { _ in () }.eraseToAnyPublisher())
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        update()
        panel.orderFrontRegardless()
    }

    /// Tracking areas are rebuilt whenever the window resizes (track change, assistant card), and
    /// AppKit then may never deliver the exit. While open, mouse moves anywhere re-evaluate the
    /// pointer; the monitors exist only while open, so the collapsed island stays idle.
    private func syncPointerMonitors() {
        let open = model.expanded || model.agentCardOpen
        guard open == pointerMonitors.isEmpty else { return }
        if !open {
            pointerMonitors.forEach(NSEvent.removeMonitor)
            pointerMonitors = []
            return
        }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePointer() }
        }) { pointerMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.evaluatePointer() }
            return event
        }) { pointerMonitors.append(local) }
    }

    func showExpanded() { model.expanded = true; update(); panel.orderFrontRegardless() }

    /// Inclusive bounds plus a margin: a pointer pinned to the top edge sits on the frame's
    /// maxY, so fast moves that slam into the notch must still count as inside.
    private func region(at point: NSPoint, margin: CGFloat = 6) -> IslandComposition.Region? {
        composition.region(x: point.x - centerX, y: screenTop - point.y, margin: margin)
    }

    /// One place decides what the pointer means: the island expands, the bubble (or an island
    /// that only holds an assistant request) opens the mini chat, and leaving everything closes both.
    private func evaluatePointer() {
        switch region(at: NSEvent.mouseLocation) {
        case .bubble, .card:
            cancelCollapse()
            if !model.agentCardOpen { scheduleIntent(.card) }
        case .island:
            cancelCollapse()
            if model.agentCardOpen || model.expanded { return }
            if model.agentInIsland { scheduleIntent(.card) }
            else if model.preferences.expandOnHover { scheduleIntent(.island) }
        case nil:
            intentTask?.cancel()
            intentTask = nil
            if collapseTask == nil && (model.expanded || model.agentCardOpen) { scheduleCollapse() }
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func scheduleIntent(_ target: IslandComposition.Region) {
        guard intentTask == nil || intentTarget != target else { return }
        intentTask?.cancel()
        intentTarget = target
        // A short intent delay keeps things closed when the pointer only grazes them.
        intentTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
            guard let self else { return }
            self.intentTask = nil
            guard self.region(at: NSEvent.mouseLocation) != nil else { return }
            if target == .island { self.model.expanded = true } else { self.model.openAgentCard() }
        }
    }

    private func scheduleCollapse() {
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self else { return }
            self.collapseTask = nil
            guard self.region(at: NSEvent.mouseLocation) == nil else { return }
            // A custom Keep Awake duration being typed keeps the island open, like a mini chat draft.
            if !self.model.keepAwakeEditing { self.model.expanded = false }
            self.model.closeAgentCard()
        }
    }

    private func update() {
        syncPointerMonitors()
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let notchWidth: CGFloat
        let centerX: CGFloat
        if let left, let right, screen.safeAreaInsets.top > 0 {
            notchWidth = max(100, right.minX - left.maxX)
            centerX = (left.maxX + right.minX) / 2
        } else { notchWidth = 160; centerX = screen.frame.midX }
        let height = max(28, screen.safeAreaInsets.top)
        if geometry.notchWidth != notchWidth { geometry.notchWidth = notchWidth }
        if geometry.notchHeight != height { geometry.notchHeight = height }
        let layout = IslandLayout(notchWidth: notchWidth, notchHeight: height, screenWidth: screen.frame.width)
        let expandedSize = layout.size(active: true, expanded: true)
        if geometry.expandedWidth != expandedSize.width { geometry.expandedWidth = expandedSize.width }
        if geometry.expandedHeight != expandedSize.height { geometry.expandedHeight = expandedSize.height }
        let size = layout.outerSize(active: model.active, expanded: model.expanded, activityCount: model.compactIsWide ? 2 : 1)
        let bubble = model.agentInBubble ? min(34, height - 2) : 0
        let card = model.agentCardOpen ? IslandSize(width: IslandGeometry.cardWidth, height: geometry.agentCardHeight) : nil
        let composition = IslandComposition(island: size, notchHeight: height, bubbleSize: bubble, card: card)
        self.composition = composition
        self.centerX = centerX
        screenTop = screen.frame.maxY
        if geometry.composition != composition { geometry.composition = composition }
        let frame = NSRect(x: centerX - composition.halfWidth, y: screen.frame.maxY - composition.height,
                           width: 2 * composition.halfWidth, height: composition.height)
        let shape = CGSize(width: size.width, height: size.height)
        guard frame != targetFrame || shape != targetShape else { return }
        targetShape = shape
        let initialPlacement = targetFrame == .zero
        let screenChanged = targetFrame.maxY != frame.maxY || targetFrame.midX != frame.midX
        let expansionChanged = lastExpanded != model.expanded
        lastExpanded = model.expanded
        targetFrame = frame
        revealTask?.cancel()
        settleTask?.cancel()
        if !model.expanded { geometry.expandedContentVisible = false }

        if initialPlacement || screenChanged || model.preferences.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            geometry.shapeAnimation = nil
            geometry.shapeSize = shape
            geometry.expandedContentVisible = model.expanded
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        // The window jumps to the union of the old and new sizes, transparent around the island.
        // The black shape then springs from the notch outward and down inside it, so nothing is
        // stretched by a window animation. Once a shrink settles, the window follows the shape.
        let current = panel.frame
        let unionWidth = max(current.width, frame.width), unionHeight = max(current.height, frame.height)
        let union = NSRect(x: centerX - unionWidth / 2, y: screen.frame.maxY - unionHeight, width: unionWidth, height: unionHeight)
        if union != current { panel.setFrame(union, display: false, animate: false) }
        if expansionChanged {
            geometry.shapeAnimation = model.expanded
                ? .spring(response: 0.44, dampingFraction: 0.74)
                : .spring(response: 0.32, dampingFraction: 0.92)
        } else {
            geometry.shapeAnimation = .spring(response: 0.36, dampingFraction: 0.72)
        }
        geometry.shapeSize = shape
        if union != frame {
            settleTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 520_000_000) } catch { return }
                guard let self, self.targetFrame == frame else { return }
                self.panel.setFrame(frame, display: true, animate: false)
            }
        }
        if model.expanded {
            revealTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
                guard !Task.isCancelled, let self, self.model.expanded else { return }
                self.geometry.expandedContentVisible = true
            }
        }
    }
}

@MainActor final class IslandGeometry: ObservableObject {
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var expandedWidth: CGFloat = 460
    @Published var expandedHeight: CGFloat = 128
    @Published var expandedContentVisible = false
    /// Outer size of the visible island, shoulders included; animated by the view.
    @Published var shapeSize = CGSize(width: 204, height: 32)
    var shapeAnimation: Animation?
    static let cardWidth = 420.0
    /// Bubble and mini chat placement around the island.
    @Published var composition = IslandComposition(island: IslandSize(width: 204, height: 32), notchHeight: 32)
    /// Measured by the mini chat; the window grows to fit it.
    @Published var agentCardHeight = 170.0
}
