import AppKit
import SwiftUI

/// Four bouncing bars. They are Core Animation layers, so the bouncing runs in the window
/// server and costs ISLe8 itself no CPU, unlike a SwiftUI timeline redrawing every frame.
struct AudioBars: NSViewRepresentable {
    var isPlaying: Bool
    var color: NSColor

    func makeNSView(context: Context) -> AudioBarsView {
        AudioBarsView()
    }

    func updateNSView(_ view: AudioBarsView, context: Context) {
        view.update(isPlaying: isPlaying, color: color)
    }
}

final class AudioBarsView: NSView {
    private static let durations: [CFTimeInterval] = [0.42, 0.55, 0.37, 0.49]
    private static let offsets: [CFTimeInterval] = [0, 0.18, 0.09, 0.27]
    private static let restingScale: CGFloat = 0.28

    private let bars: [CALayer] = (0..<4).map { _ in CALayer() }
    private var isAnimating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            bar.transform = CATransform3DMakeScale(1, Self.restingScale, 1)
            layer?.addSublayer(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layout() {
        super.layout()
        let width: CGFloat = 3
        let gap: CGFloat = 2.5
        let total = CGFloat(bars.count) * width + CGFloat(bars.count - 1) * gap
        let start = (bounds.width - total) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: width, height: bounds.height)
            bar.position = CGPoint(x: start + CGFloat(index) * (width + gap) + width / 2, y: 0)
        }
        CATransaction.commit()
    }

    func update(isPlaying: Bool, color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.forEach { $0.backgroundColor = color.cgColor }
        CATransaction.commit()

        guard isPlaying != isAnimating else { return }
        isAnimating = isPlaying
        let now = CACurrentMediaTime()
        for (index, bar) in bars.enumerated() {
            if isPlaying {
                let bounce = CABasicAnimation(keyPath: "transform.scale.y")
                bounce.fromValue = Self.restingScale
                bounce.toValue = 1.0
                bounce.duration = Self.durations[index]
                bounce.autoreverses = true
                bounce.repeatCount = .infinity
                bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bounce.beginTime = now + Self.offsets[index]
                bar.add(bounce, forKey: "bounce")
            } else {
                bar.removeAnimation(forKey: "bounce")
            }
        }
    }
}
