#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The app-visuals cache behind the Windows page and preset apply: an app's display name, icon and
/// bundle id for the live window roster, keyed by pid. Name and bundle id are in-memory reads that
/// resolve on the spot; an icon is fetched the first time one is asked for, since it is not a cheap
/// read (a preset's apply used to spend its first frames on icons it never drew).
///
/// Main-thread only, like the `SmartWindowsViewModel` that owns it: every entry point is a pointer gesture
/// or a main-queue completion.
final class SmartWindowsAppVisuals {
    /// pid → display name.
    private var nameByPid: [Int32: String] = [:]
    /// pid → icon, filled on first read.
    private var iconByPid: [Int32: NSImage] = [:]
    /// pid → bundle id, cached alongside `byPid`, resolves a layout's `.app` bindings on apply.
    private var bundleByPid: [Int32: String] = [:]

    // MARK: - Read

    func appName(for pid: Int32) -> String { nameByPid[pid] ?? "App" }

    func icon(for pid: Int32) -> NSImage? {
        if let icon = iconByPid[pid] { return icon }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        iconByPid[pid] = icon
        return icon
    }
    func bundleID(for pid: Int32) -> String? { bundleByPid[pid] }

    // MARK: - Resolve

    /// Cache a window roster's app names and bundle ids, cheap in-memory reads for a running app.
    func cache(for windows: [ProcessWindowInfo]) {
        for pid in Set(windows.map(\.ownerPid)) where nameByPid[pid] == nil {
            let app = NSRunningApplication(processIdentifier: pid)
            nameByPid[pid] = app?.localizedName ?? "App"
            if let bundle = app?.bundleIdentifier { bundleByPid[pid] = bundle }
        }
    }
}
#endif
