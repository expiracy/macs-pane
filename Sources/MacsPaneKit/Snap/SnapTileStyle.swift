#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// The picker's one tile look, shared by the layout tiles in the notch and the tiles on the islands:
/// a near-black card with a faint rim holding a mini-screen whose boxes meet edge to edge with one line
/// between them. The tile that is the aim gets a blue rim and a soft glow, its boxes a deep blue and
/// the box under the pointer solid blue.
enum SnapTileStyle {
    static let card = Color(red: 0.078, green: 0.078, blue: 0.086)
    static let rim = Color.white.opacity(0.08)
    static let box = Color(red: 0.165, green: 0.165, blue: 0.176)
    static let line = Color.white.opacity(0.24)
    /// The other boxes of the tile that is the aim.
    static let aimedBox = Color(red: 0.043, green: 0.153, blue: 0.278)
    static let name = Color(red: 0.557, green: 0.557, blue: 0.576)
    static let title = Color.white.opacity(0.9)
    /// The recommended presets' sparkle.
    static let recommended = Color(red: 0.42, green: 0.71, blue: 1)
    static var accent: Color { NotchPalette.foreground(.accent) }
}

/// One box of a tile's mini-screen: where it sits (a top-left unit rect), the app it holds, if any,
/// and whether it is the exact box under the pointer.
struct SnapGlyphBox {
    var rect: CGRect
    var icon: NSImage?
    var lit = false
}

/// A tile: the card, its mini-screen of boxes, and its name on one line under it.
struct SnapTile: View {
    let boxes: [SnapGlyphBox]
    let name: String
    let active: Bool
    let scale: CGFloat
    /// Reports the card's rect in the picker's space, for the controller's hit-test.
    let report: (CGRect) -> AnyView

    var body: some View {
        VStack(spacing: 4 * scale) {
            card
            NotchHoverMarqueeText(text: name, role: .micro, weight: active ? .semibold : .medium,
                                  alignment: .center)
                .foregroundStyle(active ? Color.white : SnapTileStyle.name)
        }
        .frame(width: WindowSnapMetrics.tileSize.width * scale)
    }

    /// The card alone, the part the pointer aims at (owners report its frame).
    var card: some View {
        let shape = RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
        return SnapBoxesGlyph(boxes: boxes, aimed: active)
            .padding(WindowSnapMetrics.tilePadding * scale)
            .frame(width: WindowSnapMetrics.tileSize.width * scale, height: WindowSnapMetrics.tileSize.height * scale)
            .background(shape.fill(active ? SnapTileStyle.accent.opacity(0.12) : SnapTileStyle.card))
            .overlay(shape.strokeBorder(active ? SnapTileStyle.accent : SnapTileStyle.rim, lineWidth: active ? 1.5 : 1))
            .shadow(color: active ? SnapTileStyle.accent.opacity(0.35) : .clear, radius: 8)
            .background(GeometryReader { geo in report(geo.frame(in: .named(WindowSnapView.panelSpace))) })
            .animation(NotchMotion.fast, value: active)
    }
}

/// The mini-screen: each box at its exact rect with half a line inside its edge, so two neighbours
/// make one whole line and the outer edge meets the rounded frame; an app's icon centred in its box.
struct SnapBoxesGlyph: View {
    let boxes: [SnapGlyphBox]
    let aimed: Bool

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: 5, style: .continuous)
        let line = aimed ? SnapTileStyle.accent : SnapTileStyle.line
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(Array(boxes.enumerated()), id: \.offset) { _, box in
                    let size = CGSize(width: box.rect.width * geo.size.width, height: box.rect.height * geo.size.height)
                    Rectangle()
                        .fill(box.lit ? SnapTileStyle.accent : aimed ? SnapTileStyle.aimedBox : SnapTileStyle.box)
                        .overlay(Rectangle().strokeBorder(line, lineWidth: 0.5))
                        .overlay {
                            if let icon = box.icon {
                                Image(nsImage: icon).resizable().scaledToFit()
                                    .frame(width: min(size.width, size.height) * 0.7)
                            }
                        }
                        .frame(width: size.width, height: size.height)
                        .offset(x: box.rect.minX * geo.size.width, y: box.rect.minY * geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipShape(frame)
            .overlay(frame.strokeBorder(line, lineWidth: 1))
        }
    }
}

/// A tile arriving: it drops into place from slightly above, small and clear, with a springy settle,
/// each a moment after the one before (`index`), starting `delay` after the picker opens.
struct StaggeredPop: ViewModifier {
    let index: Int
    var delay: Double = 0.06
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.8, anchor: .top)
            .offset(y: shown ? 0 : -10)
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.66).delay(delay + Double(index) * 0.035)) {
                    shown = true
                }
            }
    }
}

/// The title of a group of tiles: its icon and what the group is ("✦ Recommended").
struct SnapHeading: View {
    /// The layouts' title: the same on the drag strip and in the open notch.
    static var layouts: SnapHeading {
        SnapHeading(symbol: "rectangle.split.2x1", tint: SnapTileStyle.accent, title: "Layouts")
    }

    /// Where a title starts inside a notch shape: just in from its top corner.
    static func inset(fromCorner radius: CGFloat) -> CGFloat { radius + 12 }

    let symbol: String
    var tint: Color = SnapTileStyle.title
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
            Text(title).notchText(.label, weight: .semibold).foregroundStyle(SnapTileStyle.title)
        }
        .lineLimit(1)
        .padding(.leading, 2)
    }
}
#endif
