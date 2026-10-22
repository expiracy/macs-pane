#if canImport(AppKit)
import SwiftUI

/// A single-line notch label that loops its text to reveal the overflow when it would otherwise be clipped,
/// and stays put when it fits. Used for the live-activity strip titles so a long title is fully readable
/// without widening the fixed-width strip or hard-truncating it.
///
/// The subtlety that bit two earlier attempts: the available width must be measured from something that
/// CANNOT be inflated by the title. A `fixedSize` copy of the text demands its natural width, so any
/// container measured *around* it just equals the text width → `overflow` is always ~0 → it never scrolls
/// and silently clips. So here an invisible, NON-fixedSize sizer (which truncates to whatever the flank
/// offers) establishes the box via a `GeometryReader`; the natural text width is measured separately and
/// can't leak into that box. The two are compared to decide whether to loop.
///
/// On the motion path it never tail-truncates — it renders the full text and loops it; `…` is the
/// Reduce-Motion fallback only. The scroll offset is a pure function of `TimelineView`'s clock, so the
/// strip's once-a-second countdown re-render can't reset it. Loop shape: rest at the head so the start is
/// legible, then slide the title off to the left while a second copy follows it in from the right; one
/// scroll of exactly "title + gap" lands the second copy where the first began, so the wrap is seamless.
/// A documented display-size one-off in place of a text role — the Media card's song title, which is
/// set at 22pt like the Focus timer's digits because no role goes that large. Routed through
/// `.notchFont` rather than a raw `Font` so it still grows with the notch's text preset.
struct NotchMarqueeDisplayFont: Equatable {
    let size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
}

struct NotchMarqueeText: View {
    @Environment(\.notchMetrics) private var m
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let text: String
    var role: NotchTextRole = .body
    var weight: Font.Weight?
    /// Struck through, for a title whose event is already over (the day column's past rows).
    var strikethrough = false
    /// Set to type the label at a display size instead of `role` — see `NotchMarqueeDisplayFont`.
    var display: NotchMarqueeDisplayFont?
    /// Native Settings text keeps its semantic macOS font when sharing this overflow behavior.
    var nativeFont: Font?
    /// Short labels may sit in a centered tile; an overflowing loop still starts at the leading edge.
    var alignment: Alignment = .leading
    /// Where the loop's clock starts. Nil = wall-clock (the live strip, always looping); a date = the
    /// loop begins at rest from that moment — a hover-started marquee must open at its head, not at
    /// whatever phase the wall-clock happens to be in.
    var clockOrigin: Date?

    /// The title's natural width, measured from the rendered text (never inflates the container — see above).
    @State private var textWidth: CGFloat = 0

    var body: some View {
        sizer
            .overlay(alignment: alignment) {
                GeometryReader { geo in
                    visible(containerWidth: geo.size.width)
                }
            }
            .clipped()
            .onPreferenceChange(MarqueeTextWidthKey.self) { textWidth = $0 }
            .help(text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    /// Invisible: takes the real available width and establishes the one-line height. NOT `fixedSize`, so it
    /// truncates to the flank rather than forcing the strip wider — this is what makes the width honest.
    private var sizer: some View {
        typed(Text(text))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: alignment)
            .opacity(0)
            .accessibilityHidden(true)   // purely a sizer; the visible overlay carries the title for VoiceOver
    }

    /// The visible label, given the true container width. Decides per-layout whether to loop.
    @ViewBuilder
    private func visible(containerWidth cw: CGFloat) -> some View {
        let overflow = max(0, textWidth - cw)
        let scrolls = !reduceMotion && overflow > 0.5
        Group {
            if scrolls {
                ticker(containerWidth: cw)
            } else if reduceMotion {
                // No motion allowed → a tail-truncated label is the honest fallback.
                typed(Text(text).strikethrough(strikethrough)).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: alignment)
            } else {
                // Fits (or not yet measured): the full text uses the requested alignment.
                measuredTitle.frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .frame(width: cw, alignment: alignment)
        // Soften the TRAILING edge only while looping (the head stays crisp on the left).
        .mask(scrolls ? AnyView(trailingFade) : AnyView(Rectangle()))
    }

    /// Two copies a `gap` apart, slid left at a constant speed; offset derived from wall-clock time so
    /// re-renders never interrupt it. Mounted only while actually scrolling (no 60 fps tick at rest).
    private func ticker(containerWidth cw: CGFloat) -> some View {
        let gap = m.xl
        let span = textWidth + gap
        let scrollTime = max(0.4, Double(span / scrollSpeed))
        let cycle = endRest + scrollTime
        return TimelineView(.animation) { context in
            // A hover-started loop skips most of its first rest: you pointed at the title to read the
            // rest of it, so it moves almost at once (later laps still rest the full `endRest`).
            let elapsed = clockOrigin.map { context.date.timeIntervalSince($0) + (endRest - hoverStartRest) }
                ?? context.date.timeIntervalSinceReferenceDate
            let t = max(0, elapsed).truncatingRemainder(dividingBy: cycle)
            let shift = t < endRest ? 0 : CGFloat((t - endRest) / scrollTime) * span
            HStack(spacing: gap) {
                measuredTitle
                measuredTitle
            }
            .offset(x: -shift)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The title at its natural width, reporting that width up so the overflow test reads the real value.
    private var measuredTitle: some View {
        typed(Text(text).strikethrough(strikethrough))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .background(GeometryReader { geo in
                Color.clear.preference(key: MarqueeTextWidthKey.self, value: geo.size.width)
            })
    }

    /// Every copy of the label is typed HERE, so the sizer, the two scrolling copies and the
    /// Reduce-Motion fallback can never drift apart and measure different widths.
    @ViewBuilder
    private func typed(_ base: Text) -> some View {
        if let nativeFont {
            base.font(nativeFont)
        } else if let display {
            base.notchFont(display.size, weight: display.weight, design: display.design)
        } else {
            base.notchText(role, weight: weight)
        }
    }

    /// A soft fade at the trailing edge only (full colours, so no opacity literal leaks in).
    private var trailingFade: some View {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.9),
            .init(color: .clear, location: 1)
        ], startPoint: .leading, endPoint: .trailing)
    }

    /// Points per second, scaled with the text preset so the scroll reads the same at every size.
    private var scrollSpeed: CGFloat { m(38) }
    /// The pause at the head before the title moves on, in seconds — long enough to read the start.
    private let endRest: TimeInterval = 1.4
    /// The first rest of a hover-started loop (`clockOrigin` set) — just long enough not to lurch.
    private let hoverStartRest: TimeInterval = 0.25
}

/// The label's natural width, surfaced from the rendered text so the overflow test reads the real value.
private struct MarqueeTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
/// A row's one-line title that tail-truncates at rest and, while `active` — the pointer or the keyboard
/// cursor is on its row — loops an overflowing title with `NotchMarqueeText`, starting from its head.
/// The same box either way: a paint change, never a size change (house rule 1.1). A title that fits
/// never moves.
///
/// THE way a row shows an overflowing name (house rule 3.9): the agenda rows' hover marquee, lifted out
/// so every row, menu row and chip-free name slot across the notch reuses it.
///
/// **Where it may go.** A row's flexible name column takes the slot the container offers. A
/// content-hugging chip supplies `cap`: the natural text width is measured separately and the label
/// claims the smaller of that width and the cap in both states, so hover never stretches its chrome.
///
/// **Beside another fact.** Reserve or cap that fact's slot before giving the remaining width to the
/// marquee. A date or count stays fully readable; another external name may use a separate capped
/// marquee. Do not let two unbounded flexible labels fight over the same proposal.
///
/// **Beside a `Spacer`:** nothing else to do — the stack hands the leftover to the Spacer on its own. Do
/// NOT reach for `.layoutPriority(1)` here, even though a plain `Text` beside a Spacer often carries one:
/// a prioritised child is sized FIRST against the whole proposal, and because this one's width is
/// unbounded it then swallows the lot. On the ruler pill that ate the clock and the cues outright.
///
/// **`active`.** Pass the row's own hover/cursor state, or leave it off: `notchMenuRowChrome` publishes
/// pointer-or-cursor state through `\.notchRowActive`. Direct pointer hover on the label also starts it.
///
/// Deliberately NOT driven by `\.notchSnapshotHover`: a still render would catch the loop at an
/// arbitrary phase and no two snapshots of the same page would match. Motion is a feel-pass gate.
struct NotchHoverMarqueeText: View {
    let text: String
    var role: NotchTextRole = .body
    /// Carried through both states — a selected row's title must not change weight when it starts to loop.
    var weight: Font.Weight?
    /// A display-size one-off instead of `role`; carried through both states, like `weight`.
    var display: NotchMarqueeDisplayFont?
    var nativeFont: Font?
    var alignment: Alignment = .leading
    var strikethrough = false
    /// For a content-hugging chip: measure its natural label, then cap that stable slot.
    var cap: CGFloat?
    /// The row's hover/keyboard-cursor state. Nil takes it from `\.notchRowActive` (menu rows).
    var active: Bool?
    /// When the loop started — reset on every hover, so it always opens at the head.
    @State private var origin: Date?
    @State private var hovered = false
    @State private var naturalWidth: CGFloat = 0
    @Environment(\.notchRowActive) private var rowActive

    private var isActive: Bool { hovered || (active ?? rowActive) }

    var body: some View {
        Group {
            if let cap {
                HoverMarqueeSlot(cap: cap, naturalWidth: naturalWidth, empty: text.isEmpty) { label }
                    .background {
                        widthProbe
                            .fixedSize(horizontal: true, vertical: false)
                            .hidden()
                            .background(GeometryReader { geo in
                                Color.clear.preference(key: HoverMarqueeNaturalWidthKey.self, value: geo.size.width)
                            })
                    }
            } else {
                label.frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .onPreferenceChange(HoverMarqueeNaturalWidthKey.self) { naturalWidth = $0 }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onChange(of: isActive, initial: true) { _, on in origin = on ? Date() : nil }
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var label: some View {
        Group {
            if isActive, let origin {
                movingText(origin: origin)
            } else {
                restingText
            }
        }
    }

    private func movingText(origin: Date) -> some View {
        NotchMarqueeText(text: text, role: role, weight: weight, strikethrough: strikethrough,
                         display: display, nativeFont: nativeFont, alignment: alignment,
                         clockOrigin: origin)
    }

    private var restingText: some View {
        let base = Text(text).strikethrough(strikethrough)
        return Group {
            if let nativeFont {
                base.font(nativeFont)
            } else if let display {
                base.notchFont(display.size, weight: display.weight, design: display.design)
            } else {
                base.notchText(role, weight: weight)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private var widthProbe: some View {
        if let nativeFont {
            Text(text).font(nativeFont)
        } else if let display {
            Text(text).notchFont(display.size, weight: display.weight, design: display.design)
        } else {
            Text(text).notchText(role, weight: weight)
        }
    }
}

/// Reports a chip's natural capped width to its parent, accepts a narrower proposal, then gives the
/// marquee that exact width. A flexible `frame(maxWidth:)` alone can leave the marquee's inner
/// GeometryReader unbounded, so the clipped name never learns that it needs to scroll.
private struct HoverMarqueeSlot: Layout {
    let cap: CGFloat
    let naturalWidth: CGFloat
    let empty: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let ideal = empty ? 0 : min(naturalWidth > 0 ? naturalWidth : cap, cap)
        let width = min(ideal, proposal.width ?? ideal)
        let height = label.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct HoverMarqueeNaturalWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Whether the row a label sits in is under the pointer or the keyboard cursor. Row chrome publishes it
/// so a `NotchHoverMarqueeText` nested inside a row's content can loop (house rule 3.9) without every
/// menu row having to hand its hover state down through its content closure.
private struct NotchRowActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchRowActive: Bool {
        get { self[NotchRowActiveKey.self] }
        set { self[NotchRowActiveKey.self] = newValue }
    }
}
#endif
