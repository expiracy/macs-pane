import Foundation

/// An application installed on this Mac, something a preset box can name even while it isn't running.
public struct InstalledApp: Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let path: String
    public var id: String { bundleID }

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Port for the installed-apps scan; the live adapter reads the Applications folders.
public protocol InstalledAppsProviding: Sendable {
    func installedApps() -> [InstalledApp]
}

/// Which installed apps a preset box offers under the running ones.
public enum InstalledAppCatalog {
    /// Apps not already listed as running, one per bundle id, by name.
    public static func notRunning(_ apps: [InstalledApp], running: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps
            .filter { !running.contains($0.bundleID) && seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
