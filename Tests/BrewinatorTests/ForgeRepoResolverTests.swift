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
    newsFileSources: [:],
    gitlabStubPattern: "^the .* release\\.?$",
    gitlabStubMaxLength: 30,
    gitlabNewsFiles: [],
    downloadHostForges: [
        DownloadHostForge(downloadPrefix: "downloads.example.org/sources/", forgeHost: "gitlab.example.org", owner: "GNOME"),
        DownloadHostForge(downloadPrefix: "downloads.nowhere.example/sources/", forgeHost: "svn.example.org", owner: "GNOME"),
    ],
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

private func package(_ name: String, stableURL: String? = nil, homepage: String? = nil, headURL: String? = nil) -> OutdatedPackageInfo {
    OutdatedPackageInfo(
        name: name,
        installedVersion: "1.0.0",
        currentVersion: "1.1.0",
        kind: .formula,
        stableURL: stableURL,
        homepage: homepage,
        headURL: headURL
    )
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

    /// poppler's shape: tarball and homepage both on poppler.freedesktop.org,
    /// the forge named only in `head do`.
    @Test("falls back to the head URL when neither the stable URL nor the homepage exposes a forge repo")
    func headURLScan() {
        let repo = ForgeRepoResolver.resolve(
            package: package(
                "poppler",
                stableURL: "https://poppler.freedesktop.org/poppler-26.09.0.tar.xz",
                homepage: "https://poppler.freedesktop.org/",
                headURL: "https://gitlab.example.org/poppler/poppler.git"
            ),
            database: testDatabase
        )
        #expect(repo?.host == "gitlab.example.org")
        #expect(repo?.ownerRepo == "poppler/poppler")
        #expect(repo?.dialect == .gitlab)
    }

    /// The head URL is the development remote, which for a mirror need not be
    /// where releases are published — so it must never outrank the other two.
    @Test("the stable URL and the homepage both outrank the head URL")
    func headURLRanksLast() {
        let viaStable = ForgeRepoResolver.resolve(
            package: package(
                "tool",
                stableURL: "https://github.com/owner/from-stable/archive/v1.tar.gz",
                headURL: "https://github.com/owner/from-head.git"
            ),
            database: testDatabase
        )
        #expect(viaStable?.repo == "from-stable")

        let viaHomepage = ForgeRepoResolver.resolve(
            package: package("tool", homepage: "https://github.com/owner/from-homepage", headURL: "https://github.com/owner/from-head.git"),
            database: testDatabase
        )
        #expect(viaHomepage?.repo == "from-homepage")
    }

    @Test("no override, no stable URL, no homepage, no head URL resolves to nil")
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

    /// librsvg's shape: the tarball names the project, nothing names the forge,
    /// and there is no `head do` to fall back on.
    @Test("derives the repo from a download host when no URL names a forge")
    func downloadHostDerivation() {
        let repo = ForgeRepoResolver.resolve(
            package: package(
                "librsvg",
                stableURL: "https://downloads.example.org/sources/librsvg/2.63/librsvg-2.63.0.tar.xz",
                homepage: "https://wiki.example.org/Projects/LibRsvg"
            ),
            database: testDatabase
        )
        #expect(repo?.host == "gitlab.example.org")
        #expect(repo?.ownerRepo == "GNOME/librsvg")
        #expect(repo?.dialect == .gitlab)
    }

    /// pango's shape: same download host as librsvg, but it names its repo in
    /// `head do`. A URL that says where the repo is always beats a guess from
    /// the download path.
    @Test("a head URL outranks the download-host derivation")
    func downloadHostDerivationRanksLast() {
        let repo = ForgeRepoResolver.resolve(
            package: package(
                "pango-head",
                stableURL: "https://downloads.example.org/sources/pango/1.58/pango-1.58.2.tar.xz",
                headURL: "https://gitlab.example.org/Fork/pango.git"
            ),
            database: testDatabase
        )
        #expect(repo?.ownerRepo == "Fork/pango")
    }

    @Test("a download host mapped to a forge host that isn't known resolves to nil")
    func downloadHostDerivationRequiresKnownForge() {
        let repo = ForgeRepoResolver.resolve(
            package: package("thing", stableURL: "https://downloads.nowhere.example/sources/thing/1.0/thing-1.0.tar.xz"),
            database: testDatabase
        )
        #expect(repo == nil)
    }

    @Test("an unmapped download host resolves to nil rather than guessing")
    func downloadHostDerivationIgnoresUnmappedHosts() {
        let repo = ForgeRepoResolver.resolve(
            package: package("thing", stableURL: "https://cdn.example.com/sources/thing/1.0/thing-1.0.tar.xz"),
            database: testDatabase
        )
        #expect(repo == nil)
    }
}
