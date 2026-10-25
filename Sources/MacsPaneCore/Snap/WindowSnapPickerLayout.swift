import CoreGraphics

/// How big MacsPane's drag-only notch is at each moment of a window drag: the resting notch widened
/// into a drag target, then the snap picker. The picker is the notch holding one row of layout tiles,
/// exactly as wide as that row, with a floating island either side of it: the recent-app pairings on
/// the left and your presets on the right. Everything shrinks evenly only when it would leave the
/// screen. Tile measures come from the caller, the same constants the picker view draws with.
public struct WindowSnapPickerLayout: Equatable, Sendable {
    public struct Tiles: Equatable, Sendable {
        public var size: CGSize
        public var spacing: CGFloat
        /// The space between the notch and an island.
        public var islandGap: CGFloat
        /// An island's rim, each side of its tiles.
        public var islandPadding: CGFloat

        public init(size: CGSize, spacing: CGFloat, islandGap: CGFloat, islandPadding: CGFloat) {
            self.size = size
            self.spacing = spacing
            self.islandGap = islandGap
            self.islandPadding = islandPadding
        }
    }

    /// The black beside the layout row, each side, inside the notch: the open notch's curved top
    /// corner (19pt) plus a margin, so the tiles never crowd its sides.
    public static let rowInset: CGFloat = 36
    /// How much wider than the camera the open notch always is, so a one-tile row still reads as the
    /// notch opening rather than a tab under it.
    public static let cameraClearance: CGFloat = 60
    /// The least distance from each screen edge.
    public static let screenMargin: CGFloat = 48
    /// The heading line over each group of tiles, and the air above and below an island's contents.
    public static let heading: CGFloat = 22
    public static let islandEdge: CGFloat = 10
    /// The black under the notch's tile names, above its bottom curve.
    static let bottom: CGFloat = 14

    public let notchSize: CGSize
    public let screenWidth: CGFloat
    public let tiles: Tiles
    /// Layout tiles in the row.
    public let tileCount: Int
    /// Pairing tiles on the left island, preset tiles on the right; zero leaves that island out.
    public let suggestionCount: Int
    public let presetCount: Int

    public init(notchSize: CGSize, screenWidth: CGFloat, tiles: Tiles, tileCount: Int,
                suggestionCount: Int, presetCount: Int = 0) {
        self.notchSize = notchSize
        self.screenWidth = screenWidth
        self.tiles = tiles
        self.tileCount = max(tileCount, 1)
        self.suggestionCount = max(suggestionCount, 0)
        self.presetCount = max(presetCount, 0)
    }

    /// The resting notch widened while a window is dragged, at the notch's own height and exactly as
    /// wide as the open notch, so holding there only grows it downward.
    public var dragTargetSize: CGSize {
        CGSize(width: pickerSize.width, height: notchSize.height)
    }

    /// Uniform shrink (≤ 1) for every tile and gap, so the notch and both islands fit the screen. The
    /// wider island is budgeted on both sides, because the notch stays centred under the camera.
    public var rowScale: CGFloat {
        let widestIsland = max(suggestionCount, presetCount)
        let scaled = rowWidth(tileCount) + 2 * rowWidth(widestIsland)
        let fixed = 2 * Self.rowInset + (widestIsland > 0 ? 2 * (tiles.islandGap + 2 * tiles.islandPadding) : 0)
        let available = maxWidth - fixed
        guard scaled > available, available > 0 else { return 1 }
        return available / scaled
    }

    /// The open notch: its layout row and the inset beside it, never narrower than the camera allows.
    /// Tall enough for the camera row (the notch's title, and the name of the box being aimed at, sit
    /// in it either side of the camera), one tile row with its names, and the bottom curve.
    public var pickerSize: CGSize {
        let scale = rowScale
        let width = max(rowWidth(tileCount) * scale + 2 * Self.rowInset, notchSize.width + Self.cameraClearance)
        let row = tiles.size.height * scale + labels(scale)
        return CGSize(width: width, height: rowTop + row + Self.bottom)
    }

    /// Where the notch's tiles start: just under the camera row.
    public var rowTop: CGFloat { notchSize.height + 10 }
    /// Where the islands start, up in the menu bar, as far from the top of the screen as they are from
    /// the notch; and where their headings start inside them.
    public var islandTop: CGFloat { tiles.islandGap }
    public var islandContentTop: CGFloat { islandTop + Self.islandEdge }

    public var leftIslandSize: CGSize { islandSize(suggestionCount) }
    public var rightIslandSize: CGSize { islandSize(presetCount) }

    /// Everything the open picker covers: the notch centred, with room for the wider island each side.
    /// The panel and the pointer's hot zone are this size.
    public var footprint: CGSize {
        let side = max(leftIslandSize.width, rightIslandSize.width)
        let width = pickerSize.width + (side > 0 ? 2 * (tiles.islandGap + side) : 0)
        let islands = side > 0 ? islandTop + max(leftIslandSize.height, rightIslandSize.height) : 0
        return CGSize(width: width, height: max(pickerSize.height, islands))
    }

    private func islandSize(_ count: Int) -> CGSize {
        guard count > 0 else { return .zero }
        let scale = rowScale
        let row = Self.heading + tiles.size.height * scale + labels(scale)
        return CGSize(width: rowWidth(count) * scale + 2 * tiles.islandPadding,
                      height: Self.islandEdge + row + Self.islandEdge)
    }

    /// The gap from a tile to its name, and one micro line with its slack.
    private func labels(_ scale: CGFloat) -> CGFloat { 4 * scale + 16 }

    private var maxWidth: CGFloat { max(notchSize.width + Self.cameraClearance, screenWidth - Self.screenMargin) }

    private func rowWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * tiles.size.width + CGFloat(count - 1) * tiles.spacing
    }
}
