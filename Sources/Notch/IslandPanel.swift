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
    /// Screen-space test for the visible island; the window can be briefly larger while the shape animates.
    var islandContains: ((NSPoint) -> Bool)?
    private var tracking: NSTrackingArea?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
    }
    override func mouseEntered(with event: NSEvent) { pointerChanged?(true) }
    override func mouseExited(with event: NSEvent) { pointerChanged?(false) }
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
    private var expandTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var lastExpanded = false
    private var targetFrame = NSRect.zero
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
        hosting.pointerChanged = { [weak self] inside in self?.pointerChanged(inside) }
        hosting.islandContains = { [weak self] point in self?.targetFrame.contains(point) ?? true }
        model.objectWillChange.merge(with: model.preferences.objectWillChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.update() }.store(in: &subscriptions)
        update()
        panel.orderFrontRegardless()
    }

    func showExpanded() { model.expanded = true; update(); panel.orderFrontRegardless() }

    private func pointerChanged(_ inside: Bool) {
        collapseTask?.cancel()
        expandTask?.cancel()
        if inside {
            guard model.preferences.expandOnHover, !model.expanded else { return }
            // A short intent delay keeps the island closed when the pointer only grazes it.
            expandTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 80_000_000) } catch { return }
                guard let self, self.targetFrame.contains(NSEvent.mouseLocation) else { return }
                self.model.expanded = true
            }
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled, let self else { return }
                if !self.targetFrame.contains(NSEvent.mouseLocation) { self.model.expanded = false }
            }
        }
    }

    private func update() {
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
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        guard frame != targetFrame else { return }
        let initialPlacement = targetFrame == .zero
        let screenChanged = targetFrame.maxY != frame.maxY || targetFrame.midX != frame.midX
        let expansionChanged = lastExpanded != model.expanded
        lastExpanded = model.expanded
        targetFrame = frame
        revealTask?.cancel()
        settleTask?.cancel()
        if !model.expanded { geometry.expandedContentVisible = false }
        let shape = CGSize(width: size.width, height: size.height)

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
}
