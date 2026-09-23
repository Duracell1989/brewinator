import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(
    vlcNotesURLTemplate: "https://example.test/vlc/releases/%s.html"
)

private func package(current: String = "3.0.24") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "vlc", installedVersion: "3.0.23", currentVersion: current, kind: .cask)
}

private let notesURL = URL(string: "https://example.test/vlc/releases/3.0.24.html")!

/// The shape of the page, reduced to the two headings that matter: a banner
/// `<h1>` that must be skipped, the release block, and the evergreen section
/// that must end it.
private func page(releaseHeading: String) -> String {
    """
    <body>
    <center><h1 class='bigtitle'>VLC <b>3.0.24</b> <em>Vetinari</em></h1></center>
    <section class="features">
    <div class="container">
    <h1 style='margin-bottom: 12px;'>\(releaseHeading)</h1>
    <ul><li>Adds ATRAC3 and ATRAC9 decoding</li></ul>
    <p>Also switches update verification to a new RSA-4096 key.</p>
    </div>
    <div class="container">
    <h1 style='margin-bottom: 12px;'>3.0 Highlights</h1>
    <ul><li>VLC 3.0 activates hardware decoding by default</li></ul>
    </div>
    </section>
    </body>
    """
}

@Suite("VLCReleaseNotes")
struct VLCReleaseNotesTests {
    @Test("canHandle matches only the vlc cask")
    func canHandle() {
        let source = VLCReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "vlc-nightly", installedVersion: "1", currentVersion: "2", kind: .cask)))
        // A formula sharing the name would be sent to a videolan.org URL built
        // from its own version, and the first claimant takes the whole result.
        #expect(!source.canHandle(OutdatedPackageInfo(name: "vlc", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("real fixture: the release block reduces to readable text with a full-notes link")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: try Fixture.data("vlc-release-notes-sample", extension: "html"), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### 3.0.24 Highlights"))
        #expect(notes.markdown.contains("Upgrades FFmpeg from 4.4 to 8.1.2"))
        #expect(notes.markdown.contains("Fixes the AudioToolbox MIDI synthesizer crash on macOS 26 and later"))
        #expect(notes.markdown.contains("[Full release notes](\(notesURL.absoluteString))"))
    }

    @Test("the evergreen 3.0 sections below the release block are left out")
    func evergreenSectionsExcluded() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: try Fixture.data("vlc-release-notes-sample", extension: "html"), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(!notes.markdown.contains("3.0 Highlights"))
        #expect(!notes.markdown.contains("Ambisonics"))
    }

    /// The block is found by position, not by its wording: 3.0.23's page heads
    /// the same block "3.0.22/3.0.23 Fixes", and 3.0.21's still said
    /// "3.0.19/3.0.20 Fixes". Keying on "<version> Highlights" would have
    /// missed all of those.
    @Test("a range heading that names neither version is still the release block")
    func rangeHeadingIsStillTheReleaseBlock() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: page(releaseHeading: "3.0.19/3.0.20 Fixes"), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### 3.0.19/3.0.20 Fixes"))
        #expect(notes.markdown.contains("Adds ATRAC3 and ATRAC9 decoding"))
        #expect(!notes.markdown.contains("hardware decoding by default"))
    }

    @Test("the banner title is not mistaken for the release block")
    func bannerHeadingSkipped() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: page(releaseHeading: "3.0.24 Highlights"), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### 3.0.24 Highlights"))
        #expect(!notes.markdown.contains("Vetinari"))
    }

    /// VideoLAN publishes a page per release, and its four-component point
    /// releases never get one - 3.0.17.3, 3.0.17.4 and 3.0.11.1 are all 404
    /// while 3.0.16 and 3.0.18 are 200. Retrying those means re-fetching the
    /// same 404 every day and never archiving anything, which is worse than the
    /// placeholder this source replaced.
    @Test("a 404 is a cacheable stub — VideoLAN publishes no page for four-component point releases")
    func notFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        let url = URL(string: "https://example.test/vlc/releases/3.0.17.4.html")!
        fetcher.respond(to: url, data: Data(), statusCode: 404)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "3.0.17.4"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("no release page"))
    }

    @Test("a 500 is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data(), statusCode: 500)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a 200 page with no section heading is a cacheable stub")
    func noBlockFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: "<html><body><p>Nothing here</p></body></html>", statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No release notes found"))
    }

    /// The nastiest failure this source can have: the real block is skipped,
    /// capture starts at the evergreen section, and generic "VLC 3.0 activates
    /// hardware decoding by default" copy is archived as that version's notes -
    /// once, permanently, with no warn line, because a non-empty result is a
    /// success.
    @Test("an <h1> whose text is on the next line still starts the release block")
    func multiLineHeadingStartsCapture() async {
        let html = """
            <body>
            <center><h1 class='bigtitle'>VLC <b>3.0.25</b> <em>Vetinari</em></h1></center>
            <section class="features">
            <div class="container">
            <h1 style='margin-bottom: 12px;'>
            3.0.25 Highlights</h1>
            <ul><li>Adds ATRAC3 and ATRAC9 decoding</li></ul>
            </div>
            <div class="container">
            <h1>3.0 Highlights</h1>
            <ul><li>VLC 3.0 activates hardware decoding by default</li></ul>
            </div>
            </section>
            </body>
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: html, statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Adds ATRAC3 and ATRAC9 decoding"))
        #expect(!notes.markdown.contains("hardware decoding by default"))
    }

    @Test("an uppercase <H1> is a heading too")
    func uppercaseHeadingMatches() async {
        let html = page(releaseHeading: "3.0.24 Highlights").replacingOccurrences(of: "<h1", with: "<H1").replacingOccurrences(of: "</h1>", with: "</H1>")
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: html, statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### 3.0.24 Highlights"))
        #expect(!notes.markdown.contains("hardware decoding by default"))
    }

    @Test("text after the </h1> on the same line is not part of the heading")
    func siblingTextExcludedFromHeading() async {
        let html = page(releaseHeading: "3.0.24 Highlights").replacingOccurrences(
            of: "<h1 style='margin-bottom: 12px;'>3.0.24 Highlights</h1>",
            with: "<h1>3.0.24 Highlights</h1> released 2026-10-01"
        )
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: html, statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### 3.0.24 Highlights"))
        #expect(!notes.markdown.contains("### 3.0.24 Highlights released"))
    }

    @Test("a non-UTF-8 body names itself rather than reporting HTTP 200")
    func undecodableBodyNamesItself() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data([0xFF, 0xFE, 0xFF]), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure(.transient(let reason)) = result else {
            Issue.record("expected transient failure, got \(result)")
            return
        }
        #expect(reason.contains("UTF-8"))
        #expect(!reason.contains("HTTP 200"))
    }

    @Test("the version goes into the URL verbatim")
    func versionFillsTheTemplate() async {
        var fetcher = FakeHTTPFetcher()
        let url = URL(string: "https://example.test/vlc/releases/3.0.25.html")!
        fetcher.respond(to: url, string: page(releaseHeading: "3.0.25 Highlights"), statusCode: 200)
        let source = VLCReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "3.0.25"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[Full release notes](\(url.absoluteString))"))
    }
}
