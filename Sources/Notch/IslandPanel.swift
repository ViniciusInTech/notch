import AppKit
import Combine
import SwiftUI
import QuartzCore
import NotchCore

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class IslandHostingView: NSHostingView<IslandView> {
    var pointerChanged: ((Bool) -> Void)?
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
}

@MainActor final class IslandPanelController {
    private let model: AppModel
    private let panel: IslandPanel
    private let hosting: IslandHostingView
    private var subscriptions = Set<AnyCancellable>()
    private var collapseTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var targetFrame = NSRect.zero
    private let geometry = IslandGeometry()

    init(model: AppModel) {
        self.model = model
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hosting = IslandHostingView(rootView: IslandView(model: model, preferences: model.preferences, artwork: model.artwork, geometry: geometry))
        // The controller owns the window size. The fixed-width expanded content
        // must not impose a new intrinsic minimum before the frame starts animating.
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
        if inside {
            if model.preferences.expandOnHover { model.expanded = true }
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled, let self else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) { self.model.expanded = false }
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
        let size = layout.outerSize(active: model.active, expanded: model.expanded, activityCount: model.activityOrder.items.count)
        let frame = NSRect(x: centerX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        guard frame != targetFrame else { return }
        let initialPlacement = targetFrame == .zero
        let screenChanged = targetFrame.maxY != frame.maxY || targetFrame.midX != frame.midX
        targetFrame = frame
        revealTask?.cancel()
        if !model.expanded { geometry.expandedContentVisible = false }
        // Both rectangles share the same top-center: the entire surface grows out of
        // the physical notch instead of appearing at its final size in a single frame.
        // Animate the real window, so no invisible full-size overlay intercepts clicks.
        if initialPlacement || screenChanged || model.preferences.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            geometry.expandedContentVisible = model.expanded
            panel.setFrame(frame, display: true, animate: false)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = model.expanded ? 0.42 : 0.28
                context.timingFunction = model.expanded
                    ? CAMediaTimingFunction(controlPoints: 0.32, 0, 0.24, 1)
                    : CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
                panel.animator().setFrame(frame, display: true)
            }
            if model.expanded {
                revealTask = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                    guard !Task.isCancelled, let self, self.model.expanded else { return }
                    self.geometry.expandedContentVisible = true
                }
            }
        }
    }
}

@MainActor final class IslandGeometry: ObservableObject {
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var expandedWidth: CGFloat = 480
    @Published var expandedHeight: CGFloat = 214
    @Published var expandedContentVisible = false
}
