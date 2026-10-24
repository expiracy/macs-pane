#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The in-notch snap picker, shown only while `isSnapping`. A short, fixed, symmetric row of *family*
/// tiles (Maximize dead-centre, quarters and halves flanking it, the two thirds orientations
/// bookending), each a mini-screen the pointer aims *inside*: a corner of the quarters tile snaps a
/// quarter, a column of a thirds tile snaps a third. Folding zones into families keeps the row a
/// handful of uniform tiles instead of one skinny tile per zone (which ran wide once everything was on).
/// Recent-app pairing tiles live in a *wing* annexed on the left, split off by a full-height seam; the
/// shape shift in `MacsPaneNotchView` keeps the family section centred on the physical notch regardless.
///
/// The tile the pointer is over lights up in accent, and the exact cell under it fills, the same
/// highlight vocabulary as the selected tab pill and the shelf's drop target. Display-only: selection
/// comes from the window-drag stream (the panel is non-key, so no `Button`s); each tile reports its
/// on-screen rect + inner mini-screen box (in the notch panel's space) so the controller can hit-test
/// the live pointer against it (`WindowSnapViewModel.zone(at:)`). Colour comes from `NotchPalette`; the
/// tile geometry stays on `tileScale` (the fit-to-row shrink), only the caption joins the text scale.
struct WindowSnapView: View {
    @ObservedObject var model: WindowSnapViewModel
    @Environment(\.notchMetrics) private var m
    /// Uniform shrink factor (≤ 1) for the tiles + spacing, supplied by `MacsPaneSnapHost.rowScale`.
    /// 1 for the fixed family row on any normal display; below 1 only to keep the row on one line on a
    /// narrow external screen. Tiles report their *rendered* frames, so the pointer mapping follows.
    var tileScale: CGFloat = 1

    /// Coordinate space (declared on `MacsPaneNotchView`) the tiles report their frames in; the controller
    /// converts the drag pointer into the same space to find the hovered tile + cell.
    static let panelSpace = "notchPanelSpace"

    var body: some View {
        // The family that owns the live highlight, its tile reads "active". Computed once per render.
        // The pairing wing leads on the far left, split from the family section by a full-height seam;
        // the family section fills the remaining width, the SYMMETRIC part of the shape, which
        // `MacsPaneNotchView` keeps centred on the physical notch (the wing hangs off it to the left, so the
        // zones always read dead-centre whether or not pairings are present). The wing section's natural
        // width (tiles + seam region) is exactly `MacsPaneSnapHost.snapWingWidth`, the same value the
        // sizing adds to the panel and the root view shifts the shape by, so the three can never disagree.
        return HStack(alignment: .top, spacing: 0) {
            if !model.suggestions.isEmpty {
                HStack(alignment: .top, spacing: WindowSnapMetrics.tileSpacing * tileScale) {
                    ForEach(Array(model.suggestions.enumerated()), id: \.offset) { index, suggestion in
                        suggestionTile(index, suggestion)
                    }
                }
                suggestionSeam
            }
            VStack(spacing: m.md) {
                HStack(alignment: .top, spacing: WindowSnapMetrics.tileSpacing * tileScale) {
                    ForEach(model.pickerLayouts) { layout in
                        WindowSnapLayoutTile(layout: layout, model: model, tileScale: tileScale)
                    }
                }
                Text(model.highlightedLabel ?? "Drag onto a layout box to snap")
                    .notchText(.label)
                    .foregroundStyle(model.highlightedLabel == nil ? NotchPalette.fgSecondary : NotchPalette.fgPrimary)
                    .animation(NotchMotion.fast, value: model.highlightedLabel)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transition(.opacity)
        .onPreferenceChange(SnapLayoutFramesKey.self) { model.setLayoutFrames($0) }
    }

    /// A recent-app pairing tile, the same footprint and highlight vocabulary as a zone tile, but icon-only
    /// (no caption) and a single aim target: releasing anywhere on it tiles the whole pairing. Reports its
    /// rect so the controller can hit-test the live drag pointer (`WindowSnapViewModel.suggestionIndex(at:)`).
    private func suggestionTile(_ index: Int, _ suggestion: ResolvedDragSuggestion) -> some View {
        let active = model.highlightedSuggestion == index
        let corner = 10 * tileScale
        let padH = 12 * tileScale
        let padV = 9 * tileScale
        return SuggestionGlyph(suggestion: suggestion, visibleFrame: model.visibleFrame)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(width: WindowSnapMetrics.tileSize.width * tileScale,
                   height: WindowSnapMetrics.tileSize.height * tileScale)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(active ? NotchPalette.fillHover : NotchPalette.fillRest))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(active ? NotchPalette.foreground(.accent) : NotchPalette.strokeSubtle,
                              lineWidth: active ? 2 : 1))
            .background(GeometryReader { geo in
                let tile = geo.frame(in: .named(WindowSnapView.panelSpace))
                Color.clear.preference(key: SnapSuggestionFramesKey.self, value: [index: tile])
            })
            .animation(NotchMotion.fast, value: active)
    }

    /// The seam splitting the pairing wing from the family section: a full-height bar, deliberately
    /// heavier than a hairline and given clear air on both sides (the `snapSuggestionDivider` region
    /// the sizing budgets), so the wing unmistakably reads as a separate tray, not a neighbouring
    /// tile, at a glance mid-drag.
    private var suggestionSeam: some View {
        RoundedRectangle(cornerRadius: m.radiusSurface)
            .fill(NotchPalette.strokeContrast)
            .frame(width: m.thick)
            .frame(width: WindowSnapMetrics.suggestionDivider)
            .frame(maxHeight: .infinity)
    }

    private func tile(_ family: WindowSnapFamily, activeFamily: WindowSnapFamily?) -> some View {
        let active = family == activeFamily
        return VStack(spacing: 4 * tileScale) {
            glyphTile(family, active: active)
            Text(family.displayName)
                .notchText(.micro)
                .foregroundStyle(active ? NotchPalette.foreground(.accent) : NotchPalette.fgTertiary)
                .animation(NotchMotion.fast, value: active)
        }
    }

    /// The mini-screen tile itself: the family glyph on a rest/hover surface, reporting its rect +
    /// inner box. The inner box is the tile rect inset by the same padding the glyph sits behind, so
    /// "what you see is what you hit", the cell the pointer lands on is the one drawn under it.
    private func glyphTile(_ family: WindowSnapFamily, active: Bool) -> some View {
        let corner = 10 * tileScale
        let padH = 12 * tileScale
        let padV = 9 * tileScale
        return FamilyGlyph(family: family, highlighted: model.highlightedZone)
            .padding(.horizontal, padH)
            .padding(.vertical, padV)
            .frame(width: WindowSnapMetrics.tileSize.width * tileScale,
                   height: WindowSnapMetrics.tileSize.height * tileScale)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(active ? NotchPalette.fillHover : NotchPalette.fillRest))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(active ? NotchPalette.foreground(.accent) : NotchPalette.strokeSubtle,
                              lineWidth: active ? 2 : 1))
            .background(GeometryReader { geo in
                let tile = geo.frame(in: .named(WindowSnapView.panelSpace))
                Color.clear.preference(key: SnapFamilyFramesKey.self,
                                       value: [family: SnapTileFrame(tile: tile,
                                                                     inner: tile.insetBy(dx: padH, dy: padV))])
            })
            .animation(NotchMotion.fast, value: active)
    }
}

/// Draws a snap *family* as a mini-screen: a faint outline, the family's internal seams (so "quarters"
/// reads as a 2×2 and "thirds" as three columns), and, when the live highlight is one of this family's
/// zones, that cell filled in accent. All geometry comes from `WindowSnapFamily` (which derives it from
/// `WindowSnapZone.frame(in:)`), so the glyph and the snap can never disagree. Internal (not private) so
/// the Settings picker preview renders each tile with the exact same glyph as the notch.
struct FamilyGlyph: View {
    let family: WindowSnapFamily
    /// The live highlighted zone (may belong to another family, only a member of *this* one fills).
    let highlighted: WindowSnapZone?
    @Environment(\.notchMetrics) private var m

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: m(4), style: .continuous)   // mini-screen glyph corner, scales with the tile
                    .strokeBorder(NotchPalette.strokeContrast, lineWidth: m.thin)
                Path { p in
                    for x in family.verticalSeams {
                        p.move(to: CGPoint(x: x * w, y: 0)); p.addLine(to: CGPoint(x: x * w, y: h))
                    }
                    for y in family.horizontalSeams {
                        p.move(to: CGPoint(x: 0, y: y * h)); p.addLine(to: CGPoint(x: w, y: y * h))
                    }
                }
                .stroke(NotchPalette.strokeSubtle, lineWidth: m.thin)
                if let zone = highlighted, family.members.contains(zone) {
                    let c = family.cell(for: zone)   // top-left unit rect, no flip needed
                    RoundedRectangle(cornerRadius: m(2), style: .continuous)   // inner cell corner
                        .fill(NotchPalette.foreground(.accent))
                        .frame(width: max(0, c.width * w - 2), height: max(0, c.height * h - 2))
                        .offset(x: c.minX * w + 1, y: c.minY * h + 1)
                }
            }
        }
    }
}

/// Collects family-tile geometry (in the notch-panel coordinate space) so the controller can hit-test
/// the drag pointer against the tiles and the cell within each.
struct SnapFamilyFramesKey: PreferenceKey {
    static var defaultValue: [WindowSnapFamily: SnapTileFrame] = [:]
    static func reduce(value: inout [WindowSnapFamily: SnapTileFrame], nextValue: () -> [WindowSnapFamily: SnapTileFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Draws a recent-app pairing as a mini-screen: a faint outline and one cell per placement, at the
/// placement's real (normalised) frame within the visible frame, so the tile depicts the exact tiling it
/// applies, each cell filled with that window's app icon. Same glyph vocabulary as `FamilyGlyph`, but
/// icon cells instead of seams.
struct SuggestionGlyph: View {
    @Environment(\.notchMetrics) private var m
    let suggestion: ResolvedDragSuggestion
    /// The screen visible frame (AppKit bottom-left) the placements are expressed in, to normalise them.
    let visibleFrame: CGRect

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: m(4), style: .continuous)   // mini-screen glyph corner, scales with the tile
                    .strokeBorder(NotchPalette.strokeContrast, lineWidth: m.thin)
                ForEach(Array(suggestion.pairing.placements.enumerated()), id: \.offset) { i, placement in
                    let r = Self.unitRect(placement.frame, in: visibleFrame)
                    cell(icon: i < suggestion.icons.count ? suggestion.icons[i] : nil)
                        .frame(width: max(0, r.width * w - 2), height: max(0, r.height * h - 2))
                        .offset(x: r.minX * w + 1, y: r.minY * h + 1)
                }
            }
        }
    }

    private func cell(icon: NSImage?) -> some View {
        RoundedRectangle(cornerRadius: m(2), style: .continuous)   // inner cell corner
            .fill(NotchPalette.fillHover)
            .overlay {
                if let icon {
                    Image(nsImage: icon).resizable().scaledToFit().padding(m.hair)
                }
            }
    }

    /// A placement's frame (AppKit bottom-left, within `vf`) as a top-left-origin unit rect for drawing,
    /// the Y is flipped so the glyph reads the way the screen does.
    static func unitRect(_ frame: CGRect, in vf: CGRect) -> CGRect {
        guard vf.width > 0, vf.height > 0 else { return .zero }
        return CGRect(x: (frame.minX - vf.minX) / vf.width,
                      y: (vf.maxY - frame.maxY) / vf.height,
                      width: frame.width / vf.width,
                      height: frame.height / vf.height)
    }
}

/// Collects suggestion-tile geometry (in the notch-panel coordinate space) so the controller can hit-test
/// the drag pointer against the pairing tiles. Mirrors `SnapFamilyFramesKey`.
struct SnapSuggestionFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
#endif
