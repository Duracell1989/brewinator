import Foundation
import Testing

@testable import Brewinator

private let vivaldiFeed = URL(string: "https://update.vivaldi.com/update/1.0/public/mac/appcast.xml")!
private let vivaldiNotesURL = URL(string: "https://update.vivaldi.com/update/1.0/relnotes/8.1.4087.64.html")!

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: ["vivaldi": vivaldiFeed],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
    newsFileSources: [:],
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

private func vivaldiPackage(current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "vivaldi", installedVersion: "8.1.4087.62", currentVersion: current, kind: .cask)
}

@Suite("SparkleAppcast")
struct SparkleAppcastTests {
    @Test("canHandle is true only for a name registered in sparkleFeeds")
    func canHandle() {
        let source = SparkleAppcast(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(vivaldiPackage(current: "8.1.4087.64")))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("matched item's notes link is fetched and reduced to text")
    func matchedItemNotesReduced() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, data: try Fixture.data("sparkle-appcast-sample", extension: "xml"), statusCode: 200)
        fetcher.respond(to: vivaldiNotesURL, data: try Fixture.data("sparkle-notes-sample", extension: "html"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Changelog since Vivaldi"))
        #expect(notes.markdown.contains("[Full release notes](\(vivaldiNotesURL.absoluteString))"))
    }

    @Test("no releaseNotesLink in the feed is a cacheable message, not a failure")
    func noNotesLinkIsCacheable() async {
        let emptyFeed = """
            <?xml version="1.0"?>
            <rss><channel><item><title>1.0</title></item></channel></rss>
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, string: emptyFeed, statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No release-notes link"))
    }

    @Test("a feed fetch failure is transient")
    func feedFetchFailureIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(vivaldiFeed)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a releaseNotesLink tag carrying an attribute (e.g. xml:lang) is still matched, not just the bare <tag> form")
    func releaseNotesLinkWithAttributeIsMatched() async throws {
        let feedWithAttribute = """
            <?xml version="1.0" standalone="yes"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
                <channel>
                    <item>
                        <title>8.1.4087.64</title>
                        <sparkle:releaseNotesLink xml:lang="en">\(vivaldiNotesURL.absoluteString)</sparkle:releaseNotesLink>
                        <sparkle:shortVersionString>8.1.4087.64</sparkle:shortVersionString>
                    </item>
                </channel>
            </rss>
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, string: feedWithAttribute, statusCode: 200)
        fetcher.respond(to: vivaldiNotesURL, data: try Fixture.data("sparkle-notes-sample", extension: "html"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[Full release notes](\(vivaldiNotesURL.absoluteString))"))
        #expect(!notes.markdown.contains("No release-notes link"))
    }

    @Test("a notes-page fetch failure is transient")
    func notesPageFetchFailureIsTransient() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, data: try Fixture.data("sparkle-appcast-sample", extension: "xml"), statusCode: 200)
        fetcher.fail(vivaldiNotesURL)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
