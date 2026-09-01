import Foundation
import Testing

@testable import Brewinator

private let newsURL = URL(string: "https://raw.githubusercontent.com/gpg/gpgme/master/NEWS")!

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
    newsFileSources: ["gpgme": NewsFileSpec(url: newsURL, headingStyle: .gnupg)],
    gitlabStubPattern: "^the .* release\\.?$",
    gitlabStubMaxLength: 30,
    gitlabNewsFiles: [],
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

private func gpgmePackage(installed: String = "2.1.2", current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "gpgme", installedVersion: installed, currentVersion: current, kind: .formula)
}

private func loadedSource() throws -> NewsFileChangelog {
    var fetcher = FakeHTTPFetcher()
    fetcher.respond(to: newsURL, data: try Fixture.data("gpgme-news-sample", extension: "txt"), statusCode: 200)
    return NewsFileChangelog(httpFetcher: fetcher, database: testDatabase)
}

@Suite("NewsFileChangelog")
struct NewsFileChangelogTests {
    @Test("canHandle is true only for a name registered in newsFileSources")
    func canHandle() {
        let source = NewsFileChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(gpgmePackage(current: "2.2.0")))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("the range runs from the current version down to the installed one, exclusive")
    func extractsRange() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(installed: "2.1.2", current: "2.2.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Noteworthy changes in version 2.2.0"))
        #expect(notes.markdown.contains("Handle the new SIGINFO status line"))
        #expect(!notes.markdown.contains("Noteworthy changes in version 2.1.2"))
    }

    @Test("the unreleased section above the current version is never included")
    func excludesUnreleasedSection() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(current: "2.2.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(!notes.markdown.contains("2.2.1"))
    }

    @Test("an installed version no longer in the file falls back to everything below the current one")
    func fallsBackToOpenEndedRange() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(installed: "1.0.0", current: "2.2.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Noteworthy changes in version 2.2.0"))
        #expect(notes.markdown.contains("Noteworthy changes in version 2.1.2"))
    }

    @Test("an unknown current version reports no entry rather than falling back to the newest section")
    func unknownCurrentVersionReportsNoEntry() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(current: "99.0.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No NEWS entry for 99.0.0"))
        #expect(!notes.markdown.contains("Noteworthy changes"))
    }

    @Test("a formula revision suffix is stripped before matching")
    func matchesThroughRevisionSuffix() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(installed: "2.1.2_1", current: "2.2.0_2"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Noteworthy changes in version 2.2.0"))
        #expect(!notes.markdown.contains("Noteworthy changes in version 2.1.2"))
    }

    @Test("the NEWS URL is linked under a labelled footer")
    func linksTheSource() async throws {
        let source = try loadedSource()
        let result = await source.fetch(gpgmePackage(current: "2.2.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[Full NEWS](\(newsURL.absoluteString))"))
    }

    @Test("a network error is transient")
    func networkErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(newsURL)
        let source = NewsFileChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(gpgmePackage(current: "2.2.0"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a non-200 response is transient")
    func nonOKResponseIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: newsURL, string: "", statusCode: 404)
        let source = NewsFileChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(gpgmePackage(current: "2.2.0"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
