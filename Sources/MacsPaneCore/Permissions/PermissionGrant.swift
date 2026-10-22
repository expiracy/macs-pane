import Foundation

/// The system permissions MacsPane asks for, and what granting one takes. Today that is one:
/// Accessibility, which moving and resizing other apps' windows needs. One description per permission
/// so the menu's warning, the setup step and the grant card all say the same thing.
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

    /// Whether the pane's list takes an app dragged into it (Accessibility's does: it has + and −).
    public var acceptsAppDrop: Bool {
        switch self {
        case .accessibility: return true
        }
    }

    /// The service name `tccutil` knows this permission by, for replacing a stale entry left in
    /// System Settings by an earlier copy of the app.
    public var tccService: String {
        switch self {
        case .accessibility: return "Accessibility"
        }
    }

    /// The three steps the helper walks through. The app has already done the first one, so the
    /// card reports it rather than asking for it, and the last step says not to look for a Done
    /// button — the card watches for the grant itself.
    public func steps(appName: String) -> [String] {
        ["macOS opened System Settings on the right list.",
         "Turn \(appName) on in that list.",
         "Come back. This card notices by itself."]
    }

    /// What to do when the app isn't in the list yet.
    public func missingFromListHint(appName: String) -> String {
        acceptsAppDrop
            ? "Not there? Drag the icon in, or click + in System Settings and pick \(appName)."
            : "Not there? \(appName) appears once it has asked — use the feature once, then come back."
    }

    /// The line that explains a switch that is already on but not working.
    public func staleEntryHint(appName: String) -> String {
        "Already on in that list? That entry belongs to an earlier copy of \(appName). "
            + "Start over to replace it."
    }
}
