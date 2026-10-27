import AppKit
import QuartzCore
import SwiftUI
import NotchCore

/// Decorative, compositor-driven bars. No audio input, FFT, polling or per-frame SwiftUI work.
struct AlbumWaveform: NSViewRepresentable {
    let accent: ArtworkAccent
    let isPlaying: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> AlbumWaveformView { AlbumWaveformView() }

    func updateNSView(_ view: AlbumWaveformView, context: Context) {
        view.configure(accent: accent, animate: isPlaying && !reduceMotion)
    }

    static func dismantleNSView(_ view: AlbumWaveformView, coordinator: ()) { view.stop() }
}

final class AlbumWaveformView: NSView {
    private var bars: [CALayer] = []
    private var wantsAnimation = false
    private var animating = false
    private let restingScales: [CGFloat] = [0.35, 0.65, 0.9, 0.55, 0.3]

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); setup() }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        for index in 0..<5 {
            let bar = CALayer()
            bar.cornerRadius = 1.5
            bar.transform = CATransform3DMakeScale(1, restingScales[index], 1)
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: min(18, bounds.height))
            bar.position = CGPoint(x: bounds.midX + CGFloat(index - 2) * 5, y: bounds.midY)
        }
        CATransaction.commit()
    }

    func configure(accent: ArtworkAccent, animate: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.backgroundColor = NSColor(srgbRed: accent.red, green: accent.green, blue: accent.blue,
                                          alpha: 0.7 + Double(index % 3) * 0.15).cgColor
        }
        CATransaction.commit()
        wantsAnimation = animate
        updateAnimation()
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAnimation() }

    private func updateAnimation() {
        let shouldAnimate = wantsAnimation && window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate != animating else { return }
        if !shouldAnimate { settle(); return }
        animating = true
        for (index, bar) in bars.enumerated() {
            let wave = CAKeyframeAnimation(keyPath: "transform.scale.y")
            wave.values = [0.25, 0.8, 0.4, 1, 0.35, 0.25]
            wave.keyTimes = [0, 0.18, 0.4, 0.6, 0.82, 1]
            wave.calculationMode = .cubic
            wave.duration = 1.2 + Double(index) * 0.13
            wave.timeOffset = Double(index) * 0.23
            wave.repeatCount = .infinity
            wave.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 24)
            bar.add(wave, forKey: "album-wave")
        }
    }

    /// Pausing eases each bar from where it is to rest instead of freezing mid-wave.
    private func settle() {
        guard animating, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { stop(); return }
        animating = false
        for (index, bar) in bars.enumerated() {
            let current = bar.presentation()?.value(forKeyPath: "transform.scale.y") as? CGFloat ?? restingScales[index]
            bar.removeAnimation(forKey: "album-wave")
            let ease = CABasicAnimation(keyPath: "transform.scale.y")
            ease.fromValue = current
            ease.toValue = restingScales[index]
            ease.duration = 0.35
            ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            bar.transform = CATransform3DMakeScale(1, restingScales[index], 1)
            CATransaction.commit()
            bar.add(ease, forKey: "album-settle")
        }
    }

    func stop() {
        animating = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.removeAnimation(forKey: "album-wave")
            bar.transform = CATransform3DMakeScale(1, restingScales[index], 1)
        }
        CATransaction.commit()
    }
}
