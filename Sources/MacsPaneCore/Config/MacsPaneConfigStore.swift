import Foundation

/// Where MacsPane keeps its file, beside (never inside) Notch++'s Application Support folder.
public enum MacsPanePaths {
    public static let folderName = "MacsPane"

    public static func configURL(_ fm: FileManager = .default) throws -> URL {
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                              appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    /// Notch++'s `config.json`, located without creating its folder — MacsPane only ever reads it,
    /// to import layouts and presets.
    public static func notchPlusPlusConfigURL(_ fm: FileManager = .default) -> URL? {
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: false) else { return nil }
        return base.appendingPathComponent("Notch++", isDirectory: true)
            .appendingPathComponent("config.json")
    }
}

/// Loads, persists and publishes `MacsPaneConfig` as pretty-printed JSON. A first run writes `seed()` (Notch++'s layouts and presets when it is installed)
/// or the defaults. A file that will not decode is copied aside before anything can overwrite it, so a
/// bad edit costs the user nothing they cannot get back. Writes are atomic.
public final class MacsPaneConfigStore {
    private let url: URL
    public private(set) var config: MacsPaneConfig
    /// The most recent persistence error; the in-memory config stays usable.
    public private(set) var lastWriteError: Error?
    /// Invoked after any change, so the menu and the settings window can refresh.
    public var onChange: ((MacsPaneConfig) -> Void)?

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public init(url: URL, seed: () -> MacsPaneConfig? = { nil }) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(MacsPaneConfig.self, from: data) {
                config = decoded.migrated()
                if config != decoded { persist() }
            } else {
                config = .default
                Self.setAside(url)
            }
        } else {
            config = seed() ?? .default
            persist()
        }
    }

    /// Mutate the config in place, persist it, and notify observers. A failed write rolls back.
    public func update(_ transform: (inout MacsPaneConfig) -> Void) {
        let previous = config
        transform(&config)
        guard config != previous else { return }
        do {
            try Self.encoder.encode(config).write(to: url, options: [.atomic])
            lastWriteError = nil
            onChange?(config)
        } catch {
            config = previous
            lastWriteError = error
        }
    }

    private func persist() {
        do {
            try Self.encoder.encode(config).write(to: url, options: [.atomic])
        } catch {
            lastWriteError = error
        }
    }

    /// Keep an undecodable file as `config.unreadable.json` (replacing an older one).
    private static func setAside(_ url: URL) {
        let fm = FileManager.default
        let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
        try? fm.removeItem(at: aside)
        try? fm.copyItem(at: url, to: aside)
    }
}
