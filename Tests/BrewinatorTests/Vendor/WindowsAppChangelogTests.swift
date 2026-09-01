import Foundation
import Testing

@testable import Brewinator

private let whatsNewURL = URL(string: "https://example.test/windows-app")!

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
    windowsAppURL: whatsNewURL,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "11.3.8") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "windows-app", installedVersion: "11.3.7", currentVersion: current, kind: .cask)
}

@Suite("WindowsAppChangelog")
struct WindowsAppChangelogTests {
    @Test("canHandle matches only windows-app")
    func canHandle() {
        let source = WindowsAppChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixture: macOS section scoped, exact-version h3 block matched and reduced")
    func realFixtureMatchesExactVersion() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: whatsNewURL, data: try Fixture.data("windows-app-whatsnew-sample", extension: "html"), statusCode: 200)
        let source = WindowsAppChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Teams optimizations"))
        // The h3-boundary state machine must have ended this block before the
        // next <h3 line — content from "Version 11.3.7" must not leak in.
        #expect(!notes.markdown.contains("Personalization section"))
        #expect(notes.markdown.contains("[Full changelog](\(whatsNewURL.absoluteString))"))
    }

    @Test("no exact-version block match falls back to the first (newest) h3 block")
    func fallsBackToFirstBlock() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: whatsNewURL, data: try Fixture.data("windows-app-whatsnew-sample", extension: "html"), statusCode: 200)
        let source = WindowsAppChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "99.9.9"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Teams optimizations"))
    }

    @Test("a 500 is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: whatsNewURL, data: Data(), statusCode: 500)
        let source = WindowsAppChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a page with no macOS tabpanel section is a cacheable stub")
    func noMacOSSectionIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: whatsNewURL,
            string: #"<html><body><section id="tabpanel_2_windows">stuff</section></body></html>"#,
            statusCode: 200
        )
        let source = WindowsAppChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_Could not locate the macOS version-history section"))
    }
}
