#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// The live `AppLaunching` adapter: resolve the bundle id, launch WITHOUT activating (the snap
/// happens behind the notch — focus must not jump), hand back the pid on main.
struct WorkspaceAppLauncher: AppLaunching {
    func launchApp(bundleID: String, completion: @escaping (pid_t?) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            completion(nil); return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { app, _ in
            DispatchQueue.main.async { completion(app?.processIdentifier) }
        }
    }
}

/// Resolves app icons for bundle ids — AppKit-layer by nature (`NSImage` must not cross a Core
/// port), but out of ViewModel files so they stay free of `NSWorkspace`.
enum AppIconResolver {
    static func icon(bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
#endif
