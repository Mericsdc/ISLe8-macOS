import AppKit
import SwiftUI

/// A special day's scene on the open island, behind its content, in the day's own colours
/// (see `Occasion.theme(over:)`): a glowing edge, pieces along the sides and the bottom row
/// beside the dock, and things drifting through. Every piece is a Core Animation layer whose
/// motion is set up once and then played by the system's render server, so ISLe8 does no
/// work per frame. Still with Reduce Motion on.
struct SeasonalDecor: NSViewRepresentable {
    let occasion: Occasion
    let shoulder: CGFloat
    let bottomRadius: CGFloat
    let headerHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> DecorView {
        DecorView()
    }

    func updateNSView(_ view: DecorView, context: Context) {
        view.configure(.init(occasion: occasion, still: reduceMotion, shoulder: shoulder, bottomRadius: bottomRadius, headerHeight: headerHeight))
    }
}

final class DecorView: NSView {
    struct Setup: Equatable {
        let occasion: Occasion
        let still: Bool
        let shoulder: CGFloat
        let bottomRadius: CGFloat
        let headerHeight: CGFloat
    }

    private var setup: Setup?
    private var builtSize: CGSize = .zero
    /// Emoji drawn once for the app's lifetime; the view itself is made anew on every open.
    private static var images: [String: CGImage] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { true }

    func configure(_ setup: Setup) {
        guard setup != self.setup else { return }
        self.setup = setup
        rebuild()
    }

    override func layout() {
        super.layout()
        // The island changes height between tabs; the scene is laid out again for it.
        if abs(bounds.width - builtSize.width) > 1 || abs(bounds.height - builtSize.height) > 1 {
            rebuild()
        }
    }

    // MARK: Scenes

    private var width: CGFloat { bounds.width }
    private var height: CGFloat { bounds.height }
    private var top: CGFloat { setup?.headerHeight ?? 36 }

    private func rebuild() {
        guard let layer, let setup else { return }
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        builtSize = bounds.size
        guard width > 200, height > 60 else { return }
        let glow = NSColor(hex: setup.occasion.palette.3)
        switch setup.occasion {
        case .valentines: valentines(glow)
        case .stPatricks: stPatricks(glow)
        case .easter: easter(glow)
        case .halloween: halloween(glow)
        case .lunarNewYear: lunarNewYear(glow)
        case .winter: winter(glow)
        case .newYear: newYear(glow)
        }
        border(glow)
    }

    private func valentines(_ glow: NSColor) {
        spot(at: CGPoint(x: 0, y: height * 0.6), radius: 120, color: glow, opacity: 0.4)
        spot(at: CGPoint(x: width, y: height * 0.6), radius: 120, color: glow, opacity: 0.4)
        for side in [false, true] {
            let x = { (inset: CGFloat) in side ? self.width - inset : inset }
            beat(piece("❤️", 46, at: CGPoint(x: x(16), y: height * 0.6), glow: glow), offset: side ? 0.3 : 0)
            beat(piece("💖", 32, at: CGPoint(x: x(40), y: height - 28), glow: glow), offset: side ? 0.9 : 0.6)
            bob(piece("💗", 26, at: CGPoint(x: x(12), y: top + 26), glow: glow), by: 3, duration: 2.4, offset: side ? 1 : 0)
            bob(piece("💘", 22, at: CGPoint(x: x(8), y: height - 14), glow: glow), by: 2, duration: 2.1, offset: side ? 0.2 : 1.4)
            bob(piece("💕", 18, at: CGPoint(x: x(74), y: height - 14), opacity: 0.9), by: 2, duration: 2, offset: side ? 0.4 : 1.2)
        }
        rising("❤️", size: 12, count: 14, opacity: 0.55)
        twinkling("✨", size: 11, count: 8)
    }

    private func stPatricks(_ glow: NSColor) {
        spot(at: CGPoint(x: 0, y: height), radius: 140, color: glow, opacity: 0.35)
        spot(at: CGPoint(x: width, y: height), radius: 140, color: glow, opacity: 0.35)
        let gold = NSColor(hex: "#FACC15")
        for side in [false, true] {
            let x = { (inset: CGFloat) in side ? self.width - inset : inset }
            sway(piece(side ? "🍀" : "☘️", 46, at: CGPoint(x: x(20), y: height * 0.5), glow: glow), degrees: 8, duration: 3, offset: side ? 1 : 0)
            sway(piece("☘️", 24, at: CGPoint(x: x(10), y: top + 20), glow: glow), degrees: 10, duration: 2.6, offset: side ? 0.3 : 1.1)
            bob(piece("🎩", 36, at: CGPoint(x: x(38), y: height - 24), glow: glow, silhouette: NSColor(hex: "#16A34A")), by: 1.5, duration: 2.2, offset: side ? 0.7 : 0)
            for (index, coin) in [(72, 16), (88, 13), (100, 15)].enumerated() {
                pulse(piece("🪙", CGFloat(coin.1), at: CGPoint(x: x(CGFloat(coin.0)), y: height - 11), glow: gold), duration: 1.4 + Double(index) * 0.3, offset: side ? 0.5 : Double(index) * 0.4)
            }
        }
        falling("☘️", size: 13, count: 12, speed: 9, opacity: 0.5, spin: true)
        twinkling("✨", size: 10, count: 8)
    }

    private func easter(_ glow: NSColor) {
        meadow(color: NSColor(hex: "#84CC16"))
        hop(piece("🐰", 54, at: CGPoint(x: 30, y: height - 36), glow: NSColor(white: 1, alpha: 0.5)))
        bob(piece("🥚", 34, at: CGPoint(x: width - 30, y: height - 24), glow: glow), by: 1.5, duration: 2.4)
        bob(piece("🐣", 26, at: CGPoint(x: width - 62, y: height - 18), glow: glow), by: 2, duration: 1.8, offset: 0.6)
        sway(piece("🌷", 26, at: CGPoint(x: width - 12, y: height - 52)), degrees: 6, duration: 2.8)
        sway(piece("🌼", 20, at: CGPoint(x: 62, y: height - 14)), degrees: 6, duration: 2.4, offset: 0.5)
        let row = ["🌷", "🥚", "🌼", "🥚", "🌸", "🌼", "🥚"]
        for (index, item) in row.enumerated() {
            for side in [false, true] {
                let step = CGFloat(index) * 28 + 86
                let x = side ? width - step - 12 : step
                guard side ? x > width / 2 + 200 : x < width / 2 - 200 else { continue }
                sway(piece(item, 17, at: CGPoint(x: x, y: height - 12)), degrees: 5, duration: 2 + Double(index % 3) * 0.4, offset: Double(index) * 0.3)
            }
        }
        drifting("🦋", size: 15, count: 3, band: 0.3...0.6, opacity: 0.85)
        twinkling("✨", size: 10, count: 6)
    }

    private func halloween(_ glow: NSColor) {
        let moon = CGPoint(x: width - 150, y: top + 22)
        spot(at: moon, radius: 95, color: glow, opacity: 0.5)
        pulse(piece("🌕", 40, at: moon, glow: glow), duration: 3, low: 0.8)
        piece("🏰", 64, at: CGPoint(x: width - 88, y: top + 34), silhouette: NSColor(white: 0.02, alpha: 0.88))
        piece("🕸️", 34, at: CGPoint(x: 18, y: top + 14), opacity: 0.35)
        for side in [false, true] {
            let x = { (inset: CGFloat) in side ? self.width - inset : inset }
            flicker(piece("🎃", 46, at: CGPoint(x: x(28), y: height - 28), glow: glow), offset: side ? 0.4 : 0)
            flicker(piece("🎃", 24, at: CGPoint(x: x(70), y: height - 14), glow: glow), offset: side ? 0.9 : 0.2)
        }
        drifting("🦇", size: 16, count: 5, band: 0.15...0.5, opacity: 0.75)
        embers(color: glow, count: 18)
    }

    private func lunarNewYear(_ glow: NSColor) {
        let red = NSColor(hex: "#EF4444")
        spot(at: CGPoint(x: 0, y: top + 30), radius: 120, color: red, opacity: 0.4)
        spot(at: CGPoint(x: width, y: top + 30), radius: 120, color: red, opacity: 0.4)
        for side in [false, true] {
            let x = { (inset: CGFloat) in side ? self.width - inset : inset }
            hang(piece("🏮", 36, at: CGPoint(x: x(20), y: top + 30), glow: glow), offset: side ? 0.5 : 0)
            hang(piece("🏮", 26, at: CGPoint(x: x(50), y: top + 56), glow: glow), offset: side ? 1.2 : 0.8)
            bob(piece("🐉", 58, at: CGPoint(x: x(46), y: height - 30), glow: glow, mirrored: !side), by: 3, duration: 3.2, offset: side ? 0.8 : 0)
            pulse(piece("🧧", 18, at: CGPoint(x: x(100), y: height - 13), glow: glow), duration: 2.2, offset: side ? 0.3 : 1)
            sway(piece("🧨", 18, at: CGPoint(x: x(124), y: height - 13), glow: glow), degrees: 6, duration: 1.8, offset: side ? 0.6 : 0)
        }
        embers(color: NSColor(hex: "#FBBF24"), count: 14)
        twinkling("✨", size: 11, count: 8)
    }

    private func newYear(_ glow: NSColor) {
        let gold = NSColor(hex: "#FBBF24")
        spot(at: CGPoint(x: width / 2, y: height + 30), radius: width * 0.5, color: glow, opacity: 0.25)
        spot(at: CGPoint(x: width - 120, y: top + 10), radius: 90, color: gold, opacity: 0.25)
        year(gold)
        for index in 0..<6 {
            let x = width * (0.08 + 0.17 * CGFloat(index))
            burst(at: CGPoint(x: x, y: top + 14 + Self.random(index, 4) * height * 0.3), offset: Double(index) * 0.7, size: 1.4)
        }
        confetti(count: 34)
        rising("🎈", size: 15, count: 5, opacity: 0.8)
        for side in [false, true] {
            let x = { (inset: CGFloat) in side ? self.width - inset : inset }
            sway(piece(side ? "🥂" : "🍾", 42, at: CGPoint(x: x(26), y: height - 28), glow: gold), degrees: 6, duration: 2.2, offset: side ? 0.5 : 0)
            pulse(piece("🎉", 26, at: CGPoint(x: x(64), y: height - 16), glow: gold), duration: 1.4, offset: side ? 0.7 : 0)
            twinklingAt(piece("⭐️", 18, at: CGPoint(x: x(14), y: top + 24), glow: gold), offset: side ? 0.4 : 1)
        }
        twinkling("✨", size: 12, count: 12)
    }

    /// The new year in glowing gold type, top right, breathing.
    private func year(_ gold: NSColor) {
        let now = Calendar.current.dateComponents([.year, .month], from: .now)
        let number = (now.year ?? 2027) + (now.month == 12 ? 1 : 0)
        let text = CATextLayer()
        text.string = "\(number)"
        text.font = NSFont.systemFont(ofSize: 34, weight: .black)
        text.fontSize = 34
        text.foregroundColor = gold.withAlphaComponent(0.85).cgColor
        text.alignmentMode = .center
        text.contentsScale = window?.backingScaleFactor ?? 2
        text.bounds = CGRect(x: 0, y: 0, width: 110, height: 42)
        text.position = CGPoint(x: width - 120, y: top + 14)
        text.shadowColor = gold.cgColor
        text.shadowRadius = 10
        text.shadowOpacity = 1
        text.shadowOffset = .zero
        text.opacity = 0.55
        add(text)
        animate(text, "opacity", from: 0.35, to: 0.7, duration: 2.4, reverses: true)
    }

    /// Paper squares in party colours, tumbling down.
    private func confetti(count: Int) {
        let colors = ["#F472B6", "#FBBF24", "#34D399", "#60A5FA", "#C084FC", "#F87171"].map { NSColor(hex: $0) }
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let paper = CALayer()
            paper.bounds = CGRect(x: 0, y: 0, width: 3 + seed * 2, height: 5 + seed * 3)
            paper.backgroundColor = colors[index % colors.count].withAlphaComponent(0.85).cgColor
            let x = Self.random(index, 3) * width
            paper.position = CGPoint(x: x, y: -8)
            add(paper)
            let duration = Double(height + 16) / (12 + seed * 14)
            animate(paper, "position.y", from: -8, to: height + 8, duration: duration, offset: Self.random(index, 2) * duration)
            animate(paper, "position.x", from: x - 10, to: x + 10, duration: 1.6 + seed * 2, reverses: true, offset: seed * 3)
            animate(paper, "transform.rotation.z", from: 0, to: Double.pi * 2, duration: 1.2 + seed * 1.6)
            animate(paper, "transform.rotation.x", from: 0, to: Double.pi * 2, duration: 0.9 + seed)
        }
    }

    private func twinklingAt(_ item: CALayer, offset: Double) {
        animate(item, "opacity", from: 0.3, to: 1, duration: 1.3, reverses: true, offset: offset)
        animate(item, "transform.scale", from: 0.8, to: 1.1, duration: 1.3, reverses: true, offset: offset)
    }

    private func winter(_ glow: NSColor) {
        spot(at: CGPoint(x: width / 2, y: height + 20), radius: width * 0.45, color: glow, opacity: 0.22)
        garland()
        let warm = NSColor(hex: "#FDE68A")
        piece("🌲", 58, at: CGPoint(x: 22, y: height - 36))
        sway(piece("🎄", 40, at: CGPoint(x: 58, y: height - 24), glow: warm), degrees: 2, duration: 3.4)
        sway(piece("🎄", 52, at: CGPoint(x: width - 28, y: height - 32), glow: warm), degrees: 2, duration: 3.1, offset: 0.6)
        piece("🌲", 34, at: CGPoint(x: width - 64, y: height - 20))
        bob(piece("⛄️", 28, at: CGPoint(x: width - 94, y: height - 17)), by: 1, duration: 2.6)
        let village = ["🏠", "🏡", "⛪️", "🏘️", "🏠", "🏡"]
        for (index, house) in village.enumerated() {
            for side in [false, true] {
                let step = CGFloat(index) * 30 + (side ? 120 : 92)
                let x = side ? width - step : step
                guard side ? x > width / 2 + 200 : x < width / 2 - 200 else { continue }
                pulse(piece(house, 19, at: CGPoint(x: x, y: height - 13), glow: warm), duration: 2.6 + Double(index) * 0.3, low: 0.8, offset: Double(index))
            }
        }
        snow(count: 46)
        falling("❄️", size: 13, count: 6, speed: 6, opacity: 0.75, spin: true)
    }

    /// A firework: a ring of coloured sparks bursting outwards and fading, again and again.
    private func burst(at center: CGPoint, offset: Double, size: CGFloat = 1) {
        let colors = ["#F87171", "#FBBF24", "#34D399", "#60A5FA", "#F472B6", "#FFFFFF"].map { NSColor(hex: $0) }
        let shell = CALayer()
        shell.bounds = CGRect(x: -40, y: -40, width: 80, height: 80)
        shell.position = center
        shell.opacity = 0
        for index in 0..<12 {
            let angle = Double(index) / 12 * .pi * 2
            let spark = CALayer()
            spark.bounds = CGRect(x: 0, y: 0, width: 3, height: 3)
            spark.cornerRadius = 1.5
            let color = colors[index % colors.count]
            spark.backgroundColor = color.cgColor
            spark.shadowColor = color.cgColor
            spark.shadowRadius = 3
            spark.shadowOpacity = 1
            spark.shadowOffset = .zero
            spark.position = CGPoint(x: cos(angle) * 30 * size, y: sin(angle) * 30 * size)
            shell.addSublayer(spark)
        }
        add(shell)
        let duration = 2.4 + Self.random(Int(center.x), 5)
        keyframes(shell, "transform.scale", values: [0.1, 1, 1.15, 1.15], times: [0, 0.35, 0.55, 1], duration: duration, offset: offset)
        keyframes(shell, "opacity", values: [0, 1, 0, 0], times: [0, 0.1, 0.55, 1], duration: duration, offset: offset)
    }

    // MARK: Light

    /// A thin line along the island's edge in the day's colour, glowing inwards and breathing.
    private func border(_ color: NSColor) {
        guard let setup else { return }
        let outline = CAShapeLayer()
        outline.frame = bounds
        outline.path = IslandShape(shoulder: setup.shoulder, bottomRadius: setup.bottomRadius).path(in: bounds).cgPath
        outline.fillColor = nil
        outline.strokeColor = color.withAlphaComponent(0.9).cgColor
        outline.lineWidth = 3
        outline.shadowColor = color.cgColor
        outline.shadowRadius = 9
        outline.shadowOpacity = 1
        outline.shadowOffset = .zero
        add(outline)
        animate(outline, "opacity", from: 0.55, to: 1, duration: 2.2, reverses: true)
    }

    /// A soft round glow, as from a lamp or the moon.
    private func spot(at point: CGPoint, radius: CGFloat, color: NSColor, opacity: Float) {
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [color.withAlphaComponent(1).cgColor, color.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
        glow.position = point
        glow.opacity = opacity
        add(glow)
    }

    /// Spring grass glowing along the bottom.
    private func meadow(color: NSColor) {
        let grass = CAGradientLayer()
        grass.frame = CGRect(x: 0, y: height - 46, width: width, height: 46)
        grass.colors = [color.withAlphaComponent(0).cgColor, color.withAlphaComponent(0.28).cgColor]
        add(grass)
        spot(at: CGPoint(x: width / 2, y: height + 10), radius: width * 0.4, color: NSColor(hex: "#FDE68A"), opacity: 0.2)
    }

    /// Fairy lights hanging across the top, twinkling one after another.
    private func garland() {
        let colors = ["#F87171", "#FBBF24", "#4ADE80", "#60A5FA"].map { NSColor(hex: $0) }
        let count = Int(width / 22)
        for index in 0...count {
            let x = CGFloat(index) * width / CGFloat(count)
            let y = 5 + abs(sin(Double(index) * .pi / 6)) * 5
            let bulb = CALayer()
            bulb.bounds = CGRect(x: 0, y: 0, width: 4, height: 4)
            bulb.cornerRadius = 2
            let color = colors[index % colors.count]
            bulb.backgroundColor = color.cgColor
            bulb.shadowColor = color.cgColor
            bulb.shadowRadius = 4
            bulb.shadowOpacity = 1
            bulb.shadowOffset = .zero
            bulb.position = CGPoint(x: x, y: y)
            add(bulb)
            animate(bulb, "opacity", from: 0.35, to: 1, duration: 0.9 + Double(index % 4) * 0.25, reverses: true, offset: Double(index) * 0.2)
        }
    }

    // MARK: Particles

    /// Small things falling from the top, swaying side to side, and turning if asked.
    private func falling(_ text: String, size: CGFloat, count: Int, speed: Double, opacity: Float, spin: Bool = false) {
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let item = piece(text, size, at: .zero, opacity: opacity)
            let x = Self.random(index, 3) * width
            item.position = CGPoint(x: x, y: -12)
            let duration = Double(height + 24) / (speed + seed * speed)
            animate(item, "position.y", from: -12, to: height + 12, duration: duration, offset: Self.random(index, 2) * duration)
            animate(item, "position.x", from: x - 8, to: x + 8, duration: 3 + seed * 3, reverses: true, offset: seed * 4)
            if spin {
                animate(item, "transform.rotation.z", from: 0, to: Double.pi * 2, duration: 6 + seed * 4)
            }
        }
    }

    /// Snowflakes: soft white dots of a few sizes.
    private func snow(count: Int) {
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let flake = CALayer()
            let radius = 0.9 + seed * 1.5
            flake.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            flake.cornerRadius = radius
            flake.backgroundColor = NSColor.white.withAlphaComponent(0.35 + seed * 0.4).cgColor
            let x = Self.random(index, 3) * width
            flake.position = CGPoint(x: x, y: -5)
            add(flake)
            let duration = Double(height + 10) / (7 + seed * 9)
            animate(flake, "position.y", from: -5, to: height + 5, duration: duration, offset: Self.random(index, 2) * duration)
            animate(flake, "position.x", from: x - 6, to: x + 6, duration: 3 + seed * 3, reverses: true, offset: seed * 4)
        }
    }

    /// Rising from the bottom and fading out on the way up.
    private func rising(_ text: String, size: CGFloat, count: Int, opacity: Float) {
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let item = piece(text, size, at: .zero, opacity: 0)
            let x = Self.random(index, 3) * width
            item.position = CGPoint(x: x, y: height + 10)
            let duration = Double(height + 20) / (10 + seed * 8)
            let offset = Self.random(index, 2) * duration
            animate(item, "position.y", from: height + 10, to: -10, duration: duration, offset: offset)
            animate(item, "opacity", from: opacity, to: 0, duration: duration, offset: offset)
            animate(item, "position.x", from: x - 7, to: x + 7, duration: 2.5 + seed * 2, reverses: true, offset: seed * 3)
        }
    }

    /// Glowing sparks rising from the bottom, fading as they go.
    private func embers(color: NSColor, count: Int) {
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let spark = CALayer()
            let radius = 1 + seed * 1.2
            spark.bounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)
            spark.cornerRadius = radius
            spark.backgroundColor = color.cgColor
            spark.shadowColor = color.cgColor
            spark.shadowRadius = 3
            spark.shadowOpacity = 1
            spark.shadowOffset = .zero
            spark.opacity = 0
            let x = Self.random(index, 3) * width
            spark.position = CGPoint(x: x, y: height)
            add(spark)
            let duration = Double(height) / (12 + seed * 14)
            let offset = Self.random(index, 2) * duration
            animate(spark, "position.y", from: height, to: height * 0.2, duration: duration, offset: offset)
            animate(spark, "opacity", from: 0.9, to: 0, duration: duration, offset: offset)
            animate(spark, "position.x", from: x - 5, to: x + 5, duration: 1.6 + seed, reverses: true, offset: seed * 2)
        }
    }

    /// Crossing slowly from side to side within a band of the height, bobbing as they fly.
    private func drifting(_ text: String, size: CGFloat, count: Int, band: ClosedRange<CGFloat>, opacity: Float) {
        let span = Double(width + 40)
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let item = piece(text, size, at: .zero, opacity: opacity, mirrored: index.isMultiple(of: 2))
            let y = height * (band.lowerBound + Self.random(index, 3) * (band.upperBound - band.lowerBound))
            item.position = CGPoint(x: -20, y: y)
            let duration = span / (14 + seed * 10)
            let leftward = !index.isMultiple(of: 2)
            animate(item, "position.x", from: leftward ? width + 20 : -20, to: leftward ? -20 : width + 20, duration: duration, offset: Self.random(index, 2) * duration)
            animate(item, "position.y", from: y - 5, to: y + 5, duration: 0.7 + seed * 0.6, reverses: true, offset: seed * 2)
        }
    }

    /// Fading in and out in place.
    private func twinkling(_ text: String, size: CGFloat, count: Int, band: ClosedRange<CGFloat> = 0...1) {
        for index in 0..<count {
            let seed = Self.random(index, 1)
            let y = height * (band.lowerBound + Self.random(index, 3) * (band.upperBound - band.lowerBound))
            let item = piece(text, size, at: CGPoint(x: Self.random(index, 2) * width, y: y), opacity: 0)
            animate(item, "opacity", from: 0, to: 0.7, duration: 1.2 + seed * 1.5, reverses: true, offset: seed * 3)
            animate(item, "transform.scale", from: 0.6, to: 1.1, duration: 1.2 + seed * 1.5, reverses: true, offset: seed * 3)
        }
    }

    // MARK: Motion

    private func bob(_ item: CALayer, by distance: CGFloat, duration: Double, offset: Double = 0) {
        animate(item, "position.y", from: item.position.y - distance, to: item.position.y + distance, duration: duration, reverses: true, offset: offset)
    }

    private func sway(_ item: CALayer, degrees: Double, duration: Double, offset: Double = 0) {
        let angle = degrees * .pi / 180
        animate(item, "transform.rotation.z", from: -angle, to: angle, duration: duration, reverses: true, offset: offset)
    }

    /// Hanging from the top and swinging, as lanterns do.
    private func hang(_ item: CALayer, offset: Double) {
        item.anchorPoint = CGPoint(x: 0.5, y: 0)
        item.position.y -= item.bounds.height / 2
        sway(item, degrees: 7, duration: 2.6, offset: offset)
    }

    /// A heartbeat: two quick pulses, then a rest.
    private func beat(_ item: CALayer, offset: Double = 0) {
        keyframes(item, "transform.scale", values: [1, 1.14, 1, 1.09, 1, 1], times: [0, 0.12, 0.24, 0.36, 0.5, 1], duration: 1.4, offset: offset)
    }

    /// A small hop now and then.
    private func hop(_ item: CALayer) {
        let y = item.position.y
        keyframes(item, "position.y", values: [y, y - 7, y, y - 4, y, y], times: [0, 0.12, 0.24, 0.33, 0.42, 1], duration: 2.4)
    }

    /// A candle inside: the glow and the brightness waver.
    private func flicker(_ item: CALayer, offset: Double = 0) {
        keyframes(item, "shadowOpacity", values: [0.55, 1, 0.7, 0.95, 0.6, 0.9, 0.55], times: [0, 0.15, 0.3, 0.5, 0.65, 0.85, 1], duration: 1.3, offset: offset)
        keyframes(item, "opacity", values: [0.88, 1, 0.92, 1, 0.9, 1, 0.88], times: [0, 0.15, 0.3, 0.5, 0.65, 0.85, 1], duration: 1.3, offset: offset)
    }

    private func pulse(_ item: CALayer, duration: Double, low: Float = 0.7, offset: Double = 0) {
        animate(item, "opacity", from: low, to: 1, duration: duration, reverses: true, offset: offset)
    }

    // MARK: Layers

    private func add(_ item: CALayer) {
        layer?.addSublayer(item)
    }

    /// Played by the render server for as long as the layer exists. With Reduce Motion the
    /// piece just stays where it was put.
    private func animate(_ item: CALayer, _ keyPath: String, from: Any, to: Any, duration: Double, reverses: Bool = false, offset: Double = 0) {
        guard setup?.still != true, duration > 0 else { return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.autoreverses = reverses
        animation.repeatCount = .infinity
        animation.timeOffset = offset
        animation.timingFunction = CAMediaTimingFunction(name: reverses ? .easeInEaseOut : .linear)
        item.add(animation, forKey: keyPath)
    }

    private func keyframes(_ item: CALayer, _ keyPath: String, values: [Any], times: [NSNumber], duration: Double, offset: Double = 0) {
        guard setup?.still != true else { return }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times
        animation.duration = duration
        animation.repeatCount = .infinity
        animation.timeOffset = offset
        animation.calculationMode = .linear
        item.add(animation, forKey: keyPath)
    }

    /// An emoji as an image layer, each emoji and size drawn once. `glow` haloes it,
    /// `silhouette` turns it into a flat shape of that colour (a castle against the moon),
    /// `tint` washes it in a colour (a green hat).
    @discardableResult
    private func piece(
        _ text: String, _ size: CGFloat, at point: CGPoint, opacity: Float = 1,
        glow: NSColor? = nil, silhouette: NSColor? = nil, tint: NSColor? = nil, mirrored: Bool = false
    ) -> CALayer {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let (image, extent) = render(text, size: size, scale: scale)
        let item = CALayer()
        item.bounds = CGRect(origin: .zero, size: extent)
        item.position = point
        item.opacity = opacity
        if let silhouette {
            item.backgroundColor = silhouette.cgColor
            let mask = CALayer()
            mask.frame = item.bounds
            mask.contents = image
            mask.contentsScale = scale
            item.mask = mask
        } else {
            item.contents = image
            item.contentsScale = scale
            if let tint {
                let wash = CALayer()
                wash.frame = item.bounds
                wash.backgroundColor = tint.withAlphaComponent(0.55).cgColor
                wash.compositingFilter = "multiplyBlendMode"
                let mask = CALayer()
                mask.frame = item.bounds
                mask.contents = image
                mask.contentsScale = scale
                wash.mask = mask
                item.addSublayer(wash)
            }
        }
        if let glow {
            item.shadowColor = glow.cgColor
            item.shadowRadius = size * 0.35
            item.shadowOpacity = 0.9
            item.shadowOffset = .zero
        }
        if mirrored {
            item.transform = CATransform3DMakeScale(-1, 1, 1)
        }
        add(item)
        return item
    }

    private func render(_ text: String, size: CGFloat, scale: CGFloat) -> (CGImage?, CGSize) {
        let string = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let extent = string.size()
        let key = "\(text)\(Int(size))@\(scale)"
        if Self.images[key] == nil {
            let pixelWidth = Int(ceil(extent.width * scale)), pixelHeight = Int(ceil(extent.height * scale))
            if pixelWidth > 0, pixelHeight > 0, let context = CGContext(
                data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) {
                context.scaleBy(x: scale, y: scale)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                string.draw(at: .zero)
                NSGraphicsContext.restoreGraphicsState()
                Self.images[key] = context.makeImage()
            }
        }
        return (Self.images[key], extent)
    }

    /// The same "random" number for the same piece every time, between 0 and 1.
    private static func random(_ index: Int, _ salt: Int) -> CGFloat {
        let value = sin(Double(index * 127 + salt * 311) * 12.9898) * 43758.5453
        return CGFloat(value - value.rounded(.down))
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let color = ThemeColor(hex).color
        self.init(color)
    }
}
