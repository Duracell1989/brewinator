import Foundation

@testable import Brewinator

/// In-memory `ConfigStore` for exercising `ConfigEditor` without touching the
/// filesystem. `nonisolated(unsafe)` mirrors the other test doubles: the
/// editor is synchronous and single-threaded, so no locking is warranted.
final class InMemoryConfigStore: ConfigStore, @unchecked Sendable {
    let path: String
    private(set) var saveCount = 0
    private var stored: UserConfig?

    /// Injected to simulate an unwritable `~/.config` (permission denied, read-only
    /// home, disk full). Deliberately a raw `CocoaError` rather than a
    /// `ConfigStoreError`: that is exactly what `FileManager`/`Data.write` throw,
    /// and the point of the test is that such an error never escapes untyped.
    var saveError: Error?

    init(path: String = "/tmp/brewinator-test/config.json", config: UserConfig? = nil) {
        self.path = path
        self.stored = config
    }

    func load() throws -> UserConfig {
        guard let stored else { throw ConfigStoreError.notFound(path: path) }
        return stored
    }

    func save(_ config: UserConfig) throws {
        if let saveError { throw saveError }
        stored = config
        saveCount += 1
    }
}
