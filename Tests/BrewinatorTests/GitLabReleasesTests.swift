import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase(
    forgeHosts: [
        ForgeHost(host: "gitlab.com", dialect: .gitlab),
        ForgeHost(host: "gitlab.example.org", dialect: .gitlab),
        ForgeHost(host: "github.com", dialect: .github),
    ],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
    newsFileSources: [:],
    gitlabStubPattern: "^the .* release\\.?$",
    gitlabStubMaxLength: 30,
    gitlabNewsFiles: ["NEWS", "NEWS.md", "ChangeLog.md"],
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

private func runnerPackage(current: String, installed: String = "19.0.3") -> OutdatedPackageInfo {
    OutdatedPackageInfo(
        name: "gitlab-runner",
        installedVersion: installed,
        currentVersion: current,
        kind: .formula,
        stableURL: "https://gitlab.com/gitlab-org/gitlab-runner/-/archive/v\(current)/gitlab-runner-v\(current).tar.gz"
    )
}

private func pangoPackage(current: String, installed: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(
        name: "pango",
        installedVersion: installed,
        currentVersion: current,
        kind: .formula,
        stableURL: "https://gitlab.example.org/GNOME/pango/-/archive/\(current)/pango-\(current).tar.xz"
    )
}

@Suite("GitLabReleases")
struct GitLabReleasesTests {
    @Test("canHandle is true only for a package that resolves to a GitLab-dialect host")
    func canHandle() {
        let source = GitLabReleases(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(runnerPackage(current: "19.2.2")))

        let githubPackage = OutdatedPackageInfo(
            name: "foo",
            installedVersion: "1.0.0",
            currentVersion: "1.1.0",
            kind: .formula,
            stableURL: "https://github.com/foo/foo/archive/v1.1.0.tar.gz"
        )
        #expect(!source.canHandle(githubPackage))
    }

    @Test("a real (non-stub) description is used as-is, with the release's self link")
    func realDescriptionUsedDirectly() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases")!,
            data: try Fixture.data("gitlab-releases-sample", extension: "json"),
            statusCode: 200
        )
        let source = GitLabReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(runnerPackage(current: "19.2.2"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("See [the changelog]"))
        #expect(notes.markdown.contains("gitlab-runner/-/releases/v19.2.2"))
    }

    @Test("a stub description falls back to the NEWS file, extracting the range down to (excluding) the installed version")
    func stubDescriptionFallsBackToNews() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://gitlab.example.org/api/v4/projects/GNOME%2Fpango/releases")!,
            data: try Fixture.data("gitlab-releases-stub-sample", extension: "json"),
            statusCode: 200
        )
        fetcher.respond(
            to: URL(string: "https://gitlab.example.org/GNOME/pango/-/raw/1.58.2/NEWS")!,
            data: try Fixture.data("gitlab-news-sample", extension: "txt"),
            statusCode: 200
        )
        let source = GitLabReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(pangoPackage(current: "1.58.2", installed: "1.58.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Overview of changes in 1.58.2"))
        #expect(notes.markdown.contains("Overview of changes in 1.58.1"))
        #expect(notes.markdown.contains("Fix a crash when shaping empty runs"))
        // Range stops *before* the installed version's own heading.
        #expect(!notes.markdown.contains("Overview of changes in 1.58.0"))
        #expect(notes.markdown.contains("NEWS at 1.58.2"))
    }

    @Test("a 404 releases list resolves to the cacheable no-releases message")
    func notFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases")!,
            data: Data(),
            statusCode: 404
        )
        let source = GitLabReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(runnerPackage(current: "19.2.2"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No releases published"))
    }

    @Test("a 500 status is transient, not cached")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://gitlab.com/api/v4/projects/gitlab-org%2Fgitlab-runner/releases")!,
            data: Data(),
            statusCode: 500
        )
        let source = GitLabReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(runnerPackage(current: "19.2.2"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
