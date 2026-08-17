import Foundation
import Testing

@testable import Brewinator

@Suite("FileConfigStore")
struct ConfigStoreTests {
    @Test("missing config file throws notFound")
    func missingFileThrowsNotFound() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        let store = FileConfigStore(fileURL: fileURL)

        #expect(throws: ConfigStoreError.notFound(path: fileURL.path)) {
            try store.load()
        }
    }

    @Test("malformed JSON throws ConfigStoreError.invalid, not a raw DecodingError — main.swift only catches ConfigStoreError")
    func malformedJSONThrowsInvalidConfigStoreError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: fileURL)
        let store = FileConfigStore(fileURL: fileURL)

        do {
            _ = try store.load()
            Issue.record("expected load() to throw")
        } catch let error as ConfigStoreError {
            guard case .invalid(let path, _) = error else {
                Issue.record("expected .invalid, got \(error)")
                return
            }
            #expect(path == fileURL.path)
        } catch {
            Issue.record("expected a ConfigStoreError, got a raw \(type(of: error)): \(error)")
        }
    }

    @Test("save then load round-trips exactly")
    func saveThenLoadRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fileURL = directory.appendingPathComponent("config.json")
        let store = FileConfigStore(fileURL: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: "/tmp/notes", skipList: ["discord", "lib*"], notify: true)
        try store.save(config)

        #expect(try store.load() == config)
    }
}
