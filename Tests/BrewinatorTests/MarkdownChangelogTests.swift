import Foundation
import Testing

@testable import Brewinator

private let changelogURL = URL(string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md")!
private let protonPassURL = URL(string: "https://raw.githubusercontent.com/ProtonMail/WebClients/main/applications/pass-desktop/CHANGELOG.md")!

private let rustupTemplate = "https://raw.githubusercontent.com/rust-lang/rustup/%s/CHANGELOG.md"
private let rustupTagURL = URL(string: "https://raw.githubusercontent.com/rust-lang/rustup/1.29.3/CHANGELOG.md")!

private let testDatabase = ResolutionDatabase.testDefaults.with(
    markdownChangelogSources: ["claude-code": changelogURL, "proton-pass": protonPassURL],
    taggedChangelogURLTemplates: ["rustup": rustupTemplate]
)

private func rustupPackage(current: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "rustup", installedVersion: "1.29.2", currentVersion: current, kind: .formula)
}

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

    @Test("a tagged template reads the changelog at the release tag, so a patch release absent from `main` is found")
    func taggedTemplateReadsChangelogAtTheTag() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: rustupTagURL, data: try Fixture.data("rustup-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        #expect(source.canHandle(rustupPackage(current: "1.29.3")))
        let result = await source.fetch(rustupPackage(current: "1.29.3"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("## [1.29.3] - 2026-11-03"))
        #expect(notes.markdown.contains("Illegal instruction"))
        #expect(!notes.markdown.contains("rustls-webpki"))
        #expect(notes.markdown.contains("[Full changelog](\(rustupTagURL.absoluteString))"))
    }

    @Test("a bracketed `## [X] - date` heading is recognised, and the section before it is not cut short by link definitions")
    func bracketedDatedHeadingIsRecognised() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: rustupTagURL, data: try Fixture.data("rustup-changelog-sample", extension: "md"), statusCode: 200)
        let source = MarkdownChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(rustupPackage(current: "1.29.3"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[pr#5167]: https://github.com/rust-lang/rustup/pull/5167"))
    }

    @Test("the production database reads rustup's changelog at the version tag")
    func liveDatabaseRegistersRustup() {
        #expect(ResolutionDatabase.live.taggedChangelogURLTemplates["rustup"] == rustupTemplate)
        #expect(ResolutionDatabase.live.tagCompareSpecs["rustup"] == nil)
    }
}
