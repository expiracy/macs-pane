#if canImport(AppKit)
import AppKit
import SwiftUI
import MacsPaneCore

/// A floating island beside the open notch: a black rounded panel with an icon title and a row of tiles
/// in the picker's tile look (`SnapTile`), each a mini-screen of app icons in their boxes with its name
/// under it (a preset's apps, while it is the aim). The left island holds the recommended presets (pairings of your recent
/// apps), the right one your own presets. A whole tile is one target. Display-only like the rest of the picker: each tile reports its rect so
/// the controller can hit-test the drag pointer.
struct WindowSnapIsland: View {
    enum Kind { case suggestions, presets }

    let kind: Kind
    @ObservedObject var model: WindowSnapViewModel
    let tileScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch kind {
                case .suggestions:
                    SnapHeading(symbol: "sparkles", tint: SnapTileStyle.recommended, title: "Recommended")
                case .presets:
                    SnapHeading(symbol: "star", title: "Your presets")
                }
            }
            .frame(height: WindowSnapPickerLayout.heading, alignment: .top)
            HStack(alignment: .top, spacing: WindowSnapMetrics.tileSpacing * tileScale) {
                switch kind {
                case .suggestions:
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        SnapTile(boxes: suggestion.boxes(in: model.visibleFrame), name: suggestion.label,
                                 active: model.highlightedSuggestion == index, scale: tileScale) { rect in
                            AnyView(Color.clear.preference(key: SnapSuggestionFramesKey.self, value: [index: rect]))
                        }
                        .modifier(StaggeredPop(index: index, delay: 0.2))
                    }
                case .presets:
                    ForEach(Array(model.presets.enumerated()), id: \.element.id) { index, preset in
                        // While aimed at, its name line says what it opens.
                        let aimed = model.highlightedPreset == index
                        SnapTile(boxes: preset.boxes, name: aimed ? preset.apps ?? preset.name : preset.name,
                                 active: aimed, scale: tileScale) { rect in
                            AnyView(Color.clear.preference(key: SnapPresetFramesKey.self, value: [index: rect]))
                        }
                        .modifier(StaggeredPop(index: index, delay: 0.25))
                    }
                }
            }
        }
        .padding(.horizontal, WindowSnapMetrics.islandPadding)
        .padding(.vertical, WindowSnapPickerLayout.islandEdge)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(NotchPalette.surfaceBase))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(SnapTileStyle.rim, lineWidth: 1))
        .shadow(color: NotchPalette.panelShadow, radius: NotchPalette.panelShadowRadius, y: NotchPalette.panelShadowY)
        .fixedSize()
    }
}

extension ResolvedDragSuggestion {
    /// The pairing's windows as boxes on the screen they tile (`visibleFrame`, AppKit bottom-left).
    func boxes(in visibleFrame: CGRect) -> [SnapGlyphBox] {
        pairing.placements.enumerated().map { index, placement in
            SnapGlyphBox(rect: Self.unitRect(placement.frame, in: visibleFrame),
                         icon: index < icons.count ? icons[index] : nil)
        }
    }

    /// A placement's frame (AppKit bottom-left, within `vf`) as a top-left-origin unit rect for drawing.
    static func unitRect(_ frame: CGRect, in vf: CGRect) -> CGRect {
        guard vf.width > 0, vf.height > 0 else { return .zero }
        return CGRect(x: (frame.minX - vf.minX) / vf.width,
                      y: (vf.maxY - frame.maxY) / vf.height,
                      width: frame.width / vf.width,
                      height: frame.height / vf.height)
    }
}

/// Collects preset-tile geometry (in the notch-panel coordinate space) for the controller's hit-test.
struct SnapPresetFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
#endif
