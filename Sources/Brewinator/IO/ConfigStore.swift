import Foundation

enum ConfigStoreError: Error, Sendable, Equatable {
    case notFound(path: String)
    case invalid(path: String, reason: String)
    case notWritable(path: String, reason: String)
}

/// ArgumentParser prints a thrown error straight to the terminal, so an
/// unconformed enum would surface as `Error: notFound(path: "...")`.
extension ConfigStoreError: CustomStringConvertible, LocalizedError {
    var description: String {
        switch self {
        case .notFound(let path):
            return "No config at \(path)."
        case .invalid(let path, let reason):
            return "Config at \(path) could not be read: \(reason)"
        case .notWritable(let path, let reason):
            return "Could not write a config to \(path): \(reason)"
        }
    }

    var errorDescription: String? { description }
}

protocol ConfigStore: Sendable {
    /// Where the config lives - shown by `brewinator config` and in first-run
    /// messages, so the user knows which file to edit by hand.
    var path: String { get }

    func load() throws -> UserConfig
    func save(_ config: UserConfig) throws
}

extension ConfigStore {
    /// First run writes the default. Scoped to `.notFound`: a config that exists
    /// but doesn't parse still throws, since overwriting it would destroy the
    /// user's skip list.
    ///
    /// The `save` failure is wrapped, not rethrown - `createDirectory` and
    /// `Data.write` throw `CocoaError`, which escapes a `ConfigStoreError`-only
    /// catch and traps at top level instead of printing.
    func loadOrCreate(default defaultConfig: UserConfig) throws -> (config: UserConfig, created: Bool) {
        do {
            return (try load(), false)
        } catch ConfigStoreError.notFound {
            do {
                try save(defaultConfig)
            } catch let error as ConfigStoreError {
                throw error
            } catch {
                throw ConfigStoreError.notWritable(path: path, reason: "\(error)")
            }
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

    /// Normalizes every failure into `ConfigStoreError` - `main.swift` catches
    /// only that type, so a raw `DecodingError` or read error would crash rather
    /// than print.
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
        // `withoutEscapingSlashes`: this file is hand-edited, and the default
        // encoder writes every path as "\/Volumes\/...".
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
