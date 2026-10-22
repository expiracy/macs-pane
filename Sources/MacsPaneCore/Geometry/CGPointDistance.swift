import CoreGraphics
import Foundation

public extension CGPoint {
    /// Euclidean distance to `other`. One tested home for the point-distance idiom the notch hover,
    /// the window-snap drag-activation threshold, and the AX landed-check all need.
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
