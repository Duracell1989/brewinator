import Foundation
import Testing

@testable import Brewinator

private let newsURL = URL(string: "https://raw.githubusercontent.com/gpg/gpgme/master/NEWS")!
private let popplerNewsURL = URL(string: "https://gitlab.freedesktop.org/poppler/poppler/-/raw/master/NEWS")!

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
    newsFileSources: [
        "gpgme": NewsFileSpec(url: newsURL, headingStyle: .gnupg),
        "poppler": NewsFileSpec(url: popplerNewsURL, headingStyle: .poppler),
    ],
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

/// poppler goes through the same source as the GnuPG family but with the
/// `Release 26.09.0:` heading style, so the range logic is worth pinning
/// against its real NEWS file too.
@Suite("NewsFileChangelog (poppler)")
struct NewsFileChangelogPopplerTests {
    private func popplerPackage(installed: String = "26.08.0", current: String = "26.09.0") -> OutdatedPackageInfo {
        OutdatedPackageInfo(name: "poppler", installedVersion: installed, currentVersion: current, kind: .formula)
    }

    private func loadedSource() throws -> NewsFileChangelog {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: popplerNewsURL, data: try Fixture.data("poppler-news-sample", extension: "txt"), statusCode: 200)
        return NewsFileChangelog(httpFetcher: fetcher, database: testDatabase)
    }

    @Test("the upgrade's own section is extracted and the installed one left out")
    func extractsRange() async throws {
        let source = try loadedSource()
        let result = await source.fetch(popplerPackage())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Release 26.09.0:"))
        #expect(notes.markdown.contains("pdftotext: Add -urls option"))
        #expect(notes.markdown.contains("harfbuzz is now required for font subsetting"))
        #expect(!notes.markdown.contains("Release 26.08.0:"))
    }

    @Test("skipping several releases collects every section down to the installed one")
    func spansMultipleReleases() async throws {
        let source = try loadedSource()
        let result = await source.fetch(popplerPackage(installed: "26.07.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Release 26.09.0:"))
        #expect(notes.markdown.contains("Release 26.08.0:"))
        #expect(!notes.markdown.contains("Release 26.07.0:"))
    }

    @Test("the NEWS URL is linked under a labelled footer")
    func linksTheSource() async throws {
        let source = try loadedSource()
        let result = await source.fetch(popplerPackage())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[Full NEWS](\(popplerNewsURL.absoluteString))"))
    }
}
