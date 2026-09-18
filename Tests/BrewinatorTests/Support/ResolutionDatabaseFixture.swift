import Foundation

@testable import Brewinator

extension ResolutionDatabase {
    /// A baseline for note-source tests: every lookup table empty, every
    /// template inert, and the non-optional URLs pointed at `example.test` so
    /// a source that reaches for one it should not have used fails visibly
    /// rather than hitting the network.
    ///
    /// It exists so that adding a field to `ResolutionDatabase` is a one-line
    /// change here instead of an identical edit in every test file. Before
    /// this, 17 files hand-built the memberwise initialiser and each new field
    /// cost a repo-wide mechanical sweep - which is how `gnuPatchProjects: [:]`
    /// ended up in 16 files that never read it.
    ///
    /// The GitLab stub values are the production ones rather than zero values:
    /// stub detection is meaningless without them, and every test that touched
    /// them was copying the same two literals anyway.
    static let testDefaults = ResolutionDatabase(
        forgeHosts: [],
        repoOverrides: [:],
        tagCompareSpecs: [:],
        sparkleFeeds: [:],
        jetbrainsCodes: [:],
        markdownChangelogSources: [:],
        newsFileSources: [:],
        gnuPatchProjects: [:],
        gitlabStubPattern: "^the .* release\\.?$",
        gitlabStubMaxLength: 30,
        gitlabNewsFiles: [],
        downloadHostForges: [],
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

    /// Copy with selected fields replaced. Every parameter defaults to the
    /// receiver's own value, so a test names only what it actually exercises.
    func with(
        forgeHosts: [ForgeHost]? = nil,
        repoOverrides: [String: String]? = nil,
        tagCompareSpecs: [String: TagCompareSpec]? = nil,
        sparkleFeeds: [String: URL]? = nil,
        jetbrainsCodes: [String: String]? = nil,
        markdownChangelogSources: [String: URL]? = nil,
        newsFileSources: [String: NewsFileSpec]? = nil,
        gnuPatchProjects: [String: GNUPatchSpec]? = nil,
        gitlabStubPattern: String? = nil,
        gitlabStubMaxLength: Int? = nil,
        gitlabNewsFiles: [String]? = nil,
        downloadHostForges: [DownloadHostForge]? = nil,
        firefoxNotesURLTemplate: String? = nil,
        ffmpegChangelogURLTemplate: String? = nil,
        dotnetReleasesURLTemplate: String? = nil,
        dotnetNotableChangesHeading: String? = nil,
        nssNotesURLTemplate: String? = nil,
        windowsAppURL: URL? = nil,
        claudeDesktopChangelogURL: URL? = nil,
        obsidianRepo: String? = nil,
        androidStudioFeedURL: URL? = nil
    ) -> ResolutionDatabase {
        ResolutionDatabase(
            forgeHosts: forgeHosts ?? self.forgeHosts,
            repoOverrides: repoOverrides ?? self.repoOverrides,
            tagCompareSpecs: tagCompareSpecs ?? self.tagCompareSpecs,
            sparkleFeeds: sparkleFeeds ?? self.sparkleFeeds,
            jetbrainsCodes: jetbrainsCodes ?? self.jetbrainsCodes,
            markdownChangelogSources: markdownChangelogSources ?? self.markdownChangelogSources,
            newsFileSources: newsFileSources ?? self.newsFileSources,
            gnuPatchProjects: gnuPatchProjects ?? self.gnuPatchProjects,
            gitlabStubPattern: gitlabStubPattern ?? self.gitlabStubPattern,
            gitlabStubMaxLength: gitlabStubMaxLength ?? self.gitlabStubMaxLength,
            gitlabNewsFiles: gitlabNewsFiles ?? self.gitlabNewsFiles,
            downloadHostForges: downloadHostForges ?? self.downloadHostForges,
            firefoxNotesURLTemplate: firefoxNotesURLTemplate ?? self.firefoxNotesURLTemplate,
            ffmpegChangelogURLTemplate: ffmpegChangelogURLTemplate ?? self.ffmpegChangelogURLTemplate,
            dotnetReleasesURLTemplate: dotnetReleasesURLTemplate ?? self.dotnetReleasesURLTemplate,
            dotnetNotableChangesHeading: dotnetNotableChangesHeading ?? self.dotnetNotableChangesHeading,
            nssNotesURLTemplate: nssNotesURLTemplate ?? self.nssNotesURLTemplate,
            windowsAppURL: windowsAppURL ?? self.windowsAppURL,
            claudeDesktopChangelogURL: claudeDesktopChangelogURL ?? self.claudeDesktopChangelogURL,
            obsidianRepo: obsidianRepo ?? self.obsidianRepo,
            androidStudioFeedURL: androidStudioFeedURL ?? self.androidStudioFeedURL
        )
    }
}
