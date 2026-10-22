import Foundation

/// A fresh config file path in the temporary directory, for a store under test.
func makeTempConfigURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("macspane-config-\(UUID().uuidString).json")
}
