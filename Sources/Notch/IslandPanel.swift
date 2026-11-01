import AppKit
import Combine
import SwiftUI
import NotchCore
import os

private let dropLog = Logger(subsystem: "dev.vinicius.Notch", category: "shelf")

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    /// The frame extends past the top of the screen on purpose; AppKit must not pull it back.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
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

/// The window's content view: it receives drops for the shelf, so SwiftUI's own drag
/// registration inside the hosting view can never take them over. Outside the island it lets
/// clicks and drags through to the apps below.
private final class IslandDropView: NSView {
    var islandContains: ((NSPoint) -> Bool)?
    /// Drops onto the notch: entering, leaving, and the pasteboard to read on release.
    var dropTargeted: ((Bool) -> Void)?
    var dropPerformed: ((NSPasteboard) -> Bool)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let window, let islandContains {
            let local = superview?.convert(point, to: nil) ?? point
            guard islandContains(window.convertPoint(toScreen: local)) else { return nil }
        }
        return super.hitTest(point)
    }

    private func accepts(_ sender: NSDraggingInfo) -> Bool {
        // Drags that start on the shelf itself are not dropped back onto it.
        dropPerformed != nil && sender.draggingSource == nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropLog.info("drag entered accepts=\(self.accepts(sender))")
        guard accepts(sender) else { return [] }
        dropTargeted?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender) ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { dropTargeted?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropTargeted?(false) }
        let accepted = dropPerformed?(sender.draggingPasteboard) ?? false
        dropLog.info("drop accepted=\(accepted)")
        return accepted
    }
    override func wantsPeriodicDraggingUpdates() -> Bool { false }
}

@MainActor final class IslandPanelController {
    private let model: AppModel
    private let panel: IslandPanel
    private let hosting: IslandHostingView
    private let dropView = IslandDropView()
    private var dragMonitors: [Any] = []
    /// Drag pasteboard generation at the last mouse down; a change while dragging means a
    /// file or content drag is in flight, not a window move or a text selection.
    private var pressGeneration = 0
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
        dropView.autoresizingMask = [.width, .height]
        hosting.frame = dropView.bounds
        dropView.addSubview(hosting)
        panel.contentView = dropView
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
        dropView.islandContains = hosting.islandContains
        dropView.dropTargeted = { [weak self] inside in
            guard let self else { return }
            if inside { self.model.beginDropApproach() }
            else if !self.dropNear(NSEvent.mouseLocation) { self.model.endDropApproach() }
        }
        model.preferences.$shelfEnabled.receive(on: RunLoop.main).sink { [weak self] enabled in
            guard let self else { return }
            if enabled {
                self.dropView.registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
                self.dropView.dropPerformed = { [weak self] pasteboard in self?.model.receiveDrop(pasteboard) ?? false }
            } else {
                self.dropView.unregisterDraggedTypes()
                self.dropView.dropPerformed = nil
            }
            self.syncDragMonitors(enabled)
        }.store(in: &subscriptions)
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
        let open = model.expanded || model.agentCardOpen || model.compactOpen
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

    /// Opens the drop area while a drag is still on its way, so the target is already there
    /// below the edge; a drag that reaches the top edge with nothing under it opens Mission Control.
    /// The monitors only see events while a mouse button is down.
    private func syncDragMonitors(_ enabled: Bool) {
        guard enabled == dragMonitors.isEmpty else { return }
        if !enabled {
            dragMonitors.forEach(NSEvent.removeMonitor)
            dragMonitors = []
            return
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp], handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.trackDrag(type) }
        }) { dragMonitors.append(monitor) }
    }

    private func trackDrag(_ type: NSEvent.EventType) {
        let generation = NSPasteboard(name: .drag).changeCount
        switch type {
        case .leftMouseDown:
            pressGeneration = generation
        case .leftMouseDragged:
            guard generation != pressGeneration else { return }
            let near = dropNear(NSEvent.mouseLocation)
            if near && !model.shelfDropTarget { model.beginDropApproach() }
            else if !near && model.shelfDropTarget { model.endDropApproach() }
        default:
            // A drop clears the target itself; this covers drags released elsewhere.
            if model.shelfDropTarget {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    if self?.model.shelfDropTarget == true { self?.model.endDropApproach() }
                }
            }
        }
    }

    /// Around the open panel, with a wider margin to open than to stay open.
    private func dropNear(_ point: NSPoint) -> Bool {
        let margin: CGFloat = model.shelfDropTarget ? 70 : 50
        let depth = model.shelfDropTarget ? geometry.expandedHeight + margin : 180
        return abs(point.x - centerX) <= geometry.expandedWidth / 2 + margin && screenTop - point.y <= depth
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
        // While a drag is near, the drop area stays open whatever the pointer does.
        if model.shelfDropTarget { cancelCollapse(); intentTask?.cancel(); intentTask = nil; return }
        switch region(at: NSEvent.mouseLocation) {
        case .bubble, .card:
            cancelCollapse()
            if !model.agentCardOpen { scheduleIntent(.card) }
        case .island:
            cancelCollapse()
            if model.agentCardOpen || model.expanded || model.compactOpen { return }
            if model.agentInIsland { scheduleIntent(.card) }
            // The compact hover needs an activity to show; an idle island waits for a click.
            else if model.preferences.expandOnHover && (!model.preferences.compactHover || model.compactPanel != nil) {
                scheduleIntent(.island)
            }
        case nil:
            intentTask?.cancel()
            intentTask = nil
            if collapseTask == nil && (model.expanded || model.agentCardOpen || model.compactOpen) { scheduleCollapse() }
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
            if target == .card { self.model.openAgentCard() }
            else if self.model.preferences.compactHover { self.model.compactOpen = self.model.compactPanel != nil }
            else { self.model.expanded = true }
        }
    }

    private func scheduleCollapse() {
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
            guard let self else { return }
            self.collapseTask = nil
            guard self.region(at: NSEvent.mouseLocation) == nil, !self.model.shelfDropTarget else { return }
            // A custom Keep Awake duration being typed keeps the island open, like a mini chat draft.
            if !self.model.keepAwakeEditing { self.model.expanded = false }
            self.model.compactOpen = false
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
        let compactWidth = layout.size(active: true, expanded: false, compact: true).width
        if geometry.compactWidth != compactWidth { geometry.compactWidth = compactWidth }
        let size = layout.outerSize(active: model.active, expanded: model.expanded, activityCount: model.compactIsWide ? 2 : 1,
                                    compact: model.compactShown)
        let bubble = model.agentInBubble ? min(34, height - 2) : 0
        let card = model.agentCardOpen ? IslandSize(width: IslandGeometry.cardWidth, height: geometry.agentCardHeight) : nil
        let composition = IslandComposition(island: size, notchHeight: height, bubbleSize: bubble, card: card)
        self.composition = composition
        self.centerX = centerX
        screenTop = screen.frame.maxY
        if geometry.composition != composition { geometry.composition = composition }
        // A pointer pinned to the top edge reports y == maxY, outside a frame ending there. With the
        // extra point it stays over the island, so a drag at the edge reaches the shelf instead of
        // falling through to Mission Control.
        let edge = IslandGeometry.edgeOverlap
        let frame = NSRect(x: centerX - composition.halfWidth, y: screen.frame.maxY - composition.height,
                           width: 2 * composition.halfWidth, height: composition.height + edge)
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
        let union = NSRect(x: centerX - unionWidth / 2, y: screen.frame.maxY + edge - unionHeight, width: unionWidth, height: unionHeight)
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
    /// Inner width of the compact hover; its content keeps this width while the shape grows.
    @Published var compactWidth: CGFloat = 480
    @Published var expandedContentVisible = false
    /// Outer size of the visible island, shoulders included; animated by the view.
    @Published var shapeSize = CGSize(width: 204, height: 32)
    var shapeAnimation: Animation?
    static let cardWidth = 420.0
    /// Points of window above the screen's top edge.
    static let edgeOverlap: CGFloat = 1
    /// Bubble and mini chat placement around the island.
    @Published var composition = IslandComposition(island: IslandSize(width: 204, height: 32), notchHeight: 32)
    /// Measured by the mini chat; the window grows to fit it.
    @Published var agentCardHeight = 170.0
}
