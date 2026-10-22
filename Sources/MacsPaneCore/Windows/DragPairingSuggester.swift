import CoreGraphics

/// One suggested tiling offered while a window is dragged at the notch: the dragged window paired with
/// one (or two) most-recently-used windows, pre-arranged. Releasing the drag on it places every window
/// at once. The dragged window always takes the first slot (left / big), matching the picker glyph.
public struct DragPairing: Equatable, Sendable {
    /// Every window to move and where, in slot order (slot 0 = the dragged window). Hand straight to a
    /// `WindowArranging`.
    public let placements: [WindowTilePlacement]

    public init(placements: [WindowTilePlacement]) {
        self.placements = placements
    }
}

/// Builds the drag-to-notch pairing suggestions from the window being dragged and the live MRU roster —
/// pure so the suggestion logic is unit-tested without the window server (the AppKit layer resolves app
/// icons for display separately). Reuses `SmartWindowsLayout` for the frames, so a pairing tiles exactly
/// as the equivalent Smart Windows auto-tile would.
public enum DragPairingSuggester {
    /// Suggestions for `dragged`, most-useful first, given the recent windows (MRU order; may include the
    /// dragged window — it's filtered out). Returns:
    ///  - the dragged window + the single most-recent other window → side-by-side halves, whenever there
    ///    is at least one other window;
    ///  - additionally the dragged window + the two most-recent others → big-left + stacked right, only
    ///    when there are at least two others to fill it.
    /// Empty when nothing else is open — the picker then shows its zone tiles alone.
    public static func suggestions(dragged: ProcessWindowInfo,
                                   recents: [ProcessWindowInfo],
                                   visibleFrame: CGRect) -> [DragPairing] {
        let partners = recents.filter { $0.id != dragged.id }
        guard let first = partners.first else { return [] }

        var result = [pairing([dragged, first], in: visibleFrame)]
        if partners.count >= 2 {
            result.append(pairing([dragged, first, partners[1]], in: visibleFrame))
        }
        return result
    }

    private static func pairing(_ windows: [ProcessWindowInfo], in visibleFrame: CGRect) -> DragPairing {
        DragPairing(placements: SmartWindowsLayout.placements(for: windows, in: visibleFrame))
    }
}
