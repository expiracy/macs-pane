#if canImport(AppKit)
import AppKit
import MacsPaneCore

extension NSScreen {
    /// Height of the menu bar on this screen.
    var notchMenubarHeight: CGFloat { frame.maxY - visibleFrame.maxY }

    /// Whether this screen has a camera notch (both auxiliary top areas are present).
    var hasNotch: Bool { auxiliaryTopLeftArea != nil && auxiliaryTopRightArea != nil }

    /// Pure geometry derived from this screen's real measurements. On a screen without a physical
    /// notch the hover-trigger footprint falls back to the system's real notch size (if a notched
    /// display is attached) or a standard one, so the trigger stays the same everywhere.
    var notchGeometry: NotchGeometry {
        NotchGeometry(screenFrame: frame,
                      safeAreaTop: safeAreaInsets.top,
                      leftAuxWidth: auxiliaryTopLeftArea?.width,
                      rightAuxWidth: auxiliaryTopRightArea?.width,
                      menubarHeight: notchMenubarHeight,
                      fallbackNotchSize: NSScreen.referenceNotchSize)
    }

    /// The built-in display that has a real notch, if any.
    static var builtInNotched: NSScreen? { screens.first { $0.hasNotch } }

    /// The primary / menu-bar display — the screen at the global origin (the one whose menu bar the
    /// system shows). Changing the main display in System Settings makes a different screen primary,
    /// which fires `didChangeScreenParametersNotification` so the panel follows.
    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    /// The screen the notch panel hosts on: we follow the active (primary/menu-bar) display, so the
    /// panel sits on the notched laptop when that's primary and drops from the top-centre of an
    /// external monitor when that's made primary (including clamshell, where it's the only screen).
    static var notchHost: NSScreen? { primary ?? main }

    /// The screen under a global (bottom-left) point — the pointer's screen, for anything that should
    /// happen "where I am" rather than on the primary display.
    static func containing(_ point: CGPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    /// The `CGDirectDisplayID` behind this screen — stable across a reconfiguration, unlike the
    /// `NSScreen` instance, so it is what "the same display" is matched on.
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The notch footprint to mirror on a screen that has no physical notch: the real built-in
    /// notch's collapsed size if a notched display is present in the system, otherwise a standard
    /// notch size. Keeps the hover trigger identical to the laptop's when both are attached.
    static var referenceNotchSize: CGSize {
        guard let notched = builtInNotched,
              let left = notched.auxiliaryTopLeftArea?.width,
              let right = notched.auxiliaryTopRightArea?.width, notched.safeAreaInsets.top > 0 else {
            return NotchGeometry.standardNotchSize
        }
        return CGSize(width: max(0, notched.frame.width - left - right),
                      height: notched.safeAreaInsets.top)
    }
}
#endif
