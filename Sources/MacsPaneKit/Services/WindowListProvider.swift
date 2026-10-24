#if canImport(AppKit)
import AppKit
import CoreGraphics
import MacsPaneCore

/// Maps the window server's roster into pure `ProcessWindowInfo` values for the picker.
/// `CGWindowListCopyWindowInfo` is NOT deprecated (unlike `CGWindowListCreateImage`) and works
/// without Screen Recording, except `kCGWindowName`, which the server omits until that grant
/// exists; the peek renders missing titles as "Window N".
struct WindowListProvider {
    /// Front-to-back roster of every window (all Spaces, minimized included). Cheap; main thread.
    func snapshot() -> [ProcessWindowInfo] {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? Int,
                  let pid = dict[kCGWindowOwnerPID as String] as? Int,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let title = (dict[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return ProcessWindowInfo(id: UInt32(id),
                                     ownerPid: Int32(pid),
                                     title: title,
                                     frame: bounds,
                                     isOnScreen: dict[kCGWindowIsOnscreen as String] as? Bool ?? false,
                                     layer: layer,
                                     alpha: dict[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
#endif
