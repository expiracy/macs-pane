#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The picker's geometry in stage points, after `snapExpandedSize` and `snapRowScale`: a family section
/// (at least 520 wide, reserving the bar's five slots) centred on the notch, the pair wing hanging off its
/// left behind a seam, and — on a screen this narrow — every tile shrunk by one factor so both fit.
/// Setup-only addition: a mirror wing of saved presets on the right (the shipped picker has none).
struct SetupSnapPicker {
    let stageWidth: CGFloat
    let layouts: Int
    let pairs: Int
    var presets = 0
    private static let baseTile = CGSize(width: 112, height: 74)
    private static let baseGap: CGFloat = 8
    private static let seam: CGFloat = 24
    /// The open shape's top corner radius plus `lg` — the same inset the camera strip's title takes, so
    /// the wing's first tile sits clear of the concave corner instead of under it.
    private static let edge: CGFloat = 31

    /// No padding of its own: the seam's air (half of `seam` each side) is the only gap, so the layouts
    /// sit as close to each seam as the wing's tiles do on its other side.
    private static let rowPadding: CGFloat = 0
    private var slots: Int { max(layouts, 1) }
    private var baseFamily: CGFloat {
        CGFloat(slots) * Self.baseTile.width + CGFloat(slots - 1) * Self.baseGap + Self.rowPadding
    }
    /// The family section at the tiles' scale — never the shipped 520 floor, which exists for the camera
    /// strip's title; here the strip spans the whole symmetric shape instead (`stripSpansShape`).
    var familyWidth: CGFloat { baseFamily * scale }
    /// One factor for every tile and the row's padding, as `snapRowScale` shrinks the row to fit a narrow
    /// screen: the family section is centred on the notch and the wider wing must still fit beside it.
    var scale: CGFloat {
        let widest = max(pairs, presets)
        let wingTiles = CGFloat(widest) * Self.baseTile.width + CGFloat(max(widest - 1, 0)) * Self.baseGap
        let fixed = widest > 0 ? Self.seam + Self.edge + 4 : 4
        return min(1, (stageWidth / 2 - fixed) / (baseFamily / 2 + wingTiles))
    }
    /// With a wing either side of equal width the lens stays centred under a full-width strip.
    var stripSpansShape: Bool { wingWidth == rightWingWidth }
    var tile: CGSize { CGSize(width: Self.baseTile.width * scale, height: Self.baseTile.height * scale) }
    var gap: CGFloat { Self.baseGap * scale }
    var inset: CGSize { CGSize(width: 12 * scale, height: 9 * scale) }
    private var pairRow: CGFloat { CGFloat(pairs) * tile.width + CGFloat(max(pairs - 1, 0)) * gap }
    var wingWidth: CGFloat { pairs == 0 ? 0 : Self.edge + pairRow + Self.seam }
    private var presetRow: CGFloat { CGFloat(presets) * tile.width + CGFloat(max(presets - 1, 0)) * gap }
    var rightWingWidth: CGFloat { presets == 0 ? 0 : Self.seam + presetRow + Self.edge }
    var frame: CGRect {
        let height = NotchGeometry.standardNotchSize.height + 8 + tile.height + 4 + 13 + 10 + 22 + 12
        return CGRect(x: stageWidth / 2 - familyWidth / 2 - wingWidth, y: 0,
                      width: familyWidth + wingWidth + rightWingWidth, height: height)
    }
    var seamX: CGFloat { frame.minX + Self.edge + pairRow + Self.seam / 2 }
    var presetSeamX: CGFloat { stageWidth / 2 + familyWidth / 2 + Self.seam / 2 }

    func presetTile(_ k: Int) -> CGRect {
        CGRect(x: stageWidth / 2 + familyWidth / 2 + Self.seam + CGFloat(k) * (tile.width + gap),
               y: NotchGeometry.standardNotchSize.height + 8, width: tile.width, height: tile.height)
    }

    func familyTile(_ i: Int) -> CGRect {
        let row = CGFloat(layouts) * tile.width + CGFloat(max(layouts - 1, 0)) * gap
        return CGRect(x: stageWidth / 2 - row / 2 + CGFloat(i) * (tile.width + gap),
                      y: NotchGeometry.standardNotchSize.height + 8, width: tile.width, height: tile.height)
    }

    func pairTile(_ j: Int) -> CGRect {
        CGRect(x: frame.minX + Self.edge + CGFloat(j) * (tile.width + gap),
               y: NotchGeometry.standardNotchSize.height + 8, width: tile.width, height: tile.height)
    }

    func inner(_ tile: CGRect) -> CGRect { tile.insetBy(dx: inset.width, dy: inset.height) }
}

/// `WindowSnapLayoutTile`'s drawing without its view model: a mini screen of the layout's boxes, the one
/// under the pointer in the accent, and the layout's name beneath.
struct SetupSnapTile: View {
    let layout: WindowLayout
    let activeBox: Int?
    let picker: SetupSnapPicker
    private let m = NotchMetrics(scale: 1)

    var body: some View {
        VStack(spacing: 4 * picker.scale) {
            SetupLayoutGlyph(layout: layout, activeBox: activeBox)
                .padding(.horizontal, picker.inset.width)
                .padding(.vertical, picker.inset.height)
                .frame(width: picker.tile.width, height: picker.tile.height)
                .background(RoundedRectangle(cornerRadius: m.radiusSurface)
                    .fill(activeBox == nil ? NotchPalette.fillRest : NotchPalette.fillHover))
                .overlay(RoundedRectangle(cornerRadius: m.radiusSurface)
                    .strokeBorder(activeBox == nil ? NotchPalette.strokeSubtle : NotchPalette.strokeAccent,
                                  lineWidth: m.thin))
            Text(layout.name)
                .notchText(.micro)
                .foregroundStyle(activeBox == nil ? NotchPalette.fgTertiary : NotchPalette.foreground(.accent))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: picker.tile.width)
    }
}

/// A recent-pair tile, as the picker's wing draws one: cells where each app would go, each with the
/// app's icon, and the whole tile one target.
struct SetupPairTile: View {
    let pairing: WindowsLessonModel.Pairing
    let dragged: WindowsLessonModel.App
    let active: Bool
    let picker: SetupSnapPicker
    private let m = NotchMetrics(scale: 1)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(NotchPalette.strokeContrast, lineWidth: m.thin)
                ForEach(Array(([dragged] + pairing.partners).enumerated()), id: \.offset) { slot, app in
                    cell(app, frame: pairing.frames[slot], in: geo.size)
                }
            }
        }
        .padding(.horizontal, picker.inset.width)
        .padding(.vertical, picker.inset.height)
        .frame(width: picker.tile.width, height: picker.tile.height)
        .background(RoundedRectangle(cornerRadius: 10 * picker.scale, style: .continuous)
            .fill(active ? NotchPalette.fillHover : NotchPalette.fillRest))
        .overlay(RoundedRectangle(cornerRadius: 10 * picker.scale, style: .continuous)
            .strokeBorder(active ? NotchPalette.foreground(.accent) : NotchPalette.strokeSubtle, lineWidth: active ? 2 : 1))
    }

    private func cell(_ app: WindowsLessonModel.App, frame unit: CGRect, in size: CGSize) -> some View {
        let rect = CGRect(x: unit.minX * size.width + 1, y: unit.minY * size.height + 1,
                          width: max(0, unit.width * size.width - 2), height: max(0, unit.height * size.height - 2))
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(NotchPalette.fillHover)
            .overlay { SetupAppIcon(app: app, size: min(rect.width, rect.height) * 0.7) }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// A saved preset in the practice picker's right wing (setup only): its layout with each app's icon in
/// its box, its name beneath, the whole tile one target.
struct SetupPresetTile: View {
    let preset: WindowsLessonModel.Preset
    let active: Bool
    let picker: SetupSnapPicker
    private let m = NotchMetrics(scale: 1)

    var body: some View {
        VStack(spacing: 4 * picker.scale) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(NotchPalette.strokeContrast, lineWidth: m.thin)
                    ForEach(Array(preset.apps.enumerated()), id: \.offset) { box, app in
                        cell(app, frame: WindowsLessonModel.topLeft(preset.layout.boxes[box]), in: geo.size)
                    }
                }
            }
            .padding(.horizontal, picker.inset.width)
            .padding(.vertical, picker.inset.height)
            .frame(width: picker.tile.width, height: picker.tile.height)
            .background(RoundedRectangle(cornerRadius: 10 * picker.scale, style: .continuous)
                .fill(active ? NotchPalette.fillHover : NotchPalette.fillRest))
            .overlay(RoundedRectangle(cornerRadius: 10 * picker.scale, style: .continuous)
                .strokeBorder(active ? NotchPalette.foreground(.accent) : NotchPalette.strokeSubtle, lineWidth: active ? 2 : 1))
            Text(preset.name)
                .notchText(.micro)
                .foregroundStyle(active ? NotchPalette.foreground(.accent) : NotchPalette.fgTertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: picker.tile.width)
    }

    private func cell(_ app: WindowsLessonModel.App, frame unit: CGRect, in size: CGSize) -> some View {
        let rect = CGRect(x: unit.minX * size.width + 1, y: unit.minY * size.height + 1,
                          width: max(0, unit.width * size.width - 2), height: max(0, unit.height * size.height - 2))
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(NotchPalette.fillHover)
            .overlay { SetupAppIcon(app: app, size: min(rect.width, rect.height) * 0.7) }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}

/// `WindowLayoutGlyph`'s mini screen with one box lit in the accent — the snap picker's aimed box.
struct SetupLayoutGlyph: View {
    let layout: WindowLayout
    var activeBox: Int?
    private let m = NotchMetrics(scale: 1)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: m.radiusSurface).strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.thin)
                ForEach(Array(layout.boxes.enumerated()), id: \.offset) { index, box in
                    cell(index, frame: frame(of: box, in: geo.size))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func frame(of box: SnapRegion, in size: CGSize) -> CGRect {
        let unit = WindowsLessonModel.topLeft(box)
        let gap = m.hair
        return CGRect(x: unit.minX * size.width + gap / 2, y: unit.minY * size.height + gap / 2,
                      width: max(0, unit.width * size.width - gap), height: max(0, unit.height * size.height - gap))
    }

    private func cell(_ index: Int, frame: CGRect) -> some View {
        let fill: Color = activeBox == index ? NotchPalette.foreground(.accent) : NotchPalette.fillSelected
        return Rectangle().fill(fill)
            .overlay(Rectangle().strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.thin))
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}
#endif
