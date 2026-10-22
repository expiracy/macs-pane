#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A layout from the Windows page, with its exact boxes as drag targets.
struct WindowSnapLayoutTile: View {
    let layout: WindowLayout
    @ObservedObject var model: WindowSnapViewModel
    let tileScale: CGFloat
    @Environment(\.notchMetrics) private var m

    private var activeBox: Int? {
        model.highlightedLayoutBox?.layoutID == layout.id ? model.highlightedLayoutBox?.boxIndex : nil
    }

    var body: some View {
        let padH = 12 * tileScale
        let padV = 9 * tileScale
        VStack(spacing: 4 * tileScale) {
            glyph
                .padding(.horizontal, padH)
                .padding(.vertical, padV)
                .frame(width: WindowSnapMetrics.tileSize.width * tileScale,
                       height: WindowSnapMetrics.tileSize.height * tileScale)
                .background(RoundedRectangle(cornerRadius: m.radiusSurface)
                    .fill(activeBox == nil ? NotchPalette.fillRest : NotchPalette.fillHover))
                .overlay(RoundedRectangle(cornerRadius: m.radiusSurface)
                    .strokeBorder(activeBox == nil ? NotchPalette.strokeSubtle : NotchPalette.strokeAccent,
                                  lineWidth: m.thin))
                .background(GeometryReader { geo in
                    let tile = geo.frame(in: .named(WindowSnapView.panelSpace))
                    Color.clear.preference(key: SnapLayoutFramesKey.self,
                                           value: [layout.id: SnapTileFrame(tile: tile,
                                                                           inner: tile.insetBy(dx: padH, dy: padV))])
                })
            NotchHoverMarqueeText(text: layout.name, role: .micro, alignment: .center)
                .foregroundStyle(activeBox == nil ? NotchPalette.fgTertiary : NotchPalette.foreground(.accent))
        }
        // The tile's own width, so a long name can't widen it and the row stays packed and centred.
        .frame(width: WindowSnapMetrics.tileSize.width * tileScale)
    }

    private var glyph: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: m.radiusSurface)
                    .strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.thin)
                ForEach(Array(layout.boxes.enumerated()), id: \.offset) { index, box in
                    let rect = box.unitRect
                    Rectangle()
                        .fill(activeBox == index ? NotchPalette.foreground(.accent) : NotchPalette.fillSelected)
                        .overlay(Rectangle().strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.thin))
                        .frame(width: max(0, rect.width * geo.size.width - m.hair),
                               height: max(0, rect.height * geo.size.height - m.hair))
                        .offset(x: rect.minX * geo.size.width + m.hair / 2,
                                y: -rect.minY * geo.size.height - m.hair / 2)
                }
            }
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
