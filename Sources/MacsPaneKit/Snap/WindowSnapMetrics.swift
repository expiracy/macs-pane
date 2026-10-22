#if canImport(AppKit)
import CoreGraphics

/// The snap picker's tile measures, shared by the picker view (`WindowSnapView`, `WindowSnapLayoutTile`)
/// and the notch that sizes itself to hold them (`MacsPaneSnapHost`), so the two can never disagree.
enum WindowSnapMetrics {
    /// A layout tile: big enough to aim a corner or a column at mid-drag, small enough to keep the row short.
    static let tileSize = CGSize(width: 112, height: 74)
    static let tileSpacing: CGFloat = 8
    /// The air either side of the seam between the pairing wing and the layout row.
    static let suggestionDivider: CGFloat = 24
    /// The most pairing tiles the picker shows (a pair and a trio); the panel is built wide enough for them.
    static let maxSuggestions = 2
    /// The drag target is about a third of the screen wide: an easy thing to aim a window at.
    static let dragWidthFraction: CGFloat = 1.0 / 3.0
}
#endif
