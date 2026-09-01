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
    gitlabStubPattern: "",
    gitlabStubMaxLength: 0,
    gitlabNewsFiles: [],
    firefoxNotesURLTemplate: "https://example.test/firefox/%s/releasenotes/",
    ffmpegChangelogURLTemplate: "",
    dotnetReleasesURLTemplate: "",
    dotnetNotableChangesHeading: "",
    nssNotesURLTemplate: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "145.0") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "firefox", installedVersion: "144.0", currentVersion: current, kind: .cask)
}

private let notesURL = URL(string: "https://example.test/firefox/145.0/releasenotes/")!

@Suite("FirefoxReleaseNotes")
struct FirefoxReleaseNotesTests {
    @Test("canHandle matches only the plain firefox cask, not @esr/@beta")
    func canHandle() {
        let source = FirefoxReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "firefox@esr", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixture: heading-tagged note blocks reduce to readable text with a full-notes link")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: try Fixture.data("firefox-release-notes-sample", extension: "html"), statusCode: 200)
        let source = FirefoxReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### New"))
        #expect(notes.markdown.contains("comments"))
        #expect(notes.markdown.contains("[Full release notes](\(notesURL.absoluteString))"))
    }

    @Test("a 404 is transient, not a cacheable stub — Mozilla sometimes publishes the page after the build ships")
    func notFoundIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data(), statusCode: 404)
        let source = FirefoxReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a 500 is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data(), statusCode: 500)
        let source = FirefoxReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a 200 page with no release-note-content markers is a cacheable stub")
    func noNotesFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: "<html><body><p>Nothing here</p></body></html>", statusCode: 200)
        let source = FirefoxReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No release notes found"))
    }
}
