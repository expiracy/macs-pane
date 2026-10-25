#if canImport(AppKit)
import AppKit
import MacsPaneCore

/// Reads the Applications folders for app bundles, what a preset box can name while the app isn't
/// running. One level deep plus the Utilities folders, the places apps actually live.
struct LiveInstalledApps: InstalledAppsProviding {
    private static let folders: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/Applications/Utilities", "/System/Applications",
                "/System/Applications/Utilities"].map { URL(fileURLWithPath: $0) }
            + [home.appendingPathComponent("Applications")]
    }()

    func installedApps() -> [InstalledApp] {
        let fileManager = FileManager.default
        return Self.folders.flatMap { folder -> [InstalledApp] in
            let urls = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
            return urls.filter { $0.pathExtension == "app" }.compactMap { url in
                guard let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
                let name = (fileManager.displayName(atPath: url.path) as NSString).deletingPathExtension
                return InstalledApp(bundleID: bundleID, name: name, path: url.path)
            }
        }
    }
}

/// App names and icons by bundle id, for preset boxes and their app menus. Icons are
/// read once and kept. Main-thread use only, like the views that ask.
final class AppIdentityCache {
    static let shared = AppIdentityCache()
    private var icons: [String: NSImage] = [:]
    private var names: [String: String] = [:]

    func icon(forBundleID bundleID: String) -> NSImage? {
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    func name(forBundleID bundleID: String) -> String {
        if let name = names[bundleID] { return name }
        let name: String
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
        } else {
            name = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        }
        names[bundleID] = name
        return name
    }
}
#endif
