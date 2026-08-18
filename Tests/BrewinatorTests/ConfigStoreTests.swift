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

@Suite("ConfigStore.loadOrCreate")
struct ConfigStoreLoadOrCreateTests {
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
    }

    @Test("a missing config is created from the default instead of failing the first run")
    func missingFileIsCreated() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileConfigStore(fileURL: fileURL)

        let loaded = try store.loadOrCreate(default: UserConfig.default)

        #expect(loaded.created)
        #expect(loaded.config == UserConfig.default)
        #expect(try store.load() == UserConfig.default)
    }

    @Test("an existing config is returned untouched — never overwritten by the default")
    func existingFileIsKept() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = FileConfigStore(fileURL: fileURL)
        let existing = UserConfig(archiveDirectory: "/mine", skipList: ["spotify"], notify: true)
        try store.save(existing)

        let loaded = try store.loadOrCreate(default: UserConfig.default)

        #expect(!loaded.created)
        #expect(loaded.config == existing)
    }

    @Test("a malformed config throws instead of being silently replaced — a typo must never cost the user their skip list")
    func malformedFileIsNotClobbered() throws {
        let fileURL = tempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ oops".utf8).write(to: fileURL)
        let store = FileConfigStore(fileURL: fileURL)

        #expect(throws: (any Error).self) {
            _ = try store.loadOrCreate(default: UserConfig.default)
        }
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "{ oops")
    }

    @Test("the shipped default archives to a visible folder in the user's home, not a hidden support directory")
    func defaultArchivesUnderHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        #expect(UserConfig.default.archiveDirectory == "\(home)/Brew Release Notes")
        #expect(UserConfig.default.skipList.isEmpty)
        #expect(!UserConfig.default.notify)
    }
}
