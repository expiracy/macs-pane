import Foundation

/// The system permissions MacsPane asks for, and what granting one takes. Today that is one:
/// Accessibility, which moving and resizing other apps' windows needs. One description per permission
/// so the menu's warning, the setup step and the permission dropdown all say the same thing.
public enum PermissionGrant: String, CaseIterable, Codable, Sendable, Identifiable {
    case accessibility

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        }
    }

    /// What the permission is for, as a phrase that reads after "needs Accessibility for …".
    public var unlocks: String {
        switch self {
        case .accessibility: return "moving and snapping your windows"
        }
    }

    /// The same phrase as its own sentence, for the granted state.
    public var unlocksSentence: String {
        guard let first = unlocks.first else { return unlocks }
        return first.uppercased() + unlocks.dropFirst()
    }

    /// The pane's key in the Privacy & Security deep link.
    public var paneKey: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        }
    }

    public var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(paneKey)")
    }

    /// The service name `tccutil` knows this permission by, for replacing a stale entry left in
    /// System Settings by an earlier copy of the app.
    public var tccService: String {
        switch self {
        case .accessibility: return "Accessibility"
        }
    }

    /// The line that explains a switch that is already on but not working.
    public func staleEntryHint(appName: String) -> String {
        "Switched on but still not working? That entry belongs to an earlier copy of \(appName). "
            + "Start over replaces it."
    }
}
