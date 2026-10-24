#if canImport(AppKit)
import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService`. Meaningful only for the bundled `.app`; the SPM dev
/// executable has no app bundle, so `register()` throws, callers surface that gracefully.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Result<Void, Error> {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
#endif
