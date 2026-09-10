import Foundation
import Testing

@testable import Brewinator

private let changelogURL = URL(string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md")!
private let protonPassURL = URL(string: "https://raw.githubusercontent.com/ProtonMail/WebClients/main/applications/pass-desktop/CHANGELOG.md")!

private let testDatabase = ResolutionDatabase(
    forgeHosts: [],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: ["claude-code": changelogURL, "proton-pass": protonPassURL],
    newsFileSources: [:],
    gitlabStubPattern: "^the .* release\\.?$",
    gitlabStubMaxLength: 30,
    gitlabNewsFiles: [],
    downloadHostForges: [],
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

private func claudeCodePackage(current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "claude-code", installedVersion: "2.1.231", currentVersion: current, kind: .formula)
}

private func protonPassPackage(current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "proton-pass", installedVersion: "1.40.0", currentVersion: current, kind: .cask)
}

@Suite("MarkdownChangelog")
struct MarkdownChangelogTests {
    @Test("canHandle is true only for a name registered in markdownChangelogSources")
    func canHandle() {
        let source = MarkdownChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(claudeCodePackage(current: "2.1.232")))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("exact version section is extracted, heading included, stopping before the next heading")
    func extractsExactSection() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, data: try Fixture.data("claude-code-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(claudeCodePackage(current: "2.1.231"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("## 2.1.231"))
        #expect(!notes.markdown.contains("## 2.1.232"))
        #expect(notes.markdown.contains("[Full changelog](\(changelogURL.absoluteString))"))
    }

    @Test("no matching version falls back to the newest (first) section")
    func fallsBackToNewestSection() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, data: try Fixture.data("claude-code-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(claudeCodePackage(current: "99.0.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("## 2.1.232"))
    }

    @Test("a network error is transient")
    func networkErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(changelogURL)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(claudeCodePackage(current: "2.1.231"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("no changelog headings at all is a cacheable no-entry message")
    func noHeadingsIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: changelogURL, string: "Just some prose, no version headings.", statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(claudeCodePackage(current: "2.1.231"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No changelog entry found"))
    }

    @Test("a `### Version X` heading is recognised and its section extracted")
    func extractsVersionWordHeadingSection() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: protonPassURL, data: try Fixture.data("proton-pass-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(protonPassPackage(current: "1.40.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### Version 1.40.0"))
        #expect(notes.markdown.contains("Pass Monitor"))
        #expect(!notes.markdown.contains("### Version 1.40.2"))
        #expect(!notes.markdown.contains("Check for updates"))
    }

    @Test("no matching version falls back to the newest `### Version X` section")
    func versionWordHeadingFallsBackToNewestSection() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: protonPassURL, data: try Fixture.data("proton-pass-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(protonPassPackage(current: "99.0.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### Version 1.40.2"))
        #expect(!notes.markdown.contains("Pass Monitor"))
    }

    @Test("a non-version subheading does not cut a section short")
    func nonVersionSubheadingIsNotAHeading() async {
        var fetcher = FakeHTTPFetcher()
        let changelog = """
            # Changelog

            ## 2.1.231

            ### Breaking changes

            - Something changed

            ## 2.1.230

            - Older entry
            """
        fetcher.respond(to: changelogURL, string: changelog, statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(claudeCodePackage(current: "2.1.231"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### Breaking changes"))
        #expect(notes.markdown.contains("Something changed"))
        #expect(!notes.markdown.contains("Older entry"))
    }
}
