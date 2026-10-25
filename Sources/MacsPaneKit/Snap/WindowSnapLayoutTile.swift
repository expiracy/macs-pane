#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A layout in the notch, with its exact boxes as drag targets, in the picker's tile look
/// (`SnapTile`): the box under the pointer fills blue.
struct WindowSnapLayoutTile: View {
    let layout: WindowLayout
    @ObservedObject var model: WindowSnapViewModel
    let tileScale: CGFloat

    private var activeBox: Int? {
        model.highlightedLayoutBox?.layoutID == layout.id ? model.highlightedLayoutBox?.boxIndex : nil
    }

    var body: some View {
        let pad = WindowSnapMetrics.tilePadding * tileScale
        SnapTile(boxes: boxes, name: layout.name, active: activeBox != nil, scale: tileScale) { tile in
            AnyView(Color.clear.preference(key: SnapLayoutFramesKey.self,
                                           value: [layout.id: SnapTileFrame(tile: tile, inner: tile.insetBy(dx: pad, dy: pad))]))
        }
    }

    /// Back layers first, so a box in front hides the one it covers, as the window would.
    private var boxes: [SnapGlyphBox] {
        let layers = layout.layers
        return layout.boxes.indices
            .sorted { (layers[$0], -$0) > (layers[$1], -$1) }
            .map { index in
                let unit = layout.boxes[index].unitRect
                return SnapGlyphBox(rect: CGRect(x: unit.minX, y: 1 - unit.maxY, width: unit.width, height: unit.height),
                                    lit: activeBox == index)
            }
    }
}

struct SnapLayoutFramesKey: PreferenceKey {
    static var defaultValue: [String: SnapTileFrame] = [:]
    static func reduce(value: inout [String: SnapTileFrame], nextValue: () -> [String: SnapTileFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
#endif
