#if canImport(AppKit)
import AppKit
import SwiftUI

/// MacsPane's two marks, drawn in code so the icon file, the menu bar, the dropdown, setup and the
/// grant card share one source.
///
/// - `MacsPaneLogo` is the app icon: a slate tile with the notch hanging from its top edge, a window
///   snapped into the left half in blue and its neighbour outlined. It has a dark (slate) face and a
///   light face, and follows the colour scheme unless told which to wear.
/// - `MacsPaneGlyph` is the one-colour mark: a display outline, its notch, a filled left pane and an
///   outlined right one. The menu bar wears it as a template image.
///
/// Geometry is in units of the tile (1 = its side).
struct MacsPaneLogo: View {
    var size: CGFloat = 40
    /// The icon file's own canvas: the tile inset in transparent margin with its drop shadow.
    var iconCanvas = false
    /// Which face to draw; nil follows the surrounding colour scheme.
    var face: ColorScheme?
    /// Only the marks (notch and panes) on a clear square — the layer the system's icon format stacks on its fill.
    var marksOnly = false
    @Environment(\.colorScheme) private var scheme

    /// The pane you aim at in the picker: the system blue the snap highlight uses.
    static let paneBlue = Color(red: 0.04, green: 0.52, blue: 1)

    private var dark: Bool { (face ?? scheme) == .dark }
    private var tileColours: [Color] { dark ? [Color(white: 0.25), Color(white: 0.09)] : [.white, Color(white: 0.89)] }
    private var outlineColour: Color { dark ? Color(white: 0.91) : Color(white: 0.23) }

    var body: some View {
        let tile = iconCanvas ? size * 824 / 1024 : size
        let shape = RoundedRectangle(cornerRadius: tile * 0.225, style: .continuous)
        if marksOnly {
            marks(tile: tile).frame(width: tile, height: tile)
        } else {
            ZStack {
                LinearGradient(colors: tileColours, startPoint: .top, endPoint: .bottom)
                marks(tile: tile)
            }
            .frame(width: tile, height: tile)
            .clipShape(shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: dark ? [.white.opacity(0.35), .white.opacity(0.02)]
                                                                     : [.black.opacity(0.05), .black.opacity(0.16)],
                                                        startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(0.5, tile * 0.0036)))
            .shadow(color: .black.opacity(iconCanvas ? 0.28 : 0), radius: tile * 0.024, y: tile * 0.0146)
            .frame(width: size, height: size)
            .accessibilityLabel("MacsPane")
        }
    }

    /// The notch hanging from the top edge, then the two panes: the left one snapped (filled blue), the
    /// right one waiting (outlined).
    private func marks(tile: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            NotchMarkShape(width: 0.37, height: 0.12, flare: 0.033, radius: 0.044).fill(.black)
            RoundedRectangle(cornerRadius: tile * 0.065, style: .continuous)
                .fill(Self.paneBlue)
                .frame(width: tile * 0.315, height: tile * 0.587)
                .offset(x: tile * 0.163, y: tile * 0.272)
            RoundedRectangle(cornerRadius: tile * 0.054, style: .continuous)
                .strokeBorder(outlineColour, lineWidth: tile * 0.0435)
                .frame(width: tile * 0.293, height: tile * 0.565)
                .offset(x: tile * 0.543, y: tile * 0.283)
        }
        .frame(width: tile, height: tile, alignment: .topLeading)
    }
}

/// MacsPane's one-colour mark. Drawn in the current foreground style, so it tints like an SF Symbol.
struct MacsPaneGlyph: View {
    var body: some View {
        Canvas { context, size in
            let shapes = MacsPaneGlyph.shapes(in: CGRect(origin: .zero, size: size))
            context.stroke(shapes.outline, with: .foreground, lineWidth: shapes.lineWidth)
            context.fill(shapes.notch, with: .foreground)
            context.fill(shapes.filledPane, with: .foreground)
            context.stroke(shapes.openPane, with: .foreground, lineWidth: shapes.lineWidth * 0.75)
        }
        .accessibilityLabel("MacsPane")
    }

    /// The glyph's parts on a 100-unit grid: display outline, notch, the snapped pane, the waiting pane.
    struct Shapes {
        let outline: Path
        let notch: Path
        let filledPane: Path
        let openPane: Path
        let lineWidth: CGFloat
    }

    static func shapes(in rect: CGRect) -> Shapes {
        let u = min(rect.width, rect.height) / 100
        let origin = CGPoint(x: rect.midX - 50 * u, y: rect.midY - 50 * u)
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: origin.x + x * u, y: origin.y + y * u, width: w * u, height: h * u)
        }
        let frame = box(8, 14, 84, 72)
        let notch = NotchMarkShape(width: 30.0 / 84, height: 13.0 / 84, flare: 3.0 / 84, radius: 5.0 / 84).path(in: frame)
        return Shapes(outline: Path(roundedRect: frame, cornerRadius: 15 * u, style: .continuous),
                      notch: notch,
                      filledPane: Path(roundedRect: box(22, 38, 25, 36), cornerRadius: 4 * u, style: .continuous),
                      openPane: Path(roundedRect: box(57, 41, 19, 30), cornerRadius: 3 * u, style: .continuous),
                      lineWidth: 8 * u)
    }

    /// The menu bar's template image.
    static func templateImage(pointSize: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize), flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let shapes = MacsPaneGlyph.shapes(in: rect)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)
            context.setLineWidth(shapes.lineWidth)
            context.addPath(shapes.outline.cgPath); context.strokePath()
            context.addPath(shapes.notch.cgPath); context.fillPath()
            context.addPath(shapes.filledPane.cgPath); context.fillPath()
            context.setLineWidth(shapes.lineWidth * 0.75)
            context.addPath(shapes.openPane.cgPath); context.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacsPane"
        return image
    }
}
#endif
