import Foundation
import Testing

@testable import Brewinator

private let changelogURL = URL(string: "https://example.test/claude/changelog.md")!

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
    downloadHostForges: [],
    firefoxNotesURLTemplate: "",
    ffmpegChangelogURLTemplate: "",
    dotnetReleasesURLTemplate: "",
    dotnetNotableChangesHeading: "",
    nssNotesURLTemplate: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: changelogURL,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "1.30096.1") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "claude", installedVersion: "1.28929.0", currentVersion: current, kind: .cask)
}

@Suite("ClaudeDesktopChangelog")
struct ClaudeDesktopChangelogTests {
    @Test("canHandle matches only the claude Desktop cask, not claude-code")
    func canHandle() {
        let source = ClaudeDesktopChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "claude-code", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("real fixture: exact v-prefixed label match extracts that block, capped, with a full-changelog link")
    func realFixtureMatchesExactLabel() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, data: try Fixture.data("claude-desktop-changelog-sample", extension: "md"), statusCode: 200)
        let source = ClaudeDesktopChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("**v1.30096.1** — 2026-08-13"))
        #expect(notes.markdown.contains("Fixed Find (Cmd+F)"))
        #expect(!notes.markdown.contains("v1.28929.0"))
        #expect(notes.markdown.contains("[Full changelog](\(changelogURL.absoluteString))"))
    }

    @Test("no exact label match falls back to the newest (first) block")
    func fallsBackToNewestBlock() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, data: try Fixture.data("claude-desktop-changelog-sample", extension: "md"), statusCode: 200)
        let source = ClaudeDesktopChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "9.99999.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("**v1.30096.1** — 2026-08-13"))
    }

    @Test("a 500 is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, data: Data(), statusCode: 500)
        let source = ClaudeDesktopChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("no Update blocks at all is a cacheable stub")
    func noBlocksIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, string: "# Changelog\n\nNothing here.\n", statusCode: 200)
        let source = ClaudeDesktopChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No changelog entry found"))
    }
}
