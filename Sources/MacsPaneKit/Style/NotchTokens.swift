#if canImport(AppKit)
import SwiftUI
import MacsPaneCore

// The notch design system's token catalog — the single source of truth for type, spacing, radii,
// control sizes, colour, borders and elevation. Pairs with `NotchStyle.swift` (which holds the
// `notchScale` environment + `notchFont`/`NotchMetrics`/`notchChip` this builds on). Every notch
// view should compose from the tokens here rather than hardcoding values, so the look stays
// consistent and the text-size preset scales the whole UI proportionally.
//

// MARK: - Type scale

/// The six text roles every notch label is built from — used instead of raw point sizes so type is
/// consistent across tabs and the text-size preset scales them as one set. Each role carries the
/// weight + design it's almost always paired with (override per call only when a site genuinely
/// differs). Sizes are *base* (pre-scale); `.notchText` multiplies by `notchScale`, exactly like
/// `.notchFont`.
enum NotchTextRole {
    /// 11pt — counts, state tags, footer hints, RSVP chips.
    case micro
    /// 11pt — the secondary line under a title: app name, location, time, day header.
    case meta
    /// 13pt — chips, column headers, gauge labels, button text.
    case label
    /// 13pt — the primary thing you read in a row: process / event / file name, a field's value.
    case body
    /// 15pt — emphasis: the editor title, a peek card's event title.
    case callout
    /// 17pt — peek-card and section headers.
    case title

    var size: CGFloat {
        switch self {
        case .micro: return 11
        case .meta: return 11
        case .label: return 13
        case .body: return 13
        case .callout: return 15
        case .title: return 17
        }
    }

    /// The weight the role reads at by default. `body` is the one non-rounded, plainer role because
    /// it carries the longest, most-read strings; the rest lean rounded/heavier to punctuate.
    var weight: Font.Weight {
        switch self {
        case .micro: return .semibold
        case .meta, .label, .body: return .medium
        case .callout, .title: return .bold
        }
    }

    var design: Font.Design {
        switch self {
        case .body: return .default
        default: return .rounded
        }
    }
}

extension View {
    /// Apply a type role from the scale — the semantic replacement for `.notchFont(rawSize, …)`.
    /// Scales with the preset and uses the role's default weight/design unless overridden.
    func notchText(_ role: NotchTextRole, weight: Font.Weight? = nil, design: Font.Design? = nil) -> some View {
        notchFont(role.size, weight: weight ?? role.weight, design: design ?? role.design)
    }
}

// MARK: - Metrics (text-scaled spatial tokens)

/// Named, text-scaled spatial tokens layered onto `NotchMetrics` (declared in `NotchStyle.swift`).
/// A view reads `@Environment(\.notchMetrics)` and uses these instead of raw numbers, so spacing,
/// row heights, radii and border widths all grow with the text preset — the "proportional zoom"
/// rule. The raw `callAsFunction` escape hatch stays for genuine one-offs.
extension NotchMetrics {
    // Spacing scale — 7 steps. `md` is the standard gap / content-padding unit.
    var hair: CGFloat { 2 * scale }
    var xs: CGFloat { 4 * scale }
    var sm: CGFloat { 6 * scale }
    var md: CGFloat { 8 * scale }
    var lg: CGFloat { 12 * scale }
    var xl: CGFloat { 16 * scale }
    var xxl: CGFloat { 20 * scale }

    // Control sizes.
    var rowStandard: CGFloat { 30 * scale }   // list rows (Processes, agenda) — the roomy baseline
    /// A COMPACT list row — a column of names under a search field (the Notepad rail). Sized to
    /// stand level with the shared quick-add field (`notchFieldChrome`), so the head of the column
    /// and every row beneath it share one height; it still clears a `notchChip`, so a row's
    /// hover-reveal action can't stretch it. Reach for `rowStandard` for the roomy agenda rows.
    var rowCompact: CGFloat { 26 * scale }
    /// A title over an explicit Reminders list name, with a due value centred beside both lines.
    var todoRow: CGFloat { 50 * scale }
    /// A row NESTED inside another row — the linked todos an agenda row unfolds beneath its title.
    /// Shorter than `rowCompact` because it is a sub-list of a row rather than a list of its own, and
    /// a day of unfolded events must still read as an agenda; it clears a `.meta` line plus its
    /// tick target, which is all it holds.
    var rowSub: CGFloat { 22 * scale }
    /// A floating card's heading band — a `.micro` eyebrow stating the action over a `.callout` title
    /// (the todo picker's owner line). Two text lines plus the card's `xs` breathing room, fixed so
    /// the card's height maths can bill it without measuring.
    var ownerHeading: CGFloat { 40 * scale }
    /// The agenda row's leading **time column** — an event's start/end, or a todo's time / `All-day` /
    /// overdue date — right-aligned. Shared by the Home, Calendar and Todos agendas so the colour stripe,
    /// the checkbox slot and the title all line up at the same x across the three tabs (the cross-tab
    /// alignment rule: switching tabs never shifts the title column). The checkbox slot beside it reuses
    /// `iconRow`, so an event row can reserve that slot as empty whitespace and still align with a todo.
    var agendaTimeColumn: CGFloat { 47 * scale }
    /// The agenda row's **head band** — the collapsed row's height, before any linked todos unfold
    /// beneath it. It is the two-line time column's height (`.meta` start over `.micro` end), and the
    /// title line stands the SAME height so the trailing cues — the todo pill, RSVP, Join — centre on
    /// the row rather than on the title's one body line, which is shorter and top-aligned. Fixed as
    /// a minimum, not measured: the time column and the title line cannot see each other, and a band
    /// that grew with the row would drop the pill mid-list once its todos unfolded.
    var agendaRowHead: CGFloat { 26 * scale }
    var tabPill: CGFloat { 30 * scale }       // the tab-switcher pill
    /// The Todos day strip's cell — a weekday eyebrow over a day number over a dot row, and a drop
    /// target: tall enough to aim at while holding a reminder, short enough that seven of them leave
    /// the hour ruler its height. The same size as a `Home` action tile's touch target, deliberately.
    var dayCell: CGFloat { 44 * scale }
    var dayTile: CGFloat { 30 * scale }       // the Calendar day column's date tile — the grid cell carried into the list
    var freeLineH: CGFloat { 14 * scale }     // a "free until 1 PM" line between the day column's rows
    /// The hour ruler's left gutter (where the hour labels sit and the gridlines begin) and the label
    /// column inside it — a `.micro` "14:30" (or "All-day") plus breathing room, left-aligned.
    var rulerGutter: CGFloat { 42 * scale }
    var rulerLabel: CGFloat { 36 * scale }
    /// A pill's list-hue tick — the ruler pill's leading completion circle, `.micro`-sized so a row of
    /// two pills at one slot still fits the column.
    var pillTick: CGFloat { 12 * scale }
    var rulerPill: CGFloat { 18 * scale }
    /// One half-hour row of the scrolling hour ruler — a `rulerPill` with room above and below, so a
    /// half hour holds its own todos without touching the next row's.
    var rulerHalfHour: CGFloat { 26 * scale }     // a ruler pill's laid-out height — the ruler keeps a row this far inside its edges
    /// A fold row of the ruler card ("00–08 · 2 todos"): a `.micro` line with room, slimmer than a content row.
    var rulerFold: CGFloat { 22 * scale }
    var iconRow: CGFloat { 20 * scale }       // a row's / peek header's leading icon
    var iconChip: CGFloat { 24 * scale }      // a circular icon button sized to sit level with a `notchChip` (live-activity strip)
    var iconSmall: CGFloat { 14 * scale }     // chip glyphs, chevrons
    var rowActionHit: CGFloat { 26 * scale }  // a list row's hover-reveal action icon — its square hit target
    var gaugeBarH: CGFloat { 6 * scale }      // system gauge bars
    var alertRailH: CGFloat { 2 * scale }     // the live-activity strip's lifetime rail — a hair under the notch line
    /// The leeway below the notch line that the lifetime rail sits in. EVERY alert strip has it — a toast
    /// and a cue share one silhouette — so the notch sizes the collapsed surface off the same base
    /// (`alertRailBandBase`) rather than a second copy of the number that could drift from this one.
    var alertRailBand: CGFloat { Self.alertRailBandBase * scale }
    static let alertRailBandBase: CGFloat = 12
    /// A Compact alert's flank beyond each side of the camera — just room for the one glyph centred
    /// in the leading flank, and the same again in plain black on the trailing side. Draft v88–v92.
    var alertCompactFlank: CGFloat { alertEdge + alertCompactGlyph }   // the edge margin, then the glyph
    /// EVERY alert strip's outer margin — Wide, fitted and Compact alike — from the strip's edge to its
    /// first / last content ("the margin on left and right for ALL notifications is the
    /// same"). The corner's radius plus `lg`, so content clears the curve.
    var alertEdge: CGFloat { rootTopRadiusCompact + lg }
    /// A fitted alert's level meter (volume, brightness).
    var alertFittedMeter: CGFloat { 64 * scale }
    var alertCompactGlyph: CGFloat { 16 * scale }   // the Compact strip's one glyph / cover

    // MARK: - The camera strip's fixed sizes (the one place values deliberately DON'T scale)
    //
    // The camera strip is only as tall as the physical notch, so its title and controls are bound to
    // hardware rather than to the text-size preset — scaling them would clip against the top edge or
    // crowd the tabs below. They live here as named statics rather than as literals in the view: the
    // exception stays documented in the token file where you'd look for it, and there is one place to
    // change if the strip's proportions ever move.
    static let stripTitleSize: CGFloat = 18
    static let stripGlyphSize: CGFloat = 14
    static let stripControlPad: CGFloat = 6
    /// The inbox glyph's unseen count — a small capsule on the control's corner.
    static let stripBadgeSize: CGFloat = 9
    static let stripBadgeHeight: CGFloat = 13
    static let stripBadgePad: CGFloat = 3
    /// The month grid's per-day event count — a base size `notchFont` scales; smaller than `micro` so
    /// it sits as a superscript beside the day number rather than as a second number.
    static let dayCountSize: CGFloat = 8
    var sparkRowH: CGFloat { 14 * scale }     // a list row's trend chart, sitting under its figure
    var sparkGaugeH: CGFloat { 22 * scale }   // a header gauge's history chart, standing in for its bar
    // The System page: This Mac's gauge blocks, the per-core cells, and the apps table's stat cells.
    var systemGaugeH: CGFloat { 64 * scale }     // label · 17 pt number · caption, graph behind
    var systemCoreCellH: CGFloat { 30 * scale }  // one core's label, load and history
    var systemCoreCellMinW: CGFloat { 48 * scale }
    var systemCellH: CGFloat { 26 * scale }      // a stat cell: the number over the app's history
    // Control-Center-style tiles — Home's Devices ring tiles + Actions tiles.
    var tileWidth: CGFloat { 92 * scale }      // a tile's fixed width (three fit the right rail)
    var tileMinHeight: CGFloat { 76 * scale }  // a tile's height — a battery ring tile fills it, so action tiles match
    var batteryRing: CGFloat { 30 * scale }    // the battery ring's diameter in Home's compact Devices tray
    // Home's widget band — the text widgets share what's left; compact widgets stack in a fixed column.
    var homeCompactColumn: CGFloat { 156 * scale }    // Focus over Devices & actions
    var homeGridRow: CGFloat { 62 * scale }           // one Home grid row: fixed, so more rows = a taller page
    var homeFocusRing: CGFloat { 40 * scale }         // the compact Focus tray's progress ring
    var ringStroke: CGFloat { 3.5 * scale }    // the battery ring's stroke width

    // Content surfaces stay quiet; pressable controls and dropdowns have a softer corner.
    // Both follow the text-size preset. The physical notch shell and true circles differ.
    var radiusSurface: CGFloat { 8 * scale }
    var radiusControl: CGFloat { 12 * scale }

    // Root notch silhouette tokens. These are distinct from content-card radii because the root
    // shape is tied to the physical camera strip and changes with the panel footprint.
    var rootTopRadiusExpanded: CGFloat { 19 * scale }
    var rootTopRadiusCompact: CGFloat { 6 * scale }
    var rootBottomRadiusExpanded: CGFloat { 24 * scale }
    var rootBottomRadiusCompact: CGFloat { 14 * scale }

    // Border weights — scale up only (smallest preset is 1.1), so hairlines never vanish.
    var hairline: CGFloat { 0.5 * scale }
    var thin: CGFloat { 1 * scale }
    var medium: CGFloat { 1.5 * scale }
    var thick: CGFloat { 2 * scale }

    // Scrollbar lane (`NotchScrollView`): reserved lane, the idle bar inside it, and the gutter
    // between the bar and the content it never overlaps.
    var scrollLane: CGFloat { 8 * scale }
    var scrollIdle: CGFloat { 5 * scale }
    var scrollGap: CGFloat { 4 * scale }

    /// The filter-chip rail's reserved height — just a chip (24), no scrollbar lane. Reserved even when
    /// empty, so a chip-less tab still lines up with a populated one across a Calendar↔Todos switch;
    /// `NotchScrollView` adds the horizontal lane on top only when the chips actually overflow.
    var chipRailMin: CGFloat { 24 * scale }

    /// A MICRO pill's height — `.micro` text in `hair` padding, the small capsule the todo picker's
    /// linked band is built from (its chips and its Clear button). Stated as a token rather than left
    /// to the text's natural size so a rail of them has a definite height the layout maths can bill
    /// for, and so the capsule fills its button exactly. Sits a step under `chipRailMin`, which is the
    /// filter rail's roomier `.label` chip.
    var chipRailMicro: CGFloat { 16 * scale }

    /// The floating todo-picker card's widths. `linkCard` is the Notepad's, floated from a strip
    /// above the paper where it has always fit; `linkCardWide` is the agenda rails', where the card
    /// floats over a row closer to this width and a narrower card truncated every title while the
    /// due column fought them for the rest.
    var linkCard: CGFloat { 320 * scale }
    var notepadRailWidth: CGFloat { 220 * scale }
    var notepadCreationWidth: CGFloat { 260 * scale }
    /// Media: the Now playing cover, its transport buttons, and the Volume mixer row / icon / route menu.
    /// The cover is the card's full height — the artwork is the main thing on the page.
    var mediaArtwork: CGFloat { 140 * scale }
    var mediaTransport: CGFloat { 32 * scale }
    var mediaTransportPrimary: CGFloat { 44 * scale }
    var mediaRow: CGFloat { 44 * scale }
    var mediaAppIcon: CGFloat { 28 * scale }
    var mediaIdentityWidth: CGFloat { 156 * scale }
    var mediaRouteWidth: CGFloat { 166 * scale }
    var mediaOutputSlider: CGFloat { 150 * scale }
    var mediaMenuWidth: CGFloat { 240 * scale }
    /// A slider's round thumb — the Media level and position sliders.
    var sliderThumb: CGFloat { 14 * scale }
    /// A small in-panel menu's width (the Todos `Lists ▾` dropdown, pick chips, Obsidian, Create):
    /// room for a name beside its dot and tick AND for the menu's key footer ("↑↓ move · return
    /// choose · esc close") on one line. Every simple menu is this wide.
    var menuWidth: CGFloat { 220 * scale }
    /// A menu whose rows carry a second fact (a calendar's account, a preset's shape, a todo's time)
    /// or a month grid — the one other menu width. Search-and-pick cards use `linkCard`.
    var menuWidthWide: CGFloat { 280 * scale }
    /// A time-stepper dropdown: wide enough for the value between symmetric −/+ targets and for the
    /// compact preset rail beneath it, shared by Calendar and Focus quick-add.
    var timeStepperMenuWidth: CGFloat { 300 * scale }
    /// Calendar quick-add's compact month grid plus its paired clock fields.
    var dateTimePickerMenuWidth: CGFloat { 308 * scale }
    /// The bounded two-column clock popover and its five-row scrolling viewport.
    var dateTimePickerPopoverWidth: CGFloat { 156 * scale }
    var dateTimePickerListHeight: CGFloat { 144 * scale }
    var linkCardWide: CGFloat { 440 * scale }

    // The event page (`CalendarEventDetailView`): the record tray | the Who + Todo column.
    /// The right column's width — two trays of rows (a name and its reply word, a tick and a title)
    /// beside the record; the record keeps the rest of the panel, so its notes get the width.
    var eventSideColumn: CGFloat { 300 * scale }
    /// The record tray's label column ("Calendar" · "Where" · "When" …) — every value starts at one x.
    var eventLabelColumn: CGFloat { 72 * scale }
    /// A typed time pill's width — "10:00 AM" in `.label` plus the pill's padding.
    var eventTimePill: CGFloat { 84 * scale }
    /// The location pill's ceiling — a typed field that would otherwise stretch to the row's edge and
    /// read as a form box rather than a value.
    var eventLocationPill: CGFloat { 280 * scale }
    /// The widest an event's or a todo's title runs on its edit page, as text and as the field.
    var editorTitleField: CGFloat { 320 * scale }
    /// The data-driven colour dot beside a calendar's or list's name.
    var calendarDot: CGFloat { 8 * scale }
    /// A person's initials disc in the Who tray — level with its `rowCompact` row.
    var avatar: CGFloat { 22 * scale }

    /// Inner horizontal / section inset added *beyond* the notch's curved corner radius (the corner
    /// radius itself is fixed geometry, not a text metric, so it isn't part of this).
    var contentInset: CGFloat { 12 * scale }

    /// The vertical gap between the camera strip (the tab bar / takeover-page title that sits in the
    /// physical-notch strip) and where every tab's content begins — applied ONCE, at the `belowStrip`
    /// seam in the notch's root view, never per-tab. Every tab, peek page and takeover route therefore starts
    /// at the same distance below the strip: a tab that pads its own top diverges and the content jumps
    /// on a tab switch (the layout-standard "top inset is identical on every tab"). One token = one place
    /// to tune it.
    var tabContentTop: CGFloat { sm }
}

// MARK: - Colour

/// The notch's complete colour vocabulary: white-over-black surfaces plus exactly four semantic
/// intents. Colour encodes *meaning* (and so never scales); opacity encodes hierarchy and state.
/// Every notch colour comes from here.
enum NotchPalette {
    // Surfaces & fills (white over the black panel). One ladder from barely-there to pressed.
    static let surfaceBase = Color.black
    /// floating peek-card fill (slightly translucent so it reads as hovering over content)
    static let peekSurface = Color.black.opacity(0.92)
    /// A raised popover/dropdown surface — lifts off the black panel so an in-panel dropdown (the
    /// editor date/time pickers, the quick-add list autocomplete) reads as a separate floating layer.
    static let surfaceRaised = Color(white: 0.13)
    static let fillFaint = Color.white.opacity(0.04)      // secondary / zebra row
    static let fillRest = Color.white.opacity(0.06)       // resting interactive surface
    static let fillHover = Color.white.opacity(0.12)      // hover
    static let fillSelected = Color.white.opacity(0.16)   // selected neutral surface
    static let fillStrong = Color.white.opacity(0.22)     // pressed / strong (selected calendar day)
    static let fillControl = Color.white.opacity(0.10)    // flat resting fill of a neutral control (chip / cell)
    static let fillAccentSubtle = Color.accentColor.opacity(0.16)  // faint accent wash on a targeted region (the drop slot)
    /// …its hover — the brighter step for an *interactive* subtle-accent surface (quick-add date-token
    /// chip)
    static let fillAccentSubtleHover = Color.accentColor.opacity(0.24)
    /// a *non-interactive* accent tint marking a spanned range (the editor month-grid's multi-day-event
    /// span)
    static let fillAccentRange = Color.accentColor.opacity(0.25)
    /// section-tray fill — a soft *clear* surface; held ≤5% so the 4–6% rows/tiles/gauges resting
    /// inside a tray aren't swallowed. The fill alone carries the grouping (glass is reserved for the
    /// controls sitting on top)
    static let fillTray = Color.white.opacity(0.05)
    /// A dark scrim drawn *behind* a glyph that sits over arbitrary content (e.g. the Shelf's pin badge
    /// over a thumbnail), so the glyph stays legible whatever it overlaps. Black — it darkens, not lightens.
    static let scrim = Color.black.opacity(0.55)

    // Foreground (text & icons) — opacity is the hierarchy.
    static let fgPrimary = Color.white
    static let fgSecondary = Color.white.opacity(0.6)
    static let fgTertiary = Color.white.opacity(0.4)
    static let fgFaint = Color.white.opacity(0.3)
    /// The inner session ring uses the chosen slate focus and pearl break pair. The outer phase ring
    /// keeps its grey track; only elapsed focus time uses the fixed blue fill.
    static let focusRingWorkFill = Color(red: 131.0 / 255, green: 148.0 / 255, blue: 165.0 / 255)
    static let focusRingWorkTrack = focusRingWorkFill.opacity(0.30)
    static let focusRingBreakFill = Color(red: 211.0 / 255, green: 216.0 / 255, blue: 220.0 / 255)
    static let focusRingBreakTrack = focusRingBreakFill.opacity(0.25)
    static let focusPhaseWorkFill = Color(red: 10.0 / 255, green: 132.0 / 255, blue: 255.0 / 255)
    static let focusPhaseBreakFill = Color.white.opacity(0.82)

    // Strokes (border + divider colours; widths come from `NotchMetrics`).
    static let strokeSubtle = Color.white.opacity(0.12)       // dividers, card outlines, idle borders
    static let strokeContrast = Color.white.opacity(0.30)     // glyph frames, day ring
    static let strokeSelected = Color.accentColor.opacity(0.7)  // selection outline
    static let strokeAccent = Color.accentColor.opacity(0.9)    // pinned, drop-target, snap-hot

    /// The translucent accent wash filling a Magnet-style snap "ghost" (the preview of where a window
    /// will land). Fainter than `fill(.accent)` (a solid chip surface) so the target reads as a
    /// see-through overlay, not an opaque panel; paired with `strokeAccent` for the bold edge.
    static let dropGhostFill = Color.accentColor.opacity(0.22)

    /// The wash under a filled sparkline — faint enough that the line stays the thing you read, and
    /// that a chart drawn where a gauge bar used to be doesn't out-weigh the bar it replaced.
    static let sparklineFill: Double = 0.26
    /// A graph drawn BEHIND a number (System's gauges and stat cells): faint enough that the figure
    /// on top stays the thing you read.
    static let backdropFill: Double = 0.13
    static let backdropLine: Double = 0.5
    /// The heat wash under a stat cell (Task Manager's grammar): a calm floor plus up to this much
    /// more tint as the value climbs, so a column of many rows scans by colour.
    static let heatWashFloor: Double = 0.03
    static let heatWashRange: Double = 0.12

    /// The four intent hues in the notch. Content data may carry its own hue.
    enum Intent { case accent, danger, warning, success }

    /// Foreground (text / icon) colour for an intent — e.g. a destructive label or a status glyph.
    static func foreground(_ intent: Intent) -> Color {
        switch intent {
        case .accent: return .accentColor
        case .danger: return .red.opacity(0.95)
        case .warning: return .orange
        case .success: return .green
        }
    }

    /// A semantic status colour as a faint chip/badge background (e.g. the peek RSVP chip) — used
    /// when the tint comes from a status that isn't one of the four `Intent`s (so `fill(_:)` can't).
    static func tintedBadge(_ color: Color) -> Color { color.opacity(0.15) }

    /// A window's icon hue as a Smart Windows preview-tile surface — a faint wash (brighter when it's
    /// the drag's drop target) plus a matching border. The hue is data-driven (per app), so it can't be
    /// an `Intent`; these keep the opacities a token rather than a literal at the call site.
    static func windowFill(_ hue: Color, highlighted: Bool = false) -> Color { hue.opacity(highlighted ? 0.34 : 0.18) }
    static func windowStroke(_ hue: Color, highlighted: Bool = false) -> Color { hue.opacity(highlighted ? 0.95 : 0.55) }

    /// Fill (background) colour for an intent, at rest or hovered — e.g. a chip or button surface.
    static func fill(_ intent: Intent, hovered: Bool = false) -> Color {
        switch intent {
        case .accent: return .accentColor.opacity(hovered ? 1.0 : 0.85)
        case .danger: return .red.opacity(hovered ? 0.28 : 0.14)
        case .warning: return .orange.opacity(hovered ? 0.20 : 0.12)
        case .success: return .green.opacity(hovered ? 0.20 : 0.12)
        }
    }

    // State-dim ladder — the opacity applied over a whole element to de-emphasise it by state.
    // One ladder reused everywhere so "dimmed" reads consistently across tabs.
    static let dimDisabled: Double = 0.35   // a disabled control
    static let dimInFlight: Double = 0.4    // a Processes row whose close/quit is pending
    static let dimDeclined: Double = 0.4    // a declined invite (paired with strikethrough)
    static let dimPending: Double = 0.55    // an unanswered invite
    static let dimMaybe: Double = 0.75      // a tentative invite
    static let dimLifted: Double = 0.55     // a backlog row lifted by a keyboard placement (the marker carries its title)
    static let dimPast: Double = 0.5        // a Calendar day-column row whose event has already ended (paired with strikethrough)

    // Hand-rolled control hover ladder — opacity applied over the *tint* of the Shelf's real-`Button`
    // controls (`LabeledAction` / `ZipGlyphButton`), which deliberately aren't `notchChip`s (they need
    // a true Button on the key-capable Shelf panel — see FileShelfView). Dimmed at rest, near-full on
    // hover; a prominent confirm fills solid. Full (1.0) on hover is written inline as `1`.
    static let controlContentRest: Double = 0.6    // a tinted label / glyph at rest
    static let controlContentHover: Double = 0.95  // …on hover
    static let controlFillRest: Double = 0.82      // a prominent (confirm) fill at rest
    static let controlGlyphRest: Double = 0.85     // the ZipGlyphButton glyph at rest

    // Gauge load ramp: a system gauge (CPU / RAM / GPU) shifts from calm to alarming with load.
    static let gaugeWarnThreshold: Double = 0.70
    static let gaugeDangerThreshold: Double = 0.90

    /// Colour for a 0…1 load on a system gauge: the calm `accent` until 70 %, `warning` past that,
    /// `danger` past 90 %.
    static func gaugeColour(forLoad load: Double) -> Color {
        if load > gaugeDangerThreshold { return foreground(.danger) }
        if load > gaugeWarnThreshold { return foreground(.warning) }
        return .accentColor
    }
}

// MARK: - Elevation

/// The notch's three shadow levels. Depth is a fixed cue, so — unlike spacing — shadows don't scale
/// with the text preset.
enum NotchElevation {
    case low    // resting tiles
    case mid    // in-panel dropdowns
    case high   // floating peek cards

    var radius: CGFloat {
        switch self {
        case .low: return 2
        case .mid: return 9
        case .high: return 22
        }
    }
    var y: CGFloat {
        switch self {
        case .low: return 1
        case .mid: return 4
        case .high: return 8
        }
    }
    var opacity: Double {
        switch self {
        case .low: return 0.2
        case .mid, .high: return 0.45
        }
    }
}

extension NotchPalette {
    static let panelShadow = Color.black.opacity(0.45)
    static let panelShadowRadius: CGFloat = 12
    static let panelShadowY: CGFloat = 6
}

extension View {
    /// Apply one of the notch's fixed elevation shadows (all pure-black, like the panel itself).
    func notchShadow(_ level: NotchElevation) -> some View {
        shadow(color: .black.opacity(level.opacity), radius: level.radius, y: level.y)
    }
}

// MARK: - Motion

/// The notch's motion vocabulary — the single source of truth for how every notch state change is
/// timed, so the whole UI animates as one coherent thing.
/// Two curved durations cover almost everything (a quick `fast` and a deliberate `panel`), a heavier
/// `content` step covers list re-layouts, and the three springs are the panel's expand/collapse
/// family — kept at their established values . Motion is a *timing* cue, not
/// geometry, so — like colour and shadow — it does **not** scale with the text preset.
enum NotchMotion {
    /// Raw durations, exposed so a site that genuinely needs a different curve (e.g. a decelerating
    /// `.easeOut` row-insert) can still use the shared timing: `.easeOut(duration: NotchMotion.panelDuration)`.
    static let fastDuration: Double = 0.12     // hover, selection, a small live-feedback line
    static let panelDuration: Double = 0.18    // tab switch, editor open/close, dropdowns, toggles, state swaps
    static let contentDuration: Double = 0.24  // heavier content re-layouts: list reloads, completion fade, zip grow
    static let cursorBlink: Double = 0.55      // one half of a text cursor's blink (the key recorder's)
    static let leaveGrace: Double = 0.2        // how long the pointer must stay off an armed bin before it resets

    /// Quick feedback — hover highlights, selection fills, a chip toggling. The snappiest tier.
    static let fast = Animation.easeInOut(duration: fastDuration)
    /// The workhorse — a panel/state change you should *notice*: tab switches, a section or dropdown
    /// opening, a toggle revealing controls, an in-place confirm morph.
    static let panel = Animation.easeInOut(duration: panelDuration)
    /// A larger content rearrangement settling into place — a reloaded list, a row completing and
    /// leaving, the Shelf's zip field growing.
    static let content = Animation.easeInOut(duration: contentDuration)

    /// The panel's expand/collapse spring family (boring.notch-derived; values unchanged): `open` has
    /// a touch of life, `close` is critically damped so it settles without bounce, `dragTarget` (the
    /// drag-to-widen affordance) sits between.
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.8)
    static let close = Animation.spring(response: 0.45, dampingFraction: 1.0)
    static let dragTarget = Animation.spring(response: 0.4, dampingFraction: 0.85)
    /// An alert changing drawing (Wide ↔ Compact, one announcement to the next) — the Dynamic Island's
    /// shape: the width springs with a small, tasteful overshoot so the strip visibly lands. Its content
    /// never squeezes through the change: it leaves first (`alertContentOut` — fade, a touch of blur,
    /// shrinking to `alertContentScale`) and comes back on `alertContentReturn` while the spring is
    /// still settling (`alertContentIn` after the width starts). Reduce Motion: `panel`, no blur/scale.
    static let alertMorph = Animation.spring(response: 0.44, dampingFraction: 0.76)
    static let alertContentOut: Double = 0.1
    /// A deliberate outward swipe sends the alert's content toward that edge before the strip morphs.
    static let alertSwipeDismissDuration: Double = contentDuration
    static let alertSwipeDismiss = Animation.easeOut(duration: alertSwipeDismissDuration)
    static let alertContentIn: Double = 0.14
    static let alertContentReturn = Animation.spring(response: 0.32, dampingFraction: 0.9)
    static let alertContentBlur: CGFloat = 5
    static let alertContentScale: CGFloat = 0.94

    /// Something arriving or moving into place inside a page — a drawn box, a tile joining a row, a
    /// row reordering, a popover opening. Springy but settled: no visible overshoot.
    static let settle = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Something landing where it was dropped — an app filling a box. A small, deliberate overshoot.
    static let land = Animation.spring(response: 0.38, dampingFraction: 0.64)
    /// A dragged block hopping from one grid cell to the next (Home's widgets, a drawn layout box):
    /// quick enough to stay under the pointer, damped so each hop glides and never bounces.
    static let gridHop = Animation.spring(response: 0.18, dampingFraction: 0.9)
}
#endif
