#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

/// The notch's text-size scale, injected once at the root of every panel surface (the main panel
/// in the notch's root view, and each peek card, which lives in its own window and so needs the value
/// re-injected). Every notch font goes through `.notchFont`, which multiplies its size by this, so
/// one Settings preset scales the whole notch UI consistently. Defaults to 1.0 for any view shown
/// outside an injected surface.
private struct NotchScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var notchScale: CGFloat {
        get { self[NotchScaleKey.self] }
        set { self[NotchScaleKey.self] = newValue }
    }
}

/// A page-scoped request for shared controls to use the notch's neutral white/grey hierarchy.
/// Focus enables this so linked-todo surfaces stay quiet without changing their appearance on the
/// Calendar, Todos, or Notepad pages.
private struct NotchMonochromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchMonochrome: Bool {
        get { self[NotchMonochromeKey.self] }
        set { self[NotchMonochromeKey.self] = newValue }
    }
}

private struct NotchFontModifier: ViewModifier {
    @Environment(\.notchScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    /// A notch font that scales with the text-size preset. Exact drop-in for
    /// `.font(.system(size: X, weight: W, design: D))` → `.notchFont(X, weight: W, design: D)`:
    /// same base size/weight/design, just multiplied by `notchScale`. Defaults match
    /// `Font.system` (regular weight, default design) so plain sites convert without visual change.
    func notchFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(NotchFontModifier(size: size, weight: weight, design: design))
    }

    /// Scale an arbitrary metric (icon frame, row height, padding) by the text-size preset, so
    /// controls grow with their text instead of cramping. Reads the same env as `.notchFont`.
    func notchScaledFrame(width: CGFloat? = nil, height: CGFloat? = nil) -> some View {
        modifier(NotchScaledFrameModifier(width: width, height: height))
    }
}

private struct NotchScaledFrameModifier: ViewModifier {
    @Environment(\.notchScale) private var scale
    let width: CGFloat?
    let height: CGFloat?

    func body(content: Content) -> some View {
        content.frame(width: width.map { $0 * scale }, height: height.map { $0 * scale })
    }
}

/// Read the live scale inside a view that needs to size non-font metrics by hand
/// (e.g. `padding(.vertical, style.scaled(4))`). A thin wrapper so call sites stay readable.
struct NotchMetrics {
    let scale: CGFloat
    func callAsFunction(_ value: CGFloat) -> CGFloat { value * scale }
}

extension EnvironmentValues {
    var notchMetrics: NotchMetrics { NotchMetrics(scale: notchScale) }
}

/// The notch's compact rounded chip chrome, the **small** of the two standard control heights (the **big**
/// being `notchActionButton`). Every small pill across the notch rides this one height: vertical `m.xs`
/// padding around `.label` text, so they all line up (the modifier sets `.label` semibold itself, a
/// caller must NOT re-set the font, or it would override the standard and break the shared height). The
/// paint intents map to the recurring fills; all share the 12 pt control corner. Apply to a
/// `Text`/`HStack`; the caller still attaches the tap gesture.
enum NotchChipStyle { case neutral, accent, selectedFilter, destructive, quiet, success }
extension View {
    func notchChip(_ style: NotchChipStyle, hovered: Bool = false, disabled: Bool = false) -> some View {
        modifier(NotchChipModifier(style: style, hovered: hovered, disabled: disabled))
    }
}

private struct NotchChipModifier: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let style: NotchChipStyle
    let hovered: Bool
    let disabled: Bool

    func body(content: Content) -> some View {
        content
            .notchText(.label, weight: .semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, m.md)
            .padding(.vertical, m.xs)
            .background { outline.fill(fill) }
            .overlay {
                if style != .quiet {
                    RoundedRectangle(cornerRadius: m.radiusControl)
                        .strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.hairline)
                }
            }
            .contentShape(outline)
            // Smooth the rest→hover fill swap so every chip's hover reads as a deliberate lift rather
            // than an instant flicker (the caller owns the `hovered` flag; this just times its effect).
            .animation(NotchMotion.fast, value: hovered)
    }

    private var outline: RoundedRectangle { RoundedRectangle(cornerRadius: m.radiusControl) }

    private var foreground: Color {
        if disabled { return NotchPalette.fgPrimary.opacity(NotchPalette.dimDisabled) }
        switch style {
        case .destructive: return NotchPalette.foreground(.danger)
        case .success: return NotchPalette.foreground(.success)
        default: return NotchPalette.fgPrimary
        }
    }

    private var fill: Color {
        if disabled { return NotchPalette.fillRest }
        switch style {
        case .neutral: return hovered ? NotchPalette.fillSelected : NotchPalette.fillControl
        case .quiet: return hovered ? NotchPalette.fillSelected : .clear
        case .accent: return NotchPalette.fill(.accent, hovered: hovered)
        case .selectedFilter: return hovered ? NotchPalette.fillAccentSubtleHover : NotchPalette.fillAccentSubtle
        case .destructive: return NotchPalette.fill(.danger, hovered: hovered)
        case .success: return NotchPalette.fill(.success, hovered: hovered)
        }
    }
}

extension View {
    /// The notch's full-width action button, the **big** of the two standard control heights (the **small**
    /// being `notchChip`), behind every primary / secondary call-to-action (the Focus **Start** button, the
    /// Smart Windows **Arrange** footer, the meeting cockpit's **Open in Calendar · Join** and
    /// **Mute · Hold to hear**). Distinctly taller than a compact `notchChip`: `.body` semibold on a
    /// `m.radiusControl` rounded-rect, vertical `m.md` / horizontal `m.md` padding, so every big action button
    /// shares one height (it's padding-based, so it scales with the text preset). The caller supplies the content (icon + label), the tap / hold gesture, and
    /// the hover flag; `disabled` dims fill + foreground via the dim ladder (same contract as `notchChip`);
    /// centred content reads centred, content with a trailing `Spacer` reads left-anchored. `fullWidth`
    /// (the default) stretches edge-to-edge for a footer CTA; pass `false` to hug the content when the
    /// button shares a row with other elements (e.g. Smart Windows' **Arrange** beside its status).
    ///
    /// `width` pins an exact width and `fillHeight` takes the row's height instead of the shared
    /// padding-derived one (the Focus transport stands as tall as its 40pt countdown that way, with no
    /// second number to keep in step). Both apply **inside** the chrome, so the fill takes the size;
    /// from outside you get a content-sized pill floating in a bigger invisible box.
    func notchActionButton(_ style: NotchChipStyle, hovered: Bool = false,
                           disabled: Bool = false, fullWidth: Bool = true,
                           width: CGFloat? = nil, fillHeight: Bool = false) -> some View {
        modifier(NotchActionButtonModifier(style: style, hovered: hovered, disabled: disabled,
                                           fullWidth: fullWidth, width: width, fillHeight: fillHeight))
    }

    /// A segmented-rail chip's chrome: the *selected* segment gets a flat filled "thumb"
    /// (`fillSelected`); an unselected one stays bare on the panel (text only), the way a macOS
    /// segmented control fills only its active segment. The caller pads its own content and supplies the
    /// active/hover state. Used by the Calendar / Todos shown-vs-hidden filter rails and the Processes
    /// active-sort column.
    func notchSegment(active: Bool, hovered: Bool = false) -> some View {
        modifier(NotchSegmentChrome(active: active, hovered: hovered))
    }
}

private struct NotchSegmentChrome: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let active: Bool
    let hovered: Bool

    func body(content: Content) -> some View {
        content.background {
            if active {
                RoundedRectangle(cornerRadius: m.radiusControl).fill(NotchPalette.fillSelected)
            } else if hovered {
                RoundedRectangle(cornerRadius: m.radiusControl).fill(NotchPalette.fillFaint)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: m.radiusControl))
        .animation(NotchMotion.fast, value: hovered)
        .animation(NotchMotion.fast, value: active)
    }
}

/// The shared chrome behind `notchActionButton`, kept in lock-step with `FocusActionButton`'s look so
/// every full-width action reads at the same height and shape.
private struct NotchActionButtonModifier: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let style: NotchChipStyle
    let hovered: Bool
    let disabled: Bool
    let fullWidth: Bool
    var width: CGFloat?
    var fillHeight = false

    func body(content: Content) -> some View {
        content
            .notchText(.body, weight: .semibold)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(foreground)
            .padding(.horizontal, m.md)
            // Both before the background, so the fill takes the requested width rather than hugging
            // the label inside it.
            .frame(width: width)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, m.md)
            // Padding first, so it stays the MINIMUM height and the fill grows past it to the row's.
            // Outside the chrome this stretches an invisible box and leaves the pill its old size.
            .frame(maxHeight: fillHeight ? .infinity : nil)
            .background {
                RoundedRectangle(cornerRadius: m.radiusControl, style: .continuous).fill(fill)
            }
            .contentShape(RoundedRectangle(cornerRadius: m.radiusControl, style: .continuous))
            .animation(NotchMotion.fast, value: hovered)
    }

    private var foreground: Color {
        if disabled { return NotchPalette.fgPrimary.opacity(NotchPalette.dimDisabled) }
        return style == .accent ? Color.white : NotchPalette.fgPrimary
    }

    private var fill: Color {
        if disabled { return NotchPalette.fillControl }
        switch style {
        case .accent: return NotchPalette.fill(.accent, hovered: hovered)
        case .selectedFilter: return hovered ? NotchPalette.fillAccentSubtleHover : NotchPalette.fillAccentSubtle
        case .neutral: return hovered ? NotchPalette.fillHover : NotchPalette.fillControl
        case .quiet: return hovered ? NotchPalette.fillSelected : .clear
        case .destructive: return NotchPalette.fill(.danger, hovered: hovered)
        case .success: return NotchPalette.fill(.success, hovered: hovered)
        }
    }
}

extension View {
    /// The notch's shared section / group-header text treatment: `.label` (12 pt) semibold at
    /// `fgSecondary`. Every group subheading, a footer tray title (Home's Devices / Actions) and every
    /// agenda date header (Home / Calendar / Todos), uses this single definition, so they're identical
    /// by construction rather than by several sites agreeing on the same numbers. Text-only: no glyph,
    /// so a subheading never competes with the row content beneath it.
    func notchSectionTitle() -> some View {
        notchText(.label, weight: .semibold).foregroundStyle(NotchPalette.fgSecondary)
    }
}

extension View {
    /// Group a section's content into a rounded, *clear* inset-grouped surface, a soft recessed fill with
    /// continuous corners and no lit edge, so each section reads as a distinct group on the black panel
    /// (the flat grouped-content layer, the tray is a quiet container; the controls inside it carry the
    /// emphasis). `accent` tints it with the system
    /// accent (the up-next cue); `fill` lets a tray stretch to fill the available height (the agenda);
    /// `expandWidth` (default) spans the offered width, set false for a tray that hugs its content so
    /// it can sit beside another (the Calendar month grid next to its agenda). Every tray carries a
    /// hairline `strokeSubtle` border, so grouped sections read as distinct surfaces consistently across
    /// the tabs (and two adjacent trays, the Todos Scheduled / All todos columns, stay clearly apart).
    /// `inset: false` drops the inner padding for a COMPOUND tray, one subject split into panes by a
    /// full-height internal divider (the Notepad's vault | document), where each pane pads itself.
    func notchTray(accent: Bool = false, fill: Bool = false, expandWidth: Bool = true, inset: Bool = true) -> some View {
        modifier(NotchTrayModifier(accent: accent, fill: fill, expandWidth: expandWidth, inset: inset))
    }
}

private struct NotchTrayModifier: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let accent: Bool
    let fill: Bool
    let expandWidth: Bool
    let inset: Bool

    func body(content: Content) -> some View {
        content
            .padding(inset ? m.md : 0)
            .frame(maxWidth: expandWidth ? .infinity : nil, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: m.radiusSurface, style: .continuous)
                    .fill(accent ? NotchPalette.fillAccentSubtle : NotchPalette.fillTray)
            }
            .overlay {
                RoundedRectangle(cornerRadius: m.radiusSurface, style: .continuous)
                    .strokeBorder(NotchPalette.strokeSubtle, lineWidth: m.hairline)
            }
    }
}

// The shared filter-chip rail (`NotchChipRail`) lives in Components/NotchChipRail.swift
// (ratchet split).

/// A completion/status filter pill, a soft accent wash when active, neutral otherwise. Shared by the Focus
/// activity list and the Todos tab so the two completion filters read and behave identically. The
/// caller owns the tap (the notch is pointer-only, no focus-stealing `Button`).
struct NotchStatusChip: View {
    @Environment(\.notchMetrics) private var m
    @Environment(\.notchMonochrome) private var monochrome
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Text(label)
            .notchChip(active && !monochrome ? .selectedFilter : .neutral,
                       hovered: hovered || (active && monochrome))
            .contentShape(RoundedRectangle(cornerRadius: m.radiusControl))
            .onHover { hovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityLabel(label)
            .accessibilityValue(active ? "On" : "Off")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

extension View {
    /// The shared notch quick-add field chrome, a soft `fillRest` *capsule*, no outline (a clear input
    /// surface, not glass). Focus brightens the fill (`fillHover`) rather than drawing a border; pair it
    /// with an accent leading icon for a stronger cue. Used by every notch quick-add so the field reads
    /// identically across Home / Calendar / Todos.
    func notchFieldChrome(focused: Bool) -> some View {
        modifier(NotchFieldChromeModifier(focused: focused))
    }
}

private struct NotchFieldChromeModifier: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, m.md)
            .padding(.vertical, m.sm)
            .background {
                RoundedRectangle(cornerRadius: m.radiusSurface).fill(focused ? NotchPalette.fillHover : NotchPalette.fillRest)
            }
    }
}

extension View {
    /// The shared notch **editor** field box, a soft `fillRest` rounded-rect (`m.radiusSurface`) carrying a
    /// hairline `strokeSubtle` outline at rest that brightens to an accent border when focused. The
    /// counterpart to `notchFieldChrome` (the pill quick-add field): use this for a *boxy*, tray-like
    /// input where the field is the surface you're editing in (the Calendar/Todos event & todo editors'
    /// title / location / notes fields, the inline custom-duration field). Defined once so every editor
    /// field reads identically rather than each view re-deriving the same fill / radius / focus border.
    /// `compact` tightens the vertical padding for a denser field (notes); the default suits a single line.
    func notchFieldBox(focused: Bool, compact: Bool = false, height: CGFloat? = nil) -> some View {
        modifier(NotchFieldBoxModifier(focused: focused, compact: compact, height: height))
    }
}

private struct NotchFieldBoxModifier: ViewModifier {
    @Environment(\.notchMetrics) private var m
    let focused: Bool
    let compact: Bool
    let height: CGFloat?

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, m.md)
            .padding(.vertical, height == nil ? (compact ? m.xs : m.sm) : 0)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: m.radiusSurface)
                    .fill(NotchPalette.fillRest)
                    .overlay {
                        RoundedRectangle(cornerRadius: m.radiusSurface)
                            .strokeBorder(focused ? NotchPalette.strokeAccent : NotchPalette.strokeSubtle,
                                          lineWidth: focused ? m.thin : m.hairline)
                    }
            }
            .animation(NotchMotion.fast, value: focused)
    }
}

private extension View {
    @ViewBuilder
    func applyHelp(_ text: String?) -> some View {
        if let text { self.help(text) } else { self }
    }
}
#endif
