import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase(
    forgeHosts: [
        ForgeHost(host: "github.com", dialect: .github),
        ForgeHost(host: "codeberg.org", dialect: .gitea),
        ForgeHost(host: "gitlab.com", dialect: .gitlab),
    ],
    repoOverrides: [:],
    tagCompareSpecs: [:],
    sparkleFeeds: [:],
    jetbrainsCodes: [:],
    markdownChangelogSources: [:],
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

private func batPackage(current: String, installed: String = "0.25.0") -> OutdatedPackageInfo {
    OutdatedPackageInfo(
        name: "bat",
        installedVersion: installed,
        currentVersion: current,
        kind: .formula,
        stableURL: "https://github.com/sharkdp/bat/archive/v\(current).tar.gz"
    )
}

@Suite("ForgeReleases")
struct ForgeReleasesTests {
    @Test("canHandle is true for a package that resolves to a GitHub or Gitea repo, false for GitLab")
    func canHandle() {
        let source = ForgeReleases(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(batPackage(current: "0.26.0")))

        let gitlabPackage = OutdatedPackageInfo(
            name: "foo",
            installedVersion: "1.0.0",
            currentVersion: "1.1.0",
            kind: .formula,
            stableURL: "https://gitlab.com/foo/foo/-/archive/v1.1.0.tar.gz"
        )
        #expect(!source.canHandle(gitlabPackage))
    }

    @Test("GitHub: exact tag match returns that release's body and link")
    func githubExactMatch() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://api.github.com/repos/sharkdp/bat/releases")!,
            data: try Fixture.data("github-releases-sample", extension: "json"),
            statusCode: 200
        )
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(batPackage(current: "0.26.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("sharkdp/bat/releases/tag/v0.26.0"))
    }

    @Test("GitHub: no exact match falls back to the newest release, still cacheable success")
    func githubFallsBackToNewest() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://api.github.com/repos/sharkdp/bat/releases")!,
            data: try Fixture.data("github-releases-sample", extension: "json"),
            statusCode: 200
        )
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(batPackage(current: "9.9.9"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("v0.26.1"))
    }

    @Test("Gitea (Codeberg): exact tag match resolves via the /api/v1 endpoint")
    func giteaExactMatch() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(
            to: URL(string: "https://codeberg.org/api/v1/repos/forgejo/forgejo/releases")!,
            data: try Fixture.data("gitea-releases-sample", extension: "json"),
            statusCode: 200
        )
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let package = OutdatedPackageInfo(
            name: "forgejo",
            installedVersion: "16.0.1",
            currentVersion: "16.0.2",
            kind: .formula,
            stableURL: "https://codeberg.org/forgejo/forgejo/archive/v16.0.2.tar.gz"
        )
        let result = await source.fetch(package)
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("forgejo/forgejo/releases/tag/v16.0.2"))
    }

    @Test("a 404 releases list resolves to the cacheable no-releases message")
    func notFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: URL(string: "https://api.github.com/repos/sharkdp/bat/releases")!, data: Data(), statusCode: 404)
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(batPackage(current: "0.26.0"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No matching release found"))
    }

    @Test("a 500 status is transient, not cached")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: URL(string: "https://api.github.com/repos/sharkdp/bat/releases")!, data: Data(), statusCode: 500)
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(batPackage(current: "0.26.0"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a network error is transient, not cached")
    func networkErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(URL(string: "https://api.github.com/repos/sharkdp/bat/releases")!)
        let source = ForgeReleases(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(batPackage(current: "0.26.0"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
