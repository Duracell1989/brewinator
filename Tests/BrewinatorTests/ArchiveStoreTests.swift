import Foundation
import Testing

@testable import Brewinator

private func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

private func package(_ name: String, kind: PackageKind = .formula, current: String = "1.1.0") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: name, installedVersion: "1.0.0", currentVersion: current, kind: kind)
}

@Suite("FileArchiveStore.existingFile")
struct ArchiveStoreExistingFileTests {
    @Test("false when no file has been written")
    func falseWhenAbsent() {
        let store = FileArchiveStore(directory: tempDirectory())
        #expect(!store.existingFile(for: package("node")))
    }

    @Test("true once written")
    func trueAfterWrite() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("node"))
        #expect(store.existingFile(for: package("node")))
    }
}

@Suite("FileArchiveStore.write")
struct ArchiveStoreWriteTests {
    @Test("writes content to the expected filename")
    func writesExpectedFilename() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)

        try store.write(ReleaseNotes(markdown: "## node (1.0.0 → 1.1.0)\n"), for: package("node", current: "1.1.0"))

        let expected = directory.appendingPathComponent("node (formula) - 1.1.0.md")
        #expect(FileManager.default.fileExists(atPath: expected.path))
        #expect(try String(contentsOf: expected, encoding: .utf8) == "## node (1.0.0 → 1.1.0)\n")
    }

    @Test("empty content is a no-op, never cached")
    func emptyContentIsNoOp() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)

        try store.write(ReleaseNotes(markdown: ""), for: package("node"))

        #expect(!store.existingFile(for: package("node")))
    }

    @Test("no leftover temp file after a successful write")
    func noLeftoverTempFile() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)

        try store.write(ReleaseNotes(markdown: "notes"), for: package("node"))

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(contents == ["node (formula) - 1.1.0.md"])
    }
}

@Suite("FileArchiveStore.prune")
struct ArchiveStorePruneTests {
    @Test("still-outdated package is kept")
    func keepsStillOutdated() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("node", current: "1.1.0"))

        let trashed = try store.prune(keeping: [ArchivePackageIdentity(name: "node", kind: .formula)], skippedBy: .none)

        #expect(trashed.isEmpty)
        #expect(store.existingFile(for: package("node", current: "1.1.0")))
    }

    /// The returned URLs are printed to the user, so they have to be the names
    /// the user recognises from the archive. `trashItem`'s resulting URL is the
    /// name *inside Trash*, which macOS renames on collision ("node (formula) -
    /// 1.1.0 2.md") - a name that never existed in the archive.
    @Test("returns the archived path, not the renamed path inside Trash")
    func returnsOriginalPaths() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("node", current: "1.1.0"))

        let trashed = try store.prune(keeping: [], skippedBy: .none)

        #expect(trashed.count == 1)
        // `resolvingSymlinksInPath` because `contentsOfDirectory` hands back
        // /private/var while the temp URL says /var - same directory.
        let parent = trashed.first?.deletingLastPathComponent().resolvingSymlinksInPath().path
        #expect(parent == directory.resolvingSymlinksInPath().path)
        #expect(trashed.first?.lastPathComponent == "node (formula) - 1.1.0.md")
    }

    @Test("upgraded-away package (no longer outdated) is trashed")
    func trashesUpgradedAway() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("node", current: "1.1.0"))

        let trashed = try store.prune(keeping: [], skippedBy: .none)

        #expect(trashed.count == 1)
        #expect(!store.existingFile(for: package("node", current: "1.1.0")))
    }

    @Test("still-outdated but now skip-listed package is trashed anyway")
    func trashesSkipListedEvenIfStillOutdated() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("discord", current: "1.1.0"))

        let trashed = try store.prune(keeping: [ArchivePackageIdentity(name: "discord", kind: .formula)], skippedBy: SkipMatcher(["discord"]))

        #expect(trashed.count == 1)
        #expect(!store.existingFile(for: package("discord", current: "1.1.0")))
    }

    @Test("skip glob pattern matches at prune time")
    func trashesGlobSkipListed() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("libssh2", current: "1.0.0"))

        let trashed = try store.prune(keeping: [ArchivePackageIdentity(name: "libssh2", kind: .formula)], skippedBy: SkipMatcher(["lib*"]))

        #expect(trashed.count == 1)
    }

    @Test("a formula and a cask sharing the same name are not conflated — the cask can be pruned while the formula stays")
    func doesNotConflateFormulaAndCaskWithSameName() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileArchiveStore(directory: directory)
        try store.write(ReleaseNotes(markdown: "notes"), for: package("foo", kind: .formula, current: "1.0.0"))
        try store.write(ReleaseNotes(markdown: "notes"), for: package("foo", kind: .cask, current: "2.0.0"))

        // Only the formula "foo" is still outdated; the cask "foo" upgraded away.
        let trashed = try store.prune(keeping: [ArchivePackageIdentity(name: "foo", kind: .formula)], skippedBy: .none)

        #expect(trashed.count == 1)
        #expect(store.existingFile(for: package("foo", kind: .formula, current: "1.0.0")))
        #expect(!store.existingFile(for: package("foo", kind: .cask, current: "2.0.0")))
    }

    @Test("non-markdown files in the directory are ignored")
    func ignoresNonMarkdownFiles() throws {
        let directory = tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("stray".utf8).write(to: directory.appendingPathComponent(".DS_Store"))
        let store = FileArchiveStore(directory: directory)

        let trashed = try store.prune(keeping: [], skippedBy: .none)

        #expect(trashed.isEmpty)
    }

    @Test("missing archive directory prunes nothing rather than throwing")
    func missingDirectoryIsHarmless() throws {
        let store = FileArchiveStore(directory: tempDirectory())
        let trashed = try store.prune(keeping: [], skippedBy: .none)
        #expect(trashed.isEmpty)
    }
}

@Suite("FileArchiveStore.packageName(fromArchiveFilename:)")
struct ArchiveStoreFilenameParsingTests {
    @Test("extracts the name before the kind/version suffix")
    func extractsName() {
        #expect(FileArchiveStore.packageName(fromArchiveFilename: "node (formula) - 23.0.0") == "node")
    }

    @Test("a name that itself contains a space is preserved up to the first \" (\"")
    func preservesSpacesInName() {
        #expect(FileArchiveStore.packageName(fromArchiveFilename: "windows app (cask) - 11.3.8") == "windows app")
    }

    @Test("malformed filename with no \" (\" returns nil")
    func malformedFilenameReturnsNil() {
        #expect(FileArchiveStore.packageName(fromArchiveFilename: "not-a-valid-archive-name") == nil)
    }
}
