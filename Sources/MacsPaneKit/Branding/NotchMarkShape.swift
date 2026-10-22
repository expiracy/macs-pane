#if canImport(AppKit)
import SwiftUI

/// The notch as it meets a top edge: small outward flares where it joins, rounded bottom corners.
/// All four measures are fractions of the bounding width.
struct NotchMarkShape: Shape {
    let width: CGFloat
    let height: CGFloat
    let flare: CGFloat
    let radius: CGFloat

    /// `rect.minY` is the edge the notch hangs from; the measures scale with `rect.width`.
    func path(in rect: CGRect) -> Path {
        let width = self.width * rect.width, height = self.height * rect.width
        let flare = self.flare * rect.width, radius = self.radius * rect.width
        var path = Path()
        let left = rect.midX - width / 2, right = rect.midX + width / 2, top = rect.minY
        path.move(to: CGPoint(x: left - flare, y: top))
        path.addQuadCurve(to: CGPoint(x: left, y: top + flare), control: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: top + height - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: top + height), control: CGPoint(x: left, y: top + height))
        path.addLine(to: CGPoint(x: right - radius, y: top + height))
        path.addQuadCurve(to: CGPoint(x: right, y: top + height - radius), control: CGPoint(x: right, y: top + height))
        path.addLine(to: CGPoint(x: right, y: top + flare))
        path.addQuadCurve(to: CGPoint(x: right + flare, y: top), control: CGPoint(x: right, y: top))
        path.closeSubpath()
        return path
    }
}
#endif
