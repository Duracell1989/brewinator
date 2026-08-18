import Foundation

/// A tag-compare spec for upstreams that tag every release but publish no
/// release bodies — notes are reconstructed from the commit log between two
/// tags.
struct TagCompareSpec: Sendable, Equatable, Codable {
    let repo: String
    let tagTemplate: String
    let subpath: String?
}

/// The curated, public, in-repo half of the config split — "where release
/// notes actually live" for the packages this tool supports. The private
/// half (archive directory, personal skip list) is `UserConfig`.
///
/// Compiled as Swift literals rather than loaded from a bundled JSON
/// resource: this is small, changes only alongside code, and gets
/// compile-time checking that a parsed resource wouldn't. `Codable` is kept
/// for potential future serialization, not because anything decodes it today.
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

    /// The real, curated database: forge hosts, repo overrides, tag-compare
    /// specs, Sparkle feeds, JetBrains codes, GitLab stub/news-file settings,
    /// `claude-code`'s Markdown-changelog entry, and the vendor one-off
    /// constants (Firefox, ffmpeg, dotnet-sdk, Windows App, Claude Desktop,
    /// Obsidian, Android Studio).
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
            // Do not "fix" this back to Proton's own feed
            // (proton.me/download/mail/macos/version.json): its `ReleaseNotes`
            // field is an empty array on every release ever published, and
            // `ProtonMail/inbox-desktop` was archived 2025-03 with its source
            // removed. The app builds from the WebClients monorepo now, so the
            // commit log between tags is the only real source.
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
