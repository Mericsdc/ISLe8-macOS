import SwiftUI

/// The island outline: hangs from the top edge of the screen, flares out into it with two
/// concave "shoulders", and rounds off at the bottom. Both radii animate.
nonisolated struct IslandShape: Shape {
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set {
            shoulder = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = shoulder
        let radius = max(0, min(bottomRadius, rect.height - s, (rect.width - 2 * s) / 2))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + s, y: rect.minY + s),
            control: CGPoint(x: rect.minX + s, y: rect.minY)
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.minX + s, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - s, y: rect.maxY),
            radius: radius
        )
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX - s, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - s, y: rect.minY + s),
            radius: radius
        )
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - s, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

/// The island's outline at `size`, centred at the top of the rect it is drawn in. The island's
/// views stay put in a fixed frame under the notch while this grows and shrinks around them.
nonisolated struct CenteredIslandShape: Shape {
    var size: CGSize
    var shoulder: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(size.width, size.height), AnimatablePair(shoulder, bottomRadius)) }
        set {
            size = CGSize(width: newValue.first.first, height: newValue.first.second)
            shoulder = newValue.second.first
            bottomRadius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let island = CGRect(x: rect.midX - size.width / 2, y: rect.minY, width: size.width, height: size.height)
        return IslandShape(shoulder: shoulder, bottomRadius: bottomRadius).path(in: island)
    }
}
