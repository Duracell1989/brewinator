import Foundation
import Testing

@testable import Brewinator

/// Delegates to a real `FileArchiveStore` but throws from `writeSummary`, to
/// prove a failed summary cannot cost the notes themselves.
private struct SummaryFailingArchiveStore: ArchiveStore {
    struct SummaryError: Error {}

    let inner: FileArchiveStore

    func existingFile(for package: OutdatedPackageInfo) -> Bool { inner.existingFile(for: package) }
    func write(_ notes: ReleaseNotes, for package: OutdatedPackageInfo) throws { try inner.write(notes, for: package) }

    func prune(keeping outdatedIdentities: Set<ArchivePackageIdentity>, skippedBy skipped: SkipMatcher) throws -> [URL] {
        try inner.prune(keeping: outdatedIdentities, skippedBy: skipped)
    }

    func writeSummary(_ markdown: String?) throws { throw SummaryError() }
}

/// The `_Skipped - no release notes.md` file as the sync produces it. Split from
/// `BrewNotesSyncTests` to keep that file under SwiftLint's length limit.
@Suite("BrewNotesSync — skipped-packages summary")
struct BrewNotesSyncSummaryTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func seed(_ directory: URL, filename: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("pre-existing".utf8).write(to: directory.appendingPathComponent(filename))
    }

    @Test("writes one summary file listing the outdated packages that are skipped, so a missing note is not mistaken for a miss")
    func writesNoNotesSummary() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: directory.path, skipList: ["ffmpeg"], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: try loadFixture()),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: []),
            config: config
        )

        let result = try await sync.run()

        let summary = try String(contentsOf: directory.appendingPathComponent(NoNotesSummary.filename), encoding: .utf8)
        #expect(summary.contains("- discord (formula)"))
        #expect(summary.contains("- ffmpeg (formula)"))
        #expect(summary.contains("on your skip list"))
        #expect(!summary.contains("- node (formula)"))
        #expect(!result.newItems.map(\.name).contains("discord"))
    }

    @Test("a failing summary write costs only the summary - notes are still written")
    func failedSummaryDoesNotStopNotes() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: try loadFixture()),
            archiveStore: SummaryFailingArchiveStore(inner: FileArchiveStore(directory: directory)),
            resolver: Resolver(sources: []),
            config: UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        )

        let result = try await sync.run()

        #expect(Set(result.newItems.map(\.name)) == ["node", "ffmpeg", "obsidian"])
    }

    @Test("removes the summary once nothing outdated is skipped any more")
    func removesStaleSummary() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try seed(directory, filename: NoNotesSummary.filename)

        let node = OutdatedPackageInfo(name: "node", installedVersion: "22.0.0", currentVersion: "23.0.0", kind: .formula)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: OutdatedResult(formulae: [node], casks: [])),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: []),
            config: UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        )

        _ = try await sync.run()

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(remaining == ["node (formula) - 23.0.0.md"])
    }
}
