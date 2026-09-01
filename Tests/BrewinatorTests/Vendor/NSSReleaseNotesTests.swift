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
    firefoxNotesURLTemplate: "",
    ffmpegChangelogURLTemplate: "",
    dotnetReleasesURLTemplate: "",
    dotnetNotableChangesHeading: "",
    nssNotesURLTemplate: "https://example.test/nss/nss_%s.html",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "3.128") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "nss", installedVersion: "3.127", currentVersion: current, kind: .formula)
}

private let notesURL = URL(string: "https://example.test/nss/nss_3_128.html")!

@Suite("NSSReleaseNotes")
struct NSSReleaseNotesTests {
    @Test("canHandle matches only nss")
    func canHandle() {
        let source = NSSReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "nspr", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("real fixture: dots become underscores in the URL, intro date prepended, Changes section reduced with a full-notes link")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: try Fixture.data("nss-release-notes-sample", extension: "html"), statusCode: 200)
        let source = NSSReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("**Network Security Services (NSS) 3.128 was released on 26 August 2026.**"))
        #expect(notes.markdown.contains("Bug 2056235"))
        #expect(notes.markdown.contains("DTLS1.2/1.3 - silently discard invalid records."))
        #expect(!notes.markdown.contains("Distribution Information"))
        #expect(notes.markdown.contains("[Full release notes](\(notesURL.absoluteString))"))
    }

    @Test("a 404 is transient - the doc build can lag the actual release")
    func notFoundIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data(), statusCode: 404)
        let source = NSSReleaseNotes(httpFetcher: fetcher, database: testDatabase)

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
        let source = NSSReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a 200 page with no Changes in NSS section is a cacheable stub")
    func noChangesSectionIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: notesURL, string: "<html><body><h2>Introduction</h2><div class=\"docutils container\"><p>Hi.</p></div></body></html>", statusCode: 200)
        let source = NSSReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No \"Changes in NSS\" section"))
    }
}
