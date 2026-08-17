import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase(
    forgeHosts: [
        ForgeHost(host: "github.com", dialect: .github),
        ForgeHost(host: "gitea.example.org", dialect: .gitea),
        ForgeHost(host: "gitlab.example.org", dialect: .gitlab),
    ],
    repoOverrides: [
        "node": "nodejs/node",
        "pango": "gitlab.example.org/GNOME/pango",
    ],
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
    windowsAppURL: URL(string: "https://example.test/windows-app")!,
    claudeDesktopChangelogURL: URL(string: "https://example.test/claude")!,
    obsidianRepo: "",
    androidStudioFeedURL: URL(string: "https://example.test/android-studio")!
)

private func package(_ name: String, stableURL: String? = nil, homepage: String? = nil) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: name, installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .formula, stableURL: stableURL, homepage: homepage)
}

@Suite("ForgeRepoResolver")
struct ForgeRepoResolverTests {
    @Test("override (owner/repo form, github.com assumed) wins even when the stable URL points elsewhere")
    func overrideWins() {
        let repo = ForgeRepoResolver.resolve(package: package("node", stableURL: "https://nodejs.org/dist/v1.tar.xz"), database: testDatabase)
        #expect(repo?.host == "github.com")
        #expect(repo?.ownerRepo == "nodejs/node")
        #expect(repo?.dialect == .github)
    }

    @Test("override in host/owner/repo form resolves the correct dialect")
    func overrideHostForm() {
        let repo = ForgeRepoResolver.resolve(package: package("pango"), database: testDatabase)
        #expect(repo?.host == "gitlab.example.org")
        #expect(repo?.owner == "GNOME")
        #expect(repo?.repo == "pango")
        #expect(repo?.dialect == .gitlab)
    }

    @Test("falls back to scanning the stable URL when no override exists")
    func stableURLScan() {
        let repo = ForgeRepoResolver.resolve(
            package: package("foo", stableURL: "https://github.com/foo-owner/foo-repo/archive/v1.2.3.tar.gz"),
            database: testDatabase
        )
        #expect(repo?.ownerRepo == "foo-owner/foo-repo")
        #expect(repo?.dialect == .github)
    }

    @Test("falls back to the homepage when the stable URL doesn't expose a forge repo")
    func homepageScan() {
        let repo = ForgeRepoResolver.resolve(
            package: package("foo", stableURL: "https://cdn.example.com/foo.tar.gz", homepage: "https://gitea.example.org/foo/foo"),
            database: testDatabase
        )
        #expect(repo?.host == "gitea.example.org")
        #expect(repo?.dialect == .gitea)
    }

    @Test("a host not in forgeHosts is rejected even though it looks like owner/repo")
    func unknownHostRejected() {
        let repo = ForgeRepoResolver.resolve(package: package("foo", stableURL: "https://example.com/foo/foo"), database: testDatabase)
        #expect(repo == nil)
    }

    @Test("no override, no stable URL, no homepage resolves to nil")
    func nothingResolves() {
        #expect(ForgeRepoResolver.resolve(package: package("foo"), database: testDatabase) == nil)
    }

    @Test("scan matches a non-lowercase host, unlike split() this must not be case-sensitive")
    func scanIsCaseInsensitive() {
        let repo = ForgeRepoResolver.resolve(
            package: package("foo", stableURL: "https://GitHub.com/foo-owner/foo-repo/archive/v1.2.3.tar.gz"),
            database: testDatabase
        )
        #expect(repo?.ownerRepo == "foo-owner/foo-repo")
        #expect(repo?.dialect == .github)
    }

    @Test("scan strips a trailing .git off the repo, unlike split() this currently doesn't")
    func scanStripsTrailingGit() {
        let repo = ForgeRepoResolver.resolve(
            package: package("foo", stableURL: "https://github.com/foo-owner/foo-repo.git"),
            database: testDatabase
        )
        #expect(repo?.repo == "foo-repo")
    }

    @Test("scan requires a real host boundary — a forge host as a substring of a longer domain must not match")
    func scanRequiresHostBoundary() {
        let repo = ForgeRepoResolver.resolve(
            package: package("foo", homepage: "https://docs.gitlab.example.org/ee/user/foo"),
            database: testDatabase
        )
        #expect(repo == nil)
    }
}
