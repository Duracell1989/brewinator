import Foundation
import Testing

@testable import Brewinator

private let releasesURL = URL(string: "https://data.services.jetbrains.com/products/releases?code=TBA")!

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: ["jetbrains-toolbox": "TBA"],
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

private func toolboxPackage(current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "jetbrains-toolbox", installedVersion: "3.6.3", currentVersion: current, kind: .cask)
}

@Suite("JetBrainsProducts")
struct JetBrainsProductsTests {
    @Test("canHandle is true only for a name registered in jetbrainsCodes")
    func canHandle() {
        let source = JetBrainsProducts(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(toolboxPackage(current: "3.6.4")))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("exact version match: whatsnew is reduced to text and notesLink appended")
    func exactVersionMatch() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesURL, data: try Fixture.data("jetbrains-releases-sample", extension: "json"), statusCode: 200)
        let source = JetBrainsProducts(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(toolboxPackage(current: "3.6.4"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Toolbox App 3.6.4 Update"))
        #expect(notes.markdown.contains("[Full release notes]"))
    }

    @Test("no matching version falls back to the first entry, still cacheable")
    func fallsBackToFirst() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesURL, data: try Fixture.data("jetbrains-releases-sample", extension: "json"), statusCode: 200)
        let source = JetBrainsProducts(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(toolboxPackage(current: "99.0.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(!notes.markdown.isEmpty)
    }

    @Test("an unknown product code (empty releases array) is a cacheable no-match message")
    func unknownCodeIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: releasesURL, string: "{}", statusCode: 200)
        let source = JetBrainsProducts(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(toolboxPackage(current: "3.6.4"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No matching release in the JetBrains feed"))
    }

    @Test("a network error is transient")
    func networkErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(releasesURL)
        let source = JetBrainsProducts(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(toolboxPackage(current: "3.6.4"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
