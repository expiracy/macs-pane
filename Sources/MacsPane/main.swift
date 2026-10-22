import MacsPaneKit

// MacsPane's entry point. All boot logic lives in `MacsPaneKit.MacsPaneApp`, shared with the bundled
// app (App/main.swift) so they can't drift.
//   swift run macspane                 Launch (stays running in the menu bar).
//   swift run macspane --smoke-test    Boot, then quit after ~1.5 s.
MacsPaneApp.run()
