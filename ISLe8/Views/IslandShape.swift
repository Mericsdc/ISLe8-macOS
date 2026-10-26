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
