#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// A layout's boxes as a small screen, the shape you'll get, so rows aren't told apart by name alone.
/// Drawn as the real thing looks: windows tile the screen edge to edge with no gaps, a single line
/// runs where two meet, and a window in front hides the one behind it. Uncovered screen stays empty.
struct MacsPaneLayoutGlyph: View {
    let boxes: [SnapRegion]
    var size = CGSize(width: 32, height: 20)

    var body: some View {
        Canvas { context, size in
            let screen = CGRect(origin: .zero, size: size)
            let corner = max(2, size.height * 0.14)
            let frame = Path(roundedRect: screen, cornerRadius: corner, style: .continuous)
            let line = max(1, (size.height / 40).rounded())
            context.fill(frame, with: .color(.primary.opacity(0.06)))
            context.clip(to: frame)
            let window = Color(nsColor: .windowBackgroundColor)
            // Back layers first, so the front window covers the one under it.
            let layers = WindowLayout(name: "", boxes: boxes).layers
            for index in boxes.indices.sorted(by: { (layers[$0], -$0) > (layers[$1], -$1) }) {
                let rect = pixelRect(boxes[index].unitRect, in: size)
                context.fill(Path(rect), with: .color(window))
                context.fill(Path(rect), with: .color(.accentColor.opacity(0.3)))
                context.stroke(Path(rect), with: .color(.accentColor), lineWidth: line)
            }
            context.stroke(Path(roundedRect: screen.insetBy(dx: line / 2, dy: line / 2),
                                cornerRadius: corner - line / 2, style: .continuous),
                           with: .color(.accentColor), lineWidth: line)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// A unit rect (AppKit, bottom-left) on the top-left canvas, its edges on whole points so the line
    /// two neighbours share lands on the same pixels and reads as one.
    private func pixelRect(_ unit: CGRect, in size: CGSize) -> CGRect {
        let minX = (unit.minX * size.width).rounded(), maxX = (unit.maxX * size.width).rounded()
        let minY = ((1 - unit.maxY) * size.height).rounded(), maxY = ((1 - unit.minY) * size.height).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
#endif
