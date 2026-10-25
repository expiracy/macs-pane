#if canImport(AppKit)
import SwiftUI

/// One clearly bounded drop region: a dashed rounded outline holding a glyph and a label that states
/// what a drop there does ("Drop to Shelf", "AirDrop"). The design draft's collapsed drag-target
/// region (`.wf-strip-drop` + `.wf-strip-drop-label` in `design/notch-wireframe/mock.css`): dashed and
/// quiet at rest; the region under the drag lights, accent wash, accent outline, accent words.
///
/// Rules this component holds, so every caller gets them:
/// - **Lighting is paint only.** Fill, stroke colour and text colour change; the outline's width, the
///   corner, the padding and the label never do (house rule 1.1), so a drag sweeping across two
///   regions never nudges either.
/// - **The words are the action.** The label says what the drop does, not what the region is called.
/// - **Display only.** It takes no drop and no hover itself; the owner hit-tests the drag and passes
///   `lit`, because SwiftUI hands a drop to one target only (see `NotchDropDelegate`).
///
/// Same vocabulary as Customize's grid well (`HomeCustomizeGrid.cellWell`): dashed `m.xs` rhythm,
/// `fillAccentSubtle` + `strokeAccent` when targeted.
struct NotchDropRegion: View {
    let systemImage: String
    let title: String
    /// The drag is over this region, a release here does what the label says.
    let lit: Bool
    @Environment(\.notchMetrics) private var m

    /// How far a label may shrink to stay whole inside a notch-bound region ("Hold for layouts" at XL
    /// needs about 0.65; at Default nothing shrinks).
    static let minimumTextScale: CGFloat = 0.6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.radiusSurface, style: .continuous)
        HStack(spacing: m.xs) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1)
        }
        // The region's size is set by the physical notch (its height, and a wing's width beside the
        // camera), which the text-size preset can't grow, so at Large/XL the words shrink to fit the
        // outline rather than truncate the action away ("Drop to…").
        .minimumScaleFactor(NotchDropRegion.minimumTextScale)
        .notchText(.label, weight: .semibold)
        .foregroundStyle(lit ? NotchPalette.foreground(.accent) : NotchPalette.fgSecondary)
        .padding(.horizontal, m.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(lit ? NotchPalette.fillAccentSubtle : Color.clear))
        .overlay(shape.strokeBorder(lit ? NotchPalette.strokeAccent : NotchPalette.strokeContrast,
                                    style: StrokeStyle(lineWidth: m.thin, dash: [m.xs, m.xs])))
        .animation(NotchMotion.fast, value: lit)
        .accessibilityElement(children: .combine)
    }
}
#endif
