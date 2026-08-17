import Foundation
import Testing

@testable import Brewinator

private let branchURL = URL(string: "https://example.test/ffmpeg/release/8.1/Changelog")!
private let branch90URL = URL(string: "https://example.test/ffmpeg/release/9.0/Changelog")!
private let fallbackBranchURL = URL(string: "https://example.test/ffmpeg/master/Changelog")!

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
    ffmpegChangelogURLTemplate: "https://example.test/ffmpeg/%s/Changelog",
    dotnetReleasesURLTemplate: "",
    dotnetNotableChangesHeading: "",
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(current: String = "8.1.2", installed: String = "8.1.1") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "ffmpeg", installedVersion: installed, currentVersion: current, kind: .formula)
}

@Suite("FFmpegChangelog")
struct FFmpegChangelogTests {
    @Test("canHandle matches ffmpeg and its @-versioned formulae")
    func canHandle() {
        let source = FFmpegChangelog(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(source.canHandle(OutdatedPackageInfo(name: "ffmpeg@6", installedVersion: "6.0", currentVersion: "6.1", kind: .formula)))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("real fixture: point release found on the release branch, master never tried")
    func branchHasSection() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: branchURL, data: try Fixture.data("ffmpeg-changelog-branch-sample", extension: "txt"), statusCode: 200)
        let source = FFmpegChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("swscale/x86/rgb_2_rgb"))
        #expect(notes.markdown.contains("[Full Changelog](\(branchURL.absoluteString))"))
    }

    @Test("branch 404s, falls through to master, which lacks the point-release section — cacheable stub")
    func branchNotFoundFallsBackToDefaultBranch() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: branch90URL, data: Data(), statusCode: 404)
        fetcher.respond(to: fallbackBranchURL, data: try Fixture.data("ffmpeg-changelog-master-sample", extension: "txt"), statusCode: 200)
        let source = FFmpegChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "9.0.5", installed: "9.0.4"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("_No Changelog section for 9.0.5"))
        #expect(notes.markdown.contains(fallbackBranchURL.absoluteString))
    }

    @Test("a non-404 failure on the branch is transient immediately, master is never attempted")
    func nonNotFoundBranchFailureIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: branchURL, data: Data(), statusCode: 500)
        fetcher.respond(to: fallbackBranchURL, string: "version 8.1.2:\nshould never be read\n", statusCode: 200)
        let source = FFmpegChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("branch 200s but doesn't contain the target section: master is still tried")
    func branchFoundButNoMatchTriesDefaultBranch() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: branch90URL, string: "version 8.1.1:\nold stuff\n", statusCode: 200)
        fetcher.respond(to: fallbackBranchURL, string: "version 9.0:\nnext-gen changes\n", statusCode: 200)
        let source = FFmpegChangelog(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(current: "9.0", installed: "8.1.1"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("next-gen changes"))
    }
}
