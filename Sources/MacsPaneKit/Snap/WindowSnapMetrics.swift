#if canImport(AppKit)
import CoreGraphics

/// The snap picker's tile measures, shared by the picker view (`WindowSnapView`, `WindowSnapLayoutTile`)
/// and the notch that sizes itself to hold them (`MacsPaneSnapHost`), so the two can never disagree.
enum WindowSnapMetrics {
    /// A layout tile: big enough to aim a corner or a column at mid-drag, small enough to keep the row short.
    static let tileSize = CGSize(width: 88, height: 58)
    static let tileSpacing: CGFloat = 8
    /// The rim between a tile's edge and the drawing inside it, the part the pointer aims at.
    static let tilePadding: CGFloat = 6
    /// The space between the notch and each floating island, and an island's rim beside its tiles.
    static let islandGap: CGFloat = 14
    static let islandPadding: CGFloat = 14
    /// The most pairing tiles the picker shows (a pair and a trio); the panel is built wide enough for them.
    static let maxSuggestions = 2
    /// The most of your presets the right island shows, the first ones in the menu's order.
    static let maxPresets = 4
    /// The drag target is about a third of the screen wide: an easy thing to aim a window at.
    static let dragWidthFraction: CGFloat = 1.0 / 3.0
}
#endif
