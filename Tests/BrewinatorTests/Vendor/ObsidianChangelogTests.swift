import Foundation
import Testing

@testable import Brewinator

private let obsidianRepo = "obsidianmd/obsidian-releases"
private let releasesListURL = URL(string: "https://api.github.com/repos/obsidianmd/obsidian-releases/releases")!
private let releasesURL = "https://github.com/obsidianmd/obsidian-releases/releases"

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
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
    obsidianRepo: obsidianRepo,
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "1.13.7") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "obsidian", installedVersion: "1.13.6", currentVersion: current, kind: .cask)
}

@Suite("ObsidianChangelog")
struct ObsidianChangelogTests {
    @Test("canHandle matches only obsidian")
    func canHandle() {
        let source = ObsidianChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixtures: release body's changelog link is followed and its content scoped, reduced, and capped")
    func realFixturesSucceed() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesListURL, data: try Fixture.data("obsidian-releases-sample", extension: "json"), statusCode: 200)
        fetcher.respond(
            to: URL(string: "https://obsidian.md/changelog/2026-08-12-desktop-v1.13.7/")!,
            data: try Fixture.data("obsidian-changelog-sample", extension: "html"),
            statusCode: 200
        )
        let source = ObsidianChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No longer broken"))
        #expect(notes.markdown.contains("special characters in their names"))
        #expect(!notes.markdown.contains("bg-green-900"))
        #expect(notes.markdown.contains("[Full changelog](https://obsidian.md/changelog/2026-08-12-desktop-v1.13.7/)"))
    }

    @Test("a release body without a changelog link falls back to printing the raw body, not a transient failure")
    func bodyWithoutChangelogLinkFallsBack() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: releasesListURL,
            string: #"[{"tag_name":"v1.13.7","body":"No changelog link here, just prose."}]"#,
            statusCode: 200
        )
        let source = ObsidianChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No changelog link here, just prose."))
        #expect(notes.markdown.contains("[Full release on github.com](\(releasesURL))"))
    }

    @Test("no matching release is a cacheable stub")
    func noMatchIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesListURL, string: "[]", statusCode: 200)
        let source = ObsidianChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No matching release found"))
    }

    @Test("a 500 fetching the releases list is transient")
    func releasesListFailureIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesListURL, data: Data(), statusCode: 500)
        let source = ObsidianChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
