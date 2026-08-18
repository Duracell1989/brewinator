import Foundation

enum ConfigStoreError: Error, Sendable, Equatable {
    case notFound(path: String)
    case invalid(path: String, reason: String)
}

protocol ConfigStore: Sendable {
    /// Where the config lives — shown by `brewinator config` and in first-run
    /// messages, so the user knows which file to edit by hand.
    var path: String { get }

    func load() throws -> UserConfig
    func save(_ config: UserConfig) throws
}

extension ConfigStore {
    /// First run writes the default rather than dead-ending on a missing
    /// file. Deliberately scoped to `.notFound`: a config that exists but
    /// doesn't parse still throws, because overwriting it would silently
    /// destroy a skip list the user spent time building.
    func loadOrCreate(default defaultConfig: UserConfig) throws -> (config: UserConfig, created: Bool) {
        do {
            return (try load(), false)
        } catch ConfigStoreError.notFound {
            try save(defaultConfig)
            return (defaultConfig, true)
        }
    }
}

final class FileConfigStore: ConfigStore {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/brewinator/config.json")
    }

    private let fileURL: URL

    var path: String { fileURL.path }

    init(fileURL: URL = FileConfigStore.defaultURL) {
        self.fileURL = fileURL
    }

    /// Normalizes every failure mode into `ConfigStoreError` — the caller
    /// (`main.swift`) only catches that type, so a raw `DecodingError` (from
    /// malformed JSON) or file-read error escaping here would crash instead
    /// of showing the friendly "create a config first" message.
    func load() throws -> UserConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ConfigStoreError.notFound(path: fileURL.path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigStoreError.invalid(path: fileURL.path, reason: "\(error)")
        }
        do {
            return try JSONDecoder().decode(UserConfig.self, from: data)
        } catch {
            throw ConfigStoreError.invalid(path: fileURL.path, reason: "\(error)")
        }
    }

    func save(_ config: UserConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
