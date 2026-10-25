#if canImport(AppKit)
import SwiftUI

/// The notch silhouette: small concave (inward-curving) top corners where it meets the screen
/// edge, and rounded bottom corners, so it reads as a seamless extension of the physical notch.
/// Corner radii are animatable so the shape morphs smoothly between compact and expanded.
/// Adapted from MrKai77/DynamicNotchKit (MIT).
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Concave top-left corner.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY))

        // Down the left edge to the bottom-left curve.
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY))

        // Across the bottom to the bottom-right curve.
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY))

        // Up the right edge to the concave top-right corner.
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY))

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

/// What the notch's content is clipped to: the silhouette itself, plus, while a floating card is
/// open, the band below it that the card hangs into.
///
/// The band is NOT part of the silhouette. Stretching one `NotchShape` over notch + band (as this
/// used to) carried the rounded bottom corners down to the band's far edge, which squared off the
/// black notch above them. And the band is deliberately left out of `animatableData`: it is fully
/// open the moment a card opens, so a card fading in is never wiped in behind a growing clip, the
/// part inside the notch showing first, the part below it arriving second.
struct NotchContentClip: Shape {
    var notch: NotchShape
    /// How far below the silhouette content may show. Zero unless a card is open.
    var overhang: CGFloat

    var animatableData: NotchShape.AnimatableData {
        get { notch.animatableData }
        set { notch.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = notch.path(in: rect)
        if overhang > 0 {
            path.addRect(CGRect(x: rect.minX, y: rect.maxY, width: rect.width, height: overhang))
        }
        return path
    }
}
#endif
