#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A layout's boxes as a small screen, the shape you'll get, so rows aren't told apart by name alone.
struct MacsPaneLayoutGlyph: View {
    let boxes: [SnapRegion]
    var size = CGSize(width: 32, height: 20)

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size)
            context.stroke(Path(roundedRect: screen.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 3),
                           with: .color(.secondary), lineWidth: 1)
            for box in boxes {
                let unit = box.unitRect
                // Unit rects are AppKit bottom-left; the canvas is top-left.
                let rect = CGRect(x: unit.minX * size.width, y: (1 - unit.maxY) * size.height,
                                  width: unit.width * size.width, height: unit.height * size.height)
                    .insetBy(dx: 1.5, dy: 1.5)
                context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor.opacity(0.35)))
                context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.accentColor), lineWidth: 0.75)
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}
#endif
