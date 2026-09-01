import Foundation
import Testing

@testable import Brewinator

private let feedURL = URL(string: "https://example.test/android-studio")!

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
    nssNotesURLTemplate: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: feedURL
)

/// `current` is the raw cask version — this source reads it uncleaned, so
/// tests must pass the comma-separated shape, not a plain semver string.
private func package(current: String = "2026.1.3.7,quail3-patch1,AI-261.9583.0") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "android-studio", installedVersion: "2026.1.3.6,quail3,AI-261", currentVersion: current, kind: .cask)
}

@Suite("AndroidStudioBlog")
struct AndroidStudioBlogTests {
    @Test("canHandle matches only android-studio")
    func canHandle() {
        let source = AndroidStudioBlog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixture: codename extracted from the raw version matches the Blogger post title")
    func realFixtureMatchesCodename() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, data: try Fixture.data("android-studio-feed-sample", extension: "json"), statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Quail 3 Patch 1 is now available"))
        #expect(notes.markdown.contains("[Full announcement](https://androidstudio.googleblog.com/2026/08/android-studio-quail-3-patch-1-now.html)"))
    }

    @Test("a plain codename (no patch suffix) also matches its post")
    func plainCodenameMatches() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, data: try Fixture.data("android-studio-feed-sample", extension: "json"), statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "2026.1.3.5,quail3,AI-261"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Quail 3 is now available"))
        #expect(!notes.markdown.contains("Patch 1"))
    }

    @Test("no codename field in the raw version falls back to the newest post")
    func noCodenameFallsBackToNewest() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, data: try Fixture.data("android-studio-feed-sample", extension: "json"), statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "2026.1.3.7"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Quail 3 Patch 1 is now available"))
    }

    @Test("a 500 is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, data: Data(), statusCode: 500)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("invalid JSON is transient")
    func invalidJSONIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, string: "not json", statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a matched post that reduces to no readable text and has no alternate link still yields non-empty markdown")
    func imageOnlyPostWithNoLinkYieldsNonEmptyMarkdown() async {
        var fetcher = FakeHTTPFetcher()
        let imageOnlyFeed = #"""
            {"feed":{"entry":[
                {"title":{"$t":"Android Studio Quail 3 Patch 1 is now available"},"content":{"$t":"<img src=\"foo.jpg\">"}}
            ]}}
            """#
        fetcher.respond(to: feedURL, string: imageOnlyFeed, statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        // Empty markdown is a no-op in ArchiveStore.write() — the file never
        // gets written, so existingFile(for:) keeps returning false and this
        // post is re-fetched and re-skipped every single day forever.
        #expect(!notes.markdown.isEmpty)
    }

    @Test("an empty feed is a cacheable stub")
    func emptyFeedIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feedURL, string: #"{"feed":{}}"#, statusCode: 200)
        let source = AndroidStudioBlog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No matching post found"))
    }
}
