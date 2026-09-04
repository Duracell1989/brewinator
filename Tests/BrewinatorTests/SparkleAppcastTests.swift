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

    @Test("an item with neither a notes link nor a description is a cacheable message, not a failure")
    func noNotesOfEitherKindIsCacheable() async {
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
        #expect(notes.markdown.contains("No release notes in the Sparkle feed"))
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
        #expect(!notes.markdown.contains("No release notes in the Sparkle feed"))
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

    // ProtonVPN, QLMarkdown and Telegram all publish this way: no notes page
    // anywhere, the notes inlined in the item as CDATA HTML.
    @Test("notes inlined in an item's description are used when there is no notes link")
    func inlineDescriptionIsUsed() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, data: try Fixture.data("sparkle-appcast-description-sample", extension: "xml"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "6.5.1"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("- Kill switch no longer leaks on wake"))
        #expect(!notes.markdown.contains("Earlier release, must not be picked"))
    }

    // Without attribute matching this falls back to the newest item, so the
    // wrong release's notes get archived under the requested version.
    @Test("a version published only as an enclosure attribute still matches its item")
    func enclosureAttributeVersionMatches() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, data: try Fixture.data("sparkle-appcast-description-sample", extension: "xml"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "6.5.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Earlier release, must not be picked"))
        #expect(!notes.markdown.contains("Kill switch"))
    }

    // Items are split on `</item>`, so the first record also holds the channel
    // header — whose own <description> must not be read as the item's notes.
    @Test("a channel-level description is not mistaken for the first item's notes")
    func channelDescriptionIgnored() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, data: try Fixture.data("sparkle-appcast-description-sample", extension: "xml"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "6.5.1"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(!notes.markdown.contains("Most recent changes with links to updates"))
    }

    @Test("an item carrying both a notes link and a description resolves through the link")
    func linkWinsOverDescription() async throws {
        let feedWithBoth = """
            <?xml version="1.0" standalone="yes"?>
            <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
                <channel>
                    <item>
                        <title>8.1.4087.64</title>
                        <description><![CDATA[<p>Inline copy, second best</p>]]></description>
                        <sparkle:releaseNotesLink>\(vivaldiNotesURL.absoluteString)</sparkle:releaseNotesLink>
                        <sparkle:shortVersionString>8.1.4087.64</sparkle:shortVersionString>
                    </item>
                </channel>
            </rss>
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: vivaldiFeed, string: feedWithBoth, statusCode: 200)
        fetcher.respond(to: vivaldiNotesURL, data: try Fixture.data("sparkle-notes-sample", extension: "html"), statusCode: 200)
        let source = SparkleAppcast(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(vivaldiPackage(current: "8.1.4087.64"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Changelog since Vivaldi"))
        #expect(!notes.markdown.contains("Inline copy, second best"))
    }
}
