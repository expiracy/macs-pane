#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The notch a `WindowSnapController` drives while a window is dragged to the top: it widens into a
/// drag target, opens into the picker after a rest, and closes when the drag ends. MacsPane's drag-only
/// notch (`MacsPaneSnapHost`) is the host; the protocol keeps the drag tracker free of its drawing.
protocol WindowSnapHosting: AnyObject {
    /// The picker's state: tiles, highlight and what a release commits.
    var windowSnap: WindowSnapViewModel { get }
    /// The live window roster, most recent first, for the pairing suggestions and the pairing Undo.
    var recents: RecentWindowsService { get }
    /// The picker is open (the drag has rested on the notch).
    var isSnapPickerOpen: Bool { get }
    /// Everything the open picker covers (the notch and both islands) and the widened drag target,
    /// the same numbers the host draws with, so what the pointer hits is what is on screen.
    var snapPickerSize: CGSize { get }
    var windowDragTargetSize: CGSize { get }

    /// Widen the resting notch into a drag target, or put it back.
    func setWindowDragActive(_ active: Bool)
    /// The drag is on the widened target (collapsed), the target lights its "hold" region.
    func setWindowOnTarget(_ onTarget: Bool)
    /// The drag pointer entered or left the notch; a rest at `point` opens the picker.
    func setPointerInside(_ inside: Bool, at point: CGPoint?)
    /// Drop a pending open or close without touching the surface.
    func cancelPendingHoverTransitions()
    /// Close straight from the picker after a release; `undo` (a pairing was tiled) offers an Undo.
    /// `completion` runs once the picker is off screen, the moment to clear the snap state.
    func collapseSnapPicker(undo: (() -> Void)?, completion: @escaping () -> Void)
    /// One of your presets was the release target: apply it, as the menu does.
    func applyPreset(_ id: String)
}
#endif
