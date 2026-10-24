import CoreGraphics

/// How big MacsPane's drag-only notch is at each moment of a window drag: the resting notch widened
/// into a drag target, then the snap picker, one row of layout tiles under the camera, with the
/// recent-app pairing wing annexed on the left, shrunk evenly only when that row would leave the
/// screen. Tile measures come from the caller, the same constants the picker view draws with.
public struct WindowSnapPickerLayout: Equatable, Sendable {
    public struct Tiles: Equatable, Sendable {
        public var size: CGSize
        public var spacing: CGFloat
        /// The air either side of the seam between the pairing wing and the layout row.
        public var wingDivider: CGFloat

        public init(size: CGSize, spacing: CGFloat, wingDivider: CGFloat) {
            self.size = size
            self.spacing = spacing
            self.wingDivider = wingDivider
        }
    }

    /// Room beside the row inside the black shape, and the least distance from each screen edge.
    public static let rowPadding: CGFloat = 72
    public static let screenMargin: CGFloat = 48
    /// The narrowest open picker, so a short row still reads as the notch opening, not a tooltip.
    public static let minWidth: CGFloat = 520
    /// The drag target is about a third of the screen: easy to aim a window at.
    public static let dragTargetFraction: CGFloat = 1.0 / 3.0

    public let notchSize: CGSize
    public let screenWidth: CGFloat
    public let tiles: Tiles
    /// Layout tiles in the row (the picker is sized for a full bar, so pass at least the bar capacity).
    public let tileCount: Int
    public let suggestionCount: Int

    public init(notchSize: CGSize, screenWidth: CGFloat, tiles: Tiles, tileCount: Int, suggestionCount: Int) {
        self.notchSize = notchSize
        self.screenWidth = screenWidth
        self.tiles = tiles
        self.tileCount = max(tileCount, 1)
        self.suggestionCount = max(suggestionCount, 0)
    }

    /// The resting notch widened while a window is dragged, at the notch's own height.
    public var dragTargetSize: CGSize {
        CGSize(width: NotchGeometry.dragTargetWidth(screenWidth: screenWidth, notchWidth: notchSize.width,
                                                    fraction: Self.dragTargetFraction),
               height: notchSize.height)
    }

    /// Uniform shrink (≤ 1) for tiles and gaps. The wing is budgeted on both sides because it shifts
    /// the whole shape left of centre, and the layout row must stay centred on the camera.
    public var rowScale: CGFloat {
        let full = rowWidth(tileCount) + 2 * rowWidth(suggestionCount)
        let wingFixed = suggestionCount > 0 ? 2 * tiles.wingDivider : 0
        let available = maxWidth - Self.rowPadding - wingFixed
        guard full > available, available > 0 else { return 1 }
        return available / full
    }

    /// The wing's width (its tiles and the seam region) at `rowScale`; zero without pairings.
    public var wingWidth: CGFloat {
        guard suggestionCount > 0 else { return 0 }
        return rowWidth(suggestionCount) * rowScale + tiles.wingDivider
    }

    /// The open picker: the symmetric layout row plus the wing. Tall enough for the notch, one tile
    /// row with its names, the aim caption and the bottom curve, no dead band.
    public var pickerSize: CGSize {
        let scale = rowScale
        let row = min(max(rowWidth(tileCount) * scale + Self.rowPadding, Self.minWidth), maxWidth)
        let labels = 4 * scale + 16          // tile → name gap, one micro line and its slack
        let below = 8 + tiles.size.height * scale + labels + 10 + 22 + 12   // top pad · row · gap · caption · bottom
        return CGSize(width: row + wingWidth, height: notchSize.height + below)
    }

    private var maxWidth: CGFloat { max(Self.minWidth, screenWidth - Self.screenMargin) }

    private func rowWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tiles.size.width + CGFloat(count - 1) * tiles.spacing
    }
}
