import Foundation
import Testing

@testable import Brewinator

private struct FakeBrewClient: BrewClient {
    let result: OutdatedResult
    var formulaURLInfo: [String: PackageURLInfo] = [:]
    var caskURLInfo: [String: PackageURLInfo] = [:]

    func update() async throws {}
    func outdated() async throws -> OutdatedResult { result }
    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] { formulaURLInfo }
    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] { caskURLInfo }
}

/// Echoes the package it was handed back into the note body — lets a test
/// assert what `BrewNotesSync` actually passed to the resolver (e.g. the
/// merged `stableURL`) without needing shared mutable state across an async
/// boundary.
private struct EchoingNoteSource: NoteSource {
    func canHandle(_ package: OutdatedPackageInfo) -> Bool { true }
    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        .success(ReleaseNotes(markdown: "stableURL=\(package.stableURL ?? "nil")\n"))
    }
}

private struct FailingBrewClient: BrewClient {
    func update() async throws {}
    func outdated() async throws -> OutdatedResult { throw BrewClientError.invalidOutdatedOutput }
    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] { [:] }
    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] { [:] }
}

/// Delegates to a real `FileArchiveStore` but fails `write()` for one named
/// package — lets a test reproduce "one write fails, the rest of the batch
/// must still succeed" without touching the filesystem's actual failure
/// modes (disk full, permissions).
private struct WriteFailingArchiveStore: ArchiveStore {
    struct WriteError: Error {}

    let inner: FileArchiveStore
    let failingName: String

    func existingFile(for package: OutdatedPackageInfo) -> Bool { inner.existingFile(for: package) }

    func write(_ notes: ReleaseNotes, for package: OutdatedPackageInfo) throws {
        guard package.name != failingName else { throw WriteError() }
        try inner.write(notes, for: package)
    }

    func prune(keeping outdatedIdentities: Set<ArchivePackageIdentity>, skipList: [String]) throws -> [URL] {
        try inner.prune(keeping: outdatedIdentities, skipList: skipList)
    }
}

private struct FixtureNotFound: Error {}

private func loadFixture() throws -> OutdatedResult {
    guard let url = Bundle.module.url(forResource: "brew-outdated-sample", withExtension: "json", subdirectory: "Fixtures") else {
        throw FixtureNotFound()
    }
    let data = try Data(contentsOf: url)
    return try ProcessBrewClient.parseOutdated(data)
}

/// Parity-scoped suite (Phase 2): no real forge/vendor sources exist yet, so
/// every package resolves to the same placeholder — this proves the
/// prune/keep/write *decisions* are correct from a given `brew outdated`
/// snapshot, independent of note content.
@Suite("BrewNotesSync")
struct BrewNotesSyncTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func seed(_ directory: URL, filename: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("pre-existing".utf8).write(to: directory.appendingPathComponent(filename))
    }

    @Test("prunes upgraded-away and skip-listed files, writes new items for the rest, leaves existing files untouched")
    func fullSyncDecisions() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Pre-seed archive state as if from a prior sync:
        try seed(directory, filename: "ffmpeg (formula) - 8.1.2.md")  // still outdated, already archived -> kept, no new item
        try seed(directory, filename: "discord (formula) - 1.1.0.md")  // still outdated but skip-listed -> pruned
        try seed(directory, filename: "old-tool (formula) - 0.5.0.md")  // no longer outdated (upgraded) -> pruned

        let config = UserConfig(archiveDirectory: directory.path, skipList: ["discord"], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: try loadFixture()),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: []),
            config: config
        )

        let result = try await sync.run()

        #expect(result.trashedFiles.count == 2)
        #expect(Set(result.newItems.map(\.name)) == ["node", "obsidian"])

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(remaining == ["ffmpeg (formula) - 8.1.2.md", "node (formula) - 23.0.0.md", "obsidian (cask) - 1.1.0.md"])
    }

    @Test(
        "reports every outdated package, skip-listed ones included — the printed listing replaces `brew outdated --verbose`, which ignored the skip list too"
    )
    func reportsUnfilteredOutdatedSet() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: directory.path, skipList: ["discord"], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: try loadFixture()),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: []),
            config: config
        )

        let result = try await sync.run()

        #expect(Set(result.outdated.map(\.name)) == ["discord", "ffmpeg", "node", "obsidian"])
    }

    @Test("a failed brew outdated call aborts the sync entirely — no prune, no fetch")
    func failedOutdatedAbortsSync() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seed(directory, filename: "old-tool (formula) - 0.5.0.md")

        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let sync = BrewNotesSync(
            brewClient: FailingBrewClient(),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: []),
            config: config
        )

        await #expect(throws: BrewClientError.invalidOutdatedOutput) {
            try await sync.run()
        }

        // Archive must be untouched — the pre-seeded stale file survives.
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remaining == ["old-tool (formula) - 0.5.0.md"])
    }

    @Test("writes the '## name (installed → current)' header before the source's body — a Phase 2 gap this phase closes")
    func writesHeaderBeforeBody() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outdated = OutdatedResult(
            formulae: [OutdatedPackageInfo(name: "node", installedVersion: "22.0.0_1", currentVersion: "23.0.0", kind: .formula)],
            casks: []
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: outdated),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        _ = try await sync.run()

        let content = try String(contentsOf: directory.appendingPathComponent("node (formula) - 23.0.0.md"), encoding: .utf8)
        // Header uses the *raw* versions (installed keeps its "_1" revision
        // suffix), not the cleaned ones used for the filename.
        #expect(content.hasPrefix("## node (22.0.0_1 → 23.0.0)\n\n"))
        #expect(content.contains("stableURL=nil"))
    }

    @Test("merges brew info's stableURL/homepage into each package before resolving")
    func mergesBrewInfoIntoPackages() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outdated = OutdatedResult(
            formulae: [OutdatedPackageInfo(name: "jq", installedVersion: "1.8.1", currentVersion: "1.8.2", kind: .formula)],
            casks: []
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let brewClient = FakeBrewClient(
            result: outdated,
            formulaURLInfo: ["jq": PackageURLInfo(stableURL: "https://github.com/jqlang/jq/releases", homepage: "https://jqlang.github.io/jq/")]
        )
        let sync = BrewNotesSync(
            brewClient: brewClient,
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        _ = try await sync.run()

        let content = try String(contentsOf: directory.appendingPathComponent("jq (formula) - 1.8.2.md"), encoding: .utf8)
        #expect(content.contains("stableURL=https://github.com/jqlang/jq/releases"))
    }

    @Test(
        "a write failure for one package doesn't discard the rest of the batch — newItems/trashedFiles for other packages still come back"
    )
    func writeFailureForOnePackageDoesNotDiscardBatch() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seed(directory, filename: "old-tool (formula) - 0.5.0.md")  // no longer outdated -> should still be pruned

        let outdated = OutdatedResult(
            formulae: [
                OutdatedPackageInfo(name: "a", installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .formula),
                OutdatedPackageInfo(name: "b", installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .formula),
            ],
            casks: []
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let logger = RecordingLogger()
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: outdated),
            archiveStore: WriteFailingArchiveStore(inner: FileArchiveStore(directory: directory), failingName: "a"),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config,
            logger: logger
        )

        let result = try await sync.run()

        #expect(result.newItems.map(\.name) == ["b"])
        #expect(result.trashedFiles.count == 1)
        #expect(logger.messages.contains { $0.contains("a") })
    }

    @Test("a resolver fetch failure is logged instead of vanishing silently")
    func fetchFailureIsLogged() async throws {
        struct FailingNoteSource: NoteSource {
            func canHandle(_ package: OutdatedPackageInfo) -> Bool { true }
            func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
                .failure(.transient(reason: "network blip"))
            }
        }

        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outdated = OutdatedResult(
            formulae: [OutdatedPackageInfo(name: "node", installedVersion: "22.0.0", currentVersion: "23.0.0", kind: .formula)],
            casks: []
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let logger = RecordingLogger()
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: outdated),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [FailingNoteSource()]),
            config: config,
            logger: logger
        )

        let result = try await sync.run()

        #expect(result.newItems.isEmpty)
        #expect(logger.messages.contains { $0.contains("node") && $0.contains("network blip") })
    }

    @Test("a failing brew info call doesn't abort the sync — it just costs forge-repo resolution for those packages")
    func failingBrewInfoDoesNotAbortSync() async throws {
        struct InfoFailingBrewClient: BrewClient {
            let result: OutdatedResult
            func update() async throws {}
            func outdated() async throws -> OutdatedResult { result }
            func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] { throw BrewClientError.invalidOutdatedOutput }
            func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] { [:] }
        }

        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outdated = OutdatedResult(
            formulae: [OutdatedPackageInfo(name: "node", installedVersion: "22.0.0", currentVersion: "23.0.0", kind: .formula)],
            casks: []
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let sync = BrewNotesSync(
            brewClient: InfoFailingBrewClient(result: outdated),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        let result = try await sync.run()
        #expect(result.newItems.map(\.name) == ["node"])
    }
}
