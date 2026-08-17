import Foundation

enum ConfigStoreError: Error, Sendable, Equatable {
    case notFound(path: String)
    case invalid(path: String, reason: String)
}

protocol ConfigStore: Sendable {
    func load() throws -> UserConfig
    func save(_ config: UserConfig) throws
}

final class FileConfigStore: ConfigStore {
    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/brewinator/config.json")
    }

    private let fileURL: URL

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
