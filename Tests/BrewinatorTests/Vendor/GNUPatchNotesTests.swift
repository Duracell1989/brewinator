import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
    newsFileSources: [:],
    gnuPatchProjects: [
        "readline": GNUPatchSpec(urlTemplate: "https://example.test/readline/readline-%release-patches/readline%compact-%patch")
    ],
    gitlabStubPattern: "",
    gitlabStubMaxLength: 0,
    gitlabNewsFiles: [],
    downloadHostForges: [],
    firefoxNotesURLTemplate: "",
    ffmpegChangelogURLTemplate: "",
    dotnetReleasesURLTemplate: "",
    dotnetNotableChangesHeading: "",
    nssNotesURLTemplate: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func readline(installed: String = "8.3.3", current: String = "8.3.6") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "readline", installedVersion: installed, currentVersion: current, kind: .formula)
}

private func patchURL(_ number: Int) -> URL {
    // swiftlint:disable:next force_unwrapping
    URL(string: "https://example.test/readline/readline-8.3-patches/readline83-\(String(format: "%03d", number))")!
}

@Suite("PatchLevelVersion")
struct PatchLevelVersionTests {
    @Test("three components split into release and patch level")
    func threeComponents() throws {
        let version = try #require(PatchLevelVersion("8.3.6"))
        #expect(version.release == "8.3")
        #expect(version.patch == 6)
        #expect(version.compactRelease == "83")
    }

    @Test("a two-component version is the unpatched tarball, patch level 0")
    func twoComponents() throws {
        let version = try #require(PatchLevelVersion("8.3"))
        #expect(version.release == "8.3")
        #expect(version.patch == 0)
    }

    @Test("anything that is not a patch level is rejected rather than guessed at")
    func rejected() {
        #expect(PatchLevelVersion("8") == nil)
        #expect(PatchLevelVersion("8.3.6.1") == nil)
        #expect(PatchLevelVersion("8.3.beta") == nil)
    }
}

@Suite("GNUPatchReport")
struct GNUPatchReportTests {
    @Test("real fixture: reads the patch ID, reporter and description, and stops at the diff")
    func realFixture() throws {
        let report = try #require(GNUPatchReport(try Fixture.string("readline-patch-report-sample", extension: "txt")))

        #expect(report.patchID == "readline83-004")
        #expect(report.reportedBy == ["Lennart Ackermans"])
        #expect(report.referenceURL == "https://lists.gnu.org/archive/html/bug-bash/2026-05/msg00066.html")
        #expect(report.description.hasPrefix("If readline is invoked with the cursor somewhere other than column 0"))
        // The diff is the bulk of the file and none of it is readable notes.
        #expect(!report.description.contains("*** ../readline-8.3-patched/display.c"))
        #expect(!report.description.contains("Patch (apply with"))
    }

    @Test("a second reporter on an indented continuation line is kept, and emails are stripped")
    func multipleReporters() throws {
        let report = try #require(GNUPatchReport(try Fixture.string("readline-patch-report-multi-reporter-sample", extension: "txt")))

        #expect(report.patchID == "readline83-005")
        #expect(report.reportedBy == ["Ben Kallus", "Derek Schrock"])
        // Only the first URL - the second is the other reporter's thread.
        #expect(report.referenceURL == "https://lists.gnu.org/archive/html/bug-readline/2026-06/msg00005.html")
        #expect(report.description.contains("more than 256 wrapped"))
        // The indented Bug-Reference-ID continuation must not be read as a reporter.
        #expect(!report.reportedBy.contains { $0.contains("@") })
    }

    @Test("a file with no description is not a report")
    func noDescription() {
        #expect(GNUPatchReport("Patch-ID: readline83-099\n\nPatch (apply with `patch -p0'):\n*** a\n--- b\n") == nil)
    }
}

@Suite("GNUPatchNotes")
struct GNUPatchNotesTests {
    @Test("claims a same-release patch bump")
    func claimsPatchBump() {
        let source = GNUPatchNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(readline()))
    }

    @Test("does not claim a real release bump - a patch range is meaningless across one, so it falls through instead")
    func ignoresReleaseBump() {
        let source = GNUPatchNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(!source.canHandle(readline(installed: "8.3.6", current: "8.4")))
        #expect(!source.canHandle(readline(installed: "8.3.6", current: "8.4.1")))
    }

    @Test("does not claim a package with no patch spec")
    func ignoresOtherPackages() {
        let source = GNUPatchNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(!source.canHandle(OutdatedPackageInfo(name: "gettext", installedVersion: "0.26", currentVersion: "1.0", kind: .formula)))
    }

    @Test("fetches every patch in the range and joins them under one preamble")
    func fetchesRange() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: patchURL(4), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        fetcher.respond(to: patchURL(5), string: try Fixture.string("readline-patch-report-multi-reporter-sample", extension: "txt"), statusCode: 200)
        fetcher.respond(to: patchURL(6), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("`8.3.3 → 8.3.6` applies patches 004, 005 and 006."))
        #expect(notes.markdown.contains("### readline83-004"))
        #expect(notes.markdown.contains("### readline83-005"))
        #expect(notes.markdown.contains("_Reported by Ben Kallus, Derek Schrock._"))
        #expect(notes.markdown.contains("[Patch directory](https://example.test/readline/readline-8.3-patches/)"))
    }

    @Test("a single patch reads as \"patch 004\", not \"patches  and 004\"")
    func singlePatch() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: patchURL(4), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline(installed: "8.3.3", current: "8.3.4"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("applies patch 004."))
    }

    @Test("one unreachable patch does not sink the rest of the range")
    func partialFailure() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: patchURL(4), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        fetcher.respond(to: patchURL(5), string: "", statusCode: 404)
        fetcher.fail(patchURL(6))
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### readline83-004"))
        // The stated range is what the bump applies, not what happened to come
        // back - narrowing it to 004 would be a false claim about the upgrade.
        #expect(notes.markdown.contains("applies patches 004, 005 and 006."))
        #expect(notes.markdown.contains("_Patch reports 005, 006 could not be fetched"))
    }

    @Test("a range that fetches nothing is transient - the mirror lags a formula bump by hours")
    func totalFailureIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        for number in 4...6 {
            fetcher.respond(to: patchURL(number), string: "", statusCode: 404)
        }
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline())
        guard case .failure(let error) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        #expect(error == .transient(reason: "readline: no patch report fetched for 004-006"))
    }

    @Test("a long-deferred upgrade fetches only the newest 12 patches and says so")
    func capsTheRange() async throws {
        var fetcher = FakeHTTPFetcher()
        let sample = try Fixture.string("readline-patch-report-sample", extension: "txt")
        for number in 1...20 {
            fetcher.respond(to: patchURL(number), string: sample, statusCode: 200)
        }
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline(installed: "8.3", current: "8.3.20"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_8 older patches are omitted._"))
        #expect(notes.markdown.contains("applies patches 009, 010, 011, 012, 013, 014, 015, 016, 017, 018, 019 and 020."))
    }
}
