import Foundation

/// A tag-compare spec for upstreams that tag every release but publish no
/// release bodies — notes are reconstructed from the commit log between two
/// tags.
struct TagCompareSpec: Sendable, Equatable, Codable {
    let repo: String
    let tagTemplate: String
    let subpath: String?
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
        gitlabStubPattern: "^the .* release\\.?$",
        gitlabStubMaxLength: 30,
        gitlabNewsFiles: ["NEWS", "NEWS.md", "ChangeLog.md"],
        firefoxNotesURLTemplate: "https://www.firefox.com/en-US/firefox/%s/releasenotes/",
        ffmpegChangelogURLTemplate: "https://raw.githubusercontent.com/FFmpeg/FFmpeg/%s/Changelog",
        dotnetReleasesURLTemplate: "https://builds.dotnet.microsoft.com/dotnet/release-metadata/%s/releases.json",
        dotnetNotableChangesHeading: "### Notable Changes",
        windowsAppURL: URL(string: "https://learn.microsoft.com/en-us/windows-app/whats-new")!,
        claudeDesktopChangelogURL: URL(string: "https://claude.com/docs/cowork/changelog.md")!,
        obsidianRepo: "obsidianmd/obsidian-releases",
        androidStudioFeedURL: URL(string: "https://androidstudio.googleblog.com/feeds/posts/default?alt=json&max-results=25")!
    )
}
