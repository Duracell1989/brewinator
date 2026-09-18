import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(
    gnuPatchProjects: [
        "readline": GNUPatchSpec(urlTemplate: "https://example.test/readline/readline-%release-patches/readline%compact-%patch")
    ]
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

    @Test("a CRLF-served report leaves no carriage return in the heading, the reporter or the bug-report link")
    func carriageReturns() throws {
        let crlf = try Fixture.string("readline-patch-report-sample", extension: "txt").replacingOccurrences(of: "\n", with: "\r\n")
        let report = try #require(GNUPatchReport(crlf))

        #expect(report.patchID == "readline83-004")
        #expect(report.reportedBy == ["Lennart Ackermans"])
        #expect(report.referenceURL == "https://lists.gnu.org/archive/html/bug-bash/2026-05/msg00066.html")
        #expect(!report.description.contains("\r"))
    }

    @Test("a description written on the Bug-Description line itself is kept, not discarded as empty")
    func sameLineDescription() throws {
        let text = """
            Patch-ID: readline83-099

            Bug-Description:  Fixes a crash in the completion code.

            Patch (apply with `patch -p0'):
            *** a
            --- b
            """
        let report = try #require(GNUPatchReport(text))

        #expect(report.description == "Fixes a crash in the completion code.")
    }

    @Test("a reformatted diff marker still ends the description at the first diff line instead of swallowing the patch")
    func fallbackDiffAnchor() throws {
        let text = """
            Patch-ID: readline83-098

            Bug-Description:

            Corrects the prompt width calculation.

              Patch (apply with a reformatted marker):
            *** ../readline-8.3-patched/display.c
            --- display.c
            """
        let report = try #require(GNUPatchReport(text))

        #expect(report.description.contains("Corrects the prompt width calculation."))
        #expect(!report.description.contains("display.c"))
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

    @Test("does not claim a cask that happens to share the formula's name - it would be fetched from ftp.gnu.org and never reach its real notes")
    func ignoresCasks() {
        let source = GNUPatchNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(!source.canHandle(OutdatedPackageInfo(name: "readline", installedVersion: "8.3.3", currentVersion: "8.3.6", kind: .cask)))
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

    @Test("an unreachable report fails the whole range transiently rather than archiving a permanent gap")
    func unreachableIsTransient() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: patchURL(4), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        fetcher.respond(to: patchURL(5), string: "", statusCode: 429)
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline())
        guard case .failure(let error) = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
        // The status and the URL both survive into the reason - a throttle has
        // to be distinguishable from a mistyped template in the log.
        #expect(error == .transient(reason: "readline \(patchURL(5).absoluteString): HTTP 429"))
    }

    @Test("a fetched but unreadable report is archived as a named gap, not retried forever")
    func unparseableIsArchived() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: patchURL(4), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        fetcher.respond(to: patchURL(5), string: "a layout nobody recognises\n", statusCode: 200)
        fetcher.respond(to: patchURL(6), string: try Fixture.string("readline-patch-report-sample", extension: "txt"), statusCode: 200)
        let source = GNUPatchNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(readline())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("`8.3.3 → 8.3.6` applies patches 004, 005 and 006."))
        #expect(notes.markdown.contains("### readline83-005"))
        #expect(notes.markdown.contains("could not be read"))
        #expect(notes.markdown.contains("[Patch report](\(patchURL(5).absoluteString))"))
    }

    @Test("the capped range still states what the bump applies - narrowing it to the fetched subset would be a false claim")
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
        let fullRange = (1...19).map { String(format: "%03d", $0) }.joined(separator: ", ")
        #expect(notes.markdown.contains("applies patches \(fullRange) and 020."))
        #expect(notes.markdown.contains("_Only the newest 12 are reproduced below; 8 older reports are omitted._"))
    }

    @Test("the shipped templates render the real ftp.gnu.org paths")
    func liveTemplatesRender() async {
        let source = GNUPatchNotes(httpFetcher: FakeHTTPFetcher(), database: .live)

        let readlineResult = await source.fetch(readline(installed: "8.3.3", current: "8.3.4"))
        guard case .failure(let readlineError) = readlineResult, case .transient(let readlineReason) = readlineError else {
            Issue.record("expected an unregistered-URL failure, got \(readlineResult)")
            return
        }
        #expect(readlineReason.contains("https://ftp.gnu.org/gnu/readline/readline-8.3-patches/readline83-004"))

        let bash = OutdatedPackageInfo(name: "bash", installedVersion: "5.3.0", currentVersion: "5.3.1", kind: .formula)
        let bashResult = await source.fetch(bash)
        guard case .failure(let bashError) = bashResult, case .transient(let bashReason) = bashError else {
            Issue.record("expected an unregistered-URL failure, got \(bashResult)")
            return
        }
        #expect(bashReason.contains("https://ftp.gnu.org/gnu/bash/bash-5.3-patches/bash53-001"))
    }
}
