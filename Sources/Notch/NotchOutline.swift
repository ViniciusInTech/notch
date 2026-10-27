import SwiftUI

/// Concave shoulders join the menu bar; lower corners remain gently convex.
struct NotchOutline: Shape {
    var shoulder: CGFloat = 12
    var bottomRadius: CGFloat = 20

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(shoulder, bottomRadius) }
        set { shoulder = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.height / 2, rect.width / 4)
        let b = min(bottomRadius, (rect.width - 2 * s) / 2, rect.height / 2)
        let left = rect.minX + s, right = rect.maxX - s
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: right, y: rect.minY + s), control: CGPoint(x: right, y: rect.minY))
        p.addLine(to: CGPoint(x: right, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: right - b, y: rect.maxY), control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: left + b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - b), control: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: left, y: rect.minY + s))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: left, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
