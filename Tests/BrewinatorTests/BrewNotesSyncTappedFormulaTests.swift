import Foundation
import Testing

@testable import Brewinator

/// `brew outdated` reports a formula by its tap-qualified name while `brew
/// info` reports it short, so every third-party-tap formula failed to resolve
/// and left an uncollectable temp file behind. Fixed in v0.4.1.
@Suite("BrewNotesSync — tapped formulae")
struct BrewNotesSyncTappedFormulaTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private static func tappedFormula() -> OutdatedResult {
        OutdatedResult(
            formulae: [
                OutdatedPackageInfo(
                    name: "sometool",
                    installedVersion: "0.4.0",
                    currentVersion: "0.4.1",
                    kind: .formula,
                    fullName: "someone/tap/sometool"
                )
            ],
            casks: []
        )
    }

    @Test("the brew info entry is joined by full name, so stableURL/homepage still merge in")
    func mergesBrewInfoForTappedFormula() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let brewClient = FakeBrewClient(
            result: Self.tappedFormula(),
            formulaURLInfo: [
                "someone/tap/sometool": PackageURLInfo(stableURL: "https://example.com/sometool/v0.4.1.tar.gz", homepage: "https://example.com/sometool")
            ]
        )
        let sync = BrewNotesSync(
            brewClient: brewClient,
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        _ = try await sync.run()

        let content = try String(contentsOf: directory.appendingPathComponent("sometool (formula) - 0.4.1.md"), encoding: .utf8)
        #expect(content.contains("stableURL=https://example.com/sometool/v0.4.1.tar.gz"))
    }

    /// `appendingPathComponent` turns a slash into a real path component, so a
    /// slashed name wrote into a subdirectory that doesn't exist and threw.
    @Test("archives to one flat file, with no slash in the name")
    func tappedFormulaArchivesFlat() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: Self.tappedFormula()),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        let result = try await sync.run()

        #expect(result.newItems.map(\.name) == ["sometool"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["sometool (formula) - 0.4.1.md"])
    }

    /// `config skip add sometool` means the short name; the full name is an
    /// implementation detail of the join and must never gate skip matching.
    @Test("skip-listing by short name suppresses it")
    func skipListMatchesTappedFormulaShortName() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let config = UserConfig(archiveDirectory: directory.path, skipList: ["sometool"], notify: false)
        let sync = BrewNotesSync(
            brewClient: FakeBrewClient(result: Self.tappedFormula()),
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        let result = try await sync.run()

        #expect(result.newItems.isEmpty)
    }

    /// Querying with the short name would silently resolve to a same-named
    /// *core* formula where one exists, returning the wrong URLs.
    @Test("brew info is queried with full names, so a tap formula can't be shadowed by a core one")
    func queriesBrewInfoWithFullNames() async throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let outdated = OutdatedResult(
            formulae: Self.tappedFormula().formulae,
            casks: [OutdatedPackageInfo(name: "obsidian", installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .cask)]
        )
        let config = UserConfig(archiveDirectory: directory.path, skipList: [], notify: false)
        let brewClient = NameRecordingBrewClient(result: outdated)
        let sync = BrewNotesSync(
            brewClient: brewClient,
            archiveStore: FileArchiveStore(directory: directory),
            resolver: Resolver(sources: [EchoingNoteSource()]),
            config: config
        )

        _ = try await sync.run()

        #expect(brewClient.formulaNames == ["someone/tap/sometool"])
        #expect(brewClient.caskNames == ["obsidian"])
    }
}
