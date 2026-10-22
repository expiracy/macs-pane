#if canImport(AppKit)
import AppKit
import ApplicationServices
import MacsPaneCore

extension PermissionGrantPresenter {
    /// Accessibility — the pane you drag MacsPane into. The system prompt is shown first (it is the
    /// one click that can finish the job), then the helper walks the manual route.
    public func requestAccessibility(onGranted: (() -> Void)? = nil) {
        present(.accessibility, isGranted: { AXIsProcessTrusted() },
                prompt: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) },
                onGranted: onGranted)
    }
}
#endif
