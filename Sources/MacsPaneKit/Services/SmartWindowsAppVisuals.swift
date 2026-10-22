#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The app-visuals cache behind the Windows page and preset apply: an app's display name, icon and
/// bundle id for the live window roster, keyed by pid. An `NSRunningApplication`'s name, icon and
/// bundle id are in-memory reads, so they resolve on the spot.
///
/// Main-thread only, like the `SmartWindowsViewModel` that owns it: every entry point is a pointer gesture
/// or a main-queue completion.
final class SmartWindowsAppVisuals {
    /// One app's cached display values.
    struct AppVisual {
        let name: String
        var icon: NSImage?
    }

    /// pid → display values.
    private var byPid: [Int32: AppVisual] = [:]
    /// pid → bundle id, cached alongside `byPid` — resolves a layout's `.app` bindings on apply.
    private var bundleByPid: [Int32: String] = [:]

    // MARK: - Read

    func appName(for pid: Int32) -> String { byPid[pid]?.name ?? "App" }
    func icon(for pid: Int32) -> NSImage? { byPid[pid]?.icon }
    func bundleID(for pid: Int32) -> String? { bundleByPid[pid] }

    // MARK: - Resolve

    /// Cache a window roster's app visuals — the name, bundle id and icon, all cheap in-memory reads
    /// for a running app, so a row shows its icon the instant the roster is read.
    func cache(for windows: [ProcessWindowInfo]) {
        for pid in Set(windows.map(\.ownerPid)) where byPid[pid] == nil {
            let app = NSRunningApplication(processIdentifier: pid)
            byPid[pid] = AppVisual(name: app?.localizedName ?? "App", icon: app?.icon)
            if let bundle = app?.bundleIdentifier { bundleByPid[pid] = bundle }
        }
    }
}
#endif
