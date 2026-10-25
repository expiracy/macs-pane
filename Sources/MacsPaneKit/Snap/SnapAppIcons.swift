#if canImport(AppKit)
import AppKit

/// App icons for the picker's tiles, each drawn once into a small bitmap and kept while MacsPane runs.
/// The first time a process draws an app's icon the system decodes it for that size, 5–17ms an icon,
/// and the picker used to pay that for every tile's icons in the first frames of its first open: the
/// lag on the first expand. Running apps are drawn in the background at launch; any other app is drawn
/// the first time it is asked for (a preset loading, a drag starting), never while the notch animates.
enum SnapAppIcons {
    /// Big enough for the largest box's icon (70% of a full tile's height) at 2x.
    static let points: CGFloat = 36

    private static let lock = NSLock()
    nonisolated(unsafe) private static var drawn: [String: NSImage] = [:]
    /// bundle id → its app's icon, or nil when no app has that id; kept so a list redrawn every second
    /// (the menu) doesn't ask Launch Services again.
    nonisolated(unsafe) private static var byBundleID: [String: NSImage?] = [:]

    /// The icon of the app at `url`, ready to draw.
    static func icon(forAppAt url: URL) -> NSImage {
        let path = url.path
        if let hit = lock.withLock({ drawn[path] }) { return hit }
        let image = rasterized(NSWorkspace.shared.icon(forFile: path))
        lock.withLock { drawn[path] = image }
        return image
    }

    /// The icon of the app with `bundleID`, or nil when none is installed.
    static func icon(bundleID: String) -> NSImage? {
        if let hit = lock.withLock({ byBundleID[bundleID] }) { return hit }
        let image = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map(icon(forAppAt:))
        lock.withLock { byBundleID[bundleID] = image }
        return image
    }

    /// Draw the running apps' icons now, off the main thread, so the first drag finds them ready.
    static func warmRunningApps() {
        let urls = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.bundleURL)
        DispatchQueue.global(qos: .utility).async {
            for url in urls { _ = icon(forAppAt: url) }
        }
    }

    private static func rasterized(_ icon: NSImage) -> NSImage {
        let pixels = Int(points * 2)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return icon }
        // Sized in points before the context is made, so the context draws at 2x across all of it.
        rep.size = NSSize(width: points, height: points)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        icon.draw(in: NSRect(x: 0, y: 0, width: points, height: points))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
#endif
