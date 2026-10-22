import CoreGraphics

/// One reading of the pointer while the notch waits to open: where it was and when (seconds on a
/// monotonic clock). Two readings give a speed, which is how the notch tells a rest from a pass.
public struct PointerSample: Equatable, Sendable {
    public let point: CGPoint
    public let time: Double

    public init(point: CGPoint, time: Double) {
        self.point = point
        self.time = time
    }

    /// Points per second travelled since `earlier`. Readings at the same instant count as a jump, so
    /// they read as travelling rather than dividing by zero.
    public func speed(since earlier: PointerSample) -> CGFloat {
        let distance = point.distance(to: earlier.point)
        let elapsed = time - earlier.time
        guard elapsed > 0 else { return distance > 0 ? .infinity : 0 }
        return distance / CGFloat(elapsed)
    }
}
