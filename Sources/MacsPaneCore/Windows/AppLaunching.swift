import Foundation

/// Launches an installed app by bundle id without activating it, reporting the new process id (or
/// nil if the app isn't installed / failed to launch). The port Smart Windows' launch-on-apply
/// calls instead of `NSWorkspace`; live adapter = `WorkspaceAppLauncher`, tests use a fake pid.
public protocol AppLaunching {
    func launchApp(bundleID: String, completion: @escaping (pid_t?) -> Void)
}
