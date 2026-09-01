import Foundation

/// A tag-compare spec for upstreams that tag every release but publish no
/// release bodies — notes are reconstructed from the commit log between two
/// tags.
struct TagCompareSpec: Sendable, Equatable, Codable {
    let repo: String
    let tagTemplate: String
    let subpath: String?
}

/// A `NEWS`-file source for an upstream that keeps well-structured release
/// notes in-tree but publishes nothing a forge API can return.
struct NewsFileSpec: Sendable, Equatable, Codable {
    let url: URL
    let headingStyle: NewsHeadingStyle
}

/// The public half of the config split - where release notes actually live for
/// each supported package. The private half is `UserConfig`.
///
/// Swift literals rather than a bundled JSON resource: it changes only
/// alongside code and gets compile-time checking. `Codable` is speculative -
/// nothing decodes this today.
struct ResolutionDatabase: Sendable, Equatable, Codable {
    let forgeHosts: [ForgeHost]
    let repoOverrides: [String: String]
    let tagCompareSpecs: [String: TagCompareSpec]
    let sparkleFeeds: [String: URL]
    let jetbrainsCodes: [String: String]
    let markdownChangelogSources: [String: URL]
    let newsFileSources: [String: NewsFileSpec]
    let gitlabStubPattern: String
    let gitlabStubMaxLength: Int
    let gitlabNewsFiles: [String]

    /// %s = exact target version.
    let firefoxNotesURLTemplate: String
    /// %s = git ref (`release/<major.minor>` or `master`).
    let ffmpegChangelogURLTemplate: String
    /// %s = channel (major.minor).
    let dotnetReleasesURLTemplate: String
    let dotnetNotableChangesHeading: String
    /// %s = exact target version with dots swapped for underscores (`3.128` ->
    /// `3_128`) — the Sphinx page's own filename convention.
    let nssNotesURLTemplate: String
    let windowsAppURL: URL
    /// The `claude` Desktop cask's changelog page.
    let claudeDesktopChangelogURL: URL
    /// `owner/repo`.
    let obsidianRepo: String
    let androidStudioFeedURL: URL

    static let live = ResolutionDatabase(
        forgeHosts: [
            ForgeHost(host: "github.com", dialect: .github),
            ForgeHost(host: "gitea.com", dialect: .gitea),
            ForgeHost(host: "codeberg.org", dialect: .gitea),
            ForgeHost(host: "gitlab.com", dialect: .gitlab),
            ForgeHost(host: "gitlab.gnome.org", dialect: .gitlab),
            ForgeHost(host: "gitlab.freedesktop.org", dialect: .gitlab),
        ],
        repoOverrides: [
            "node": "nodejs/node",
            "signal": "signalapp/Signal-Desktop",
            "pango": "gitlab.gnome.org/GNOME/pango",
        ],
        tagCompareSpecs: [
            // Do not "fix" this back to Proton's own version.json feed: its
            // `ReleaseNotes` array is empty on every release ever published, and
            // `ProtonMail/inbox-desktop` was archived 2025-03 with its source
            // removed. The commit log between tags is the only real source.
            "proton-mail": TagCompareSpec(
                repo: "ProtonMail/WebClients",
                tagTemplate: "proton-inbox-desktop@%s",
                subpath: "applications/inbox-desktop"
            )
        ],
        sparkleFeeds: [
            "vivaldi": URL(string: "https://update.vivaldi.com/update/1.0/public/mac/appcast.xml")!
        ],
        jetbrainsCodes: [
            "jetbrains-toolbox": "TBA"
        ],
        markdownChangelogSources: [
            "claude-code": URL(string: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md")!
        ],
        // The whole GnuPG family resolves through here rather than through
        // `repoOverrides`. Their canonical host is git.gnupg.org, whose gitweb
        // is intermittently offline behind a 429 against scrapers; the official
        // `gpg/*` GitHub mirrors are reachable but publish zero releases, so
        // pointing forge resolution at them would only trade the no-forge
        // placeholder for an empty releases page — and, being an early-return
        // contract, would block this source from ever running. The in-tree NEWS
        // file is the only machine-readable source that actually carries notes.
        // Read from `master` rather than from the release tag: NEWS is cumulative,
        // so one static URL serves every version, and `NewsRangeExtractor` starting
        // at the target version is what keeps the "(unreleased)" section at the top
        // of the file out of the notes.
        newsFileSources: [
            "gnupg": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/gnupg/master/NEWS")!, headingStyle: .gnupg),
            "gpgme": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/gpgme/master/NEWS")!, headingStyle: .gnupg),
            "gpgmepp": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/gpgmepp/master/NEWS")!, headingStyle: .gnupg),
            "libassuan": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/libassuan/master/NEWS")!, headingStyle: .gnupg),
            "libgcrypt": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/libgcrypt/master/NEWS")!, headingStyle: .gnupg),
            "libgpg-error": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/libgpg-error/master/NEWS")!, headingStyle: .gnupg),
            "libksba": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/libksba/master/NEWS")!, headingStyle: .gnupg),
            "npth": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/npth/master/NEWS")!, headingStyle: .gnupg),
            "pinentry": NewsFileSpec(url: URL(string: "https://raw.githubusercontent.com/gpg/pinentry/master/NEWS")!, headingStyle: .gnupg),
        ],
        gitlabStubPattern: "^the .* release\\.?$",
        gitlabStubMaxLength: 30,
        gitlabNewsFiles: ["NEWS", "NEWS.md", "ChangeLog.md"],
        firefoxNotesURLTemplate: "https://www.firefox.com/en-US/firefox/%s/releasenotes/",
        ffmpegChangelogURLTemplate: "https://raw.githubusercontent.com/FFmpeg/FFmpeg/%s/Changelog",
        dotnetReleasesURLTemplate: "https://builds.dotnet.microsoft.com/dotnet/release-metadata/%s/releases.json",
        dotnetNotableChangesHeading: "### Notable Changes",
        nssNotesURLTemplate: "https://firefox-source-docs.mozilla.org/security/nss/releases/nss_%s.html",
        windowsAppURL: URL(string: "https://learn.microsoft.com/en-us/windows-app/whats-new")!,
        claudeDesktopChangelogURL: URL(string: "https://claude.com/docs/cowork/changelog.md")!,
        obsidianRepo: "obsidianmd/obsidian-releases",
        androidStudioFeedURL: URL(string: "https://androidstudio.googleblog.com/feeds/posts/default?alt=json&max-results=25")!
    )
}
