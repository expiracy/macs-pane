#if canImport(AppKit)
import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the notch UI. Floats above the menu bar and rides
/// across all Spaces. Mirrors DynamicNotchKit's proven configuration: `.screenSaver` level, clear
/// background, no shadow. `canBecomeKey` is true so the expanded panel can take clicks/drags
/// without the app leaving `.accessory` (the `.nonactivatingPanel` style keeps the app in the
/// background).
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, but NOT as high as `.screenSaver`: windows at screen-saver level
        // don't reliably receive drag-and-drop (the likely reason drops never fired). boring.notch
        // uses this exact level for its drag-onto-the-notch shelf.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true     // so the local mouse-moved monitor fires over the panel
        // Plain clicks must NEVER pull keyboard focus away from the user's frontmost app, every
        // notch control is pointer-driven (first-mouse Buttons, gestures). The panel takes key
        // only when explicitly asked, i.e. Quick Look's makeKeyAndOrderFront.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// An `NSHostingView` that accepts the first mouse-click even when its window isn't key. The notch is a
/// non-activating panel, so when you click it from another app AppKit would otherwise swallow the first
/// click just to make the panel key; this delivers that click straight to the SwiftUI control instead,
/// so a single click on a Shelf button/cell works without a throwaway "wake-up" click first.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
