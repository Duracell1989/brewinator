import Foundation
import Testing

@testable import Brewinator

private let indexURL = URL(string: "https://example.test/dotnet/10.0/releases.json")!
private let notesURL = URL(string: "https://github.com/dotnet/core/blob/main/release-notes/10.0/10.0.11/10.0.11.md")!
private let rawNotesURL = URL(string: "https://raw.githubusercontent.com/dotnet/core/main/release-notes/10.0/10.0.11/10.0.11.md")!

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
    dotnetReleasesURLTemplate: "https://example.test/dotnet/%s/releases.json",
    dotnetNotableChangesHeading: "### Notable Changes",
    nssNotesURLTemplate: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "10.0.400") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "dotnet-sdk", installedVersion: "10.0.303", currentVersion: current, kind: .cask)
}

@Suite("DotnetSdkReleaseNotes")
struct DotnetSdkReleaseNotesTests {
    @Test("canHandle matches dotnet-sdk and its @-versioned casks")
    func canHandle() {
        let source = DotnetSdkReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(source.canHandle(OutdatedPackageInfo(name: "dotnet-sdk@9", installedVersion: "9.0.1", currentVersion: "9.0.2", kind: .cask)))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixture: SDK version matched via releases.json, blob URL rewritten to raw, Notable Changes extracted with the page title prepended")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: indexURL, data: try Fixture.data("dotnet-sdk-releases-sample", extension: "json"), statusCode: 200)
        fetcher.respond(to: rawNotesURL, data: try Fixture.data("dotnet-sdk-release-notes-sample", extension: "md"), statusCode: 200)
        let source = DotnetSdkReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("**.NET 10.0.11 - August 11, 2026**"))
        #expect(notes.markdown.contains("CVE-2026-62898"))
        #expect(!notes.markdown.contains("Visual Studio Compatibility"))
        #expect(notes.markdown.contains("[Full release notes](\(notesURL.absoluteString))"))
    }

    @Test("a match via the sdks[] array (not the top-level sdk field) also resolves")
    func matchesViaSdksArray() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: indexURL, data: try Fixture.data("dotnet-sdk-releases-sample", extension: "json"), statusCode: 200)
        fetcher.respond(to: rawNotesURL, data: try Fixture.data("dotnet-sdk-release-notes-sample", extension: "md"), statusCode: 200)
        let source = DotnetSdkReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "10.0.111"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("CVE-2026-62898"))
    }

    @Test("no release lists the SDK version — cacheable stub, not transient")
    func noMatchIsCacheable() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: indexURL, data: try Fixture.data("dotnet-sdk-releases-sample", extension: "json"), statusCode: 200)
        let source = DotnetSdkReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "10.0.999"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No release matching SDK 10.0.999"))
    }

    @Test("a 500 fetching the index is transient")
    func indexFetchFailureIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: indexURL, data: Data(), statusCode: 500)
        let source = DotnetSdkReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a code block containing a leading # comment doesn't end the Notable Changes section early")
    func fenceAwareExtraction() async throws {
        let markdown = """
            # .NET 1.0.0

            ### Notable Changes

            Some fix.

            ```console
            # this looks like a heading but is inside a fence
            $ dotnet --version
            ```

            More notes after the fence.

            ### Next Section

            Not included.
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://example.test/dotnet/1.0/releases.json")!,
            string: #"{"releases":[{"release-notes":"https://github.com/dotnet/core/blob/main/x.md","sdk":{"version":"1.0.100"}}]}"#,
            statusCode: 200
        )
        fetcher.respond(to: URL(string: "https://raw.githubusercontent.com/dotnet/core/main/x.md")!, string: markdown, statusCode: 200)
        let source = DotnetSdkReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "1.0.100"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("this looks like a heading but is inside a fence"))
        #expect(notes.markdown.contains("More notes after the fence."))
        #expect(!notes.markdown.contains("Not included."))
    }
}
