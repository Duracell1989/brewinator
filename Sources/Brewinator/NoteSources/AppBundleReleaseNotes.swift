import Foundation

/// Last-resort notes read out of the cask's own installed `.app`, for vendors
/// who publish no changelog anywhere a forge, a feed or a vendor page can
/// reach - Proton being the case that prompted it. Two signals, in order:
///
/// 1. `Contents/Resources/ReleaseNotes.html`, the cumulative changelog Sparkle
///    shows in its update dialog. The target version's section only; an older
///    bundle that predates the update contributes nothing.
/// 2. `SUFeedURL` from `Contents/Info.plist` - the app's own appcast,
///    discovered rather than configured, which often carries the notes inline
///    in each item's `<description>`.
///
/// Registered **last**, so it can only ever displace the "no forge repo
/// detected" placeholder. That position is deliberate: plenty of Sparkle apps
/// also publish GitHub releases, and those are the better source.
///
/// The bundle is usually *behind* the version being resolved, since Homebrew
/// reports the upgrade before it installs it. It is ahead exactly for
/// `auto_updates` casks - which self-update through Sparkle and are only
/// reported at all because `brew outdated --greedy` includes them - and those
/// are the ones this source exists for.
struct AppBundleReleaseNotes: NoteSource {
    private let locator: AppBundleLocating
    private let reader: SparkleAppcastReader

    init(locator: AppBundleLocating, httpFetcher: HTTPFetching) {
        self.locator = locator
        reader = SparkleAppcastReader(httpFetcher: httpFetcher)
    }

    /// Locates twice per package, once here and once in `fetch` - two small
    /// local reads, and only for the casks that reach the end of the chain.
    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        bundle(for: package) != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let bundle = bundle(for: package) else {
            return .success(Resolver.noForgeDetected)
        }

        if let section = bundledSection(in: bundle, version: package.cleanCurrentVersion) {
            let provenance = "_Read from the installed app bundle — \(bundle.path)_\n\n"
            return .success(ReleaseNotes(markdown: MarkdownSection.body(section, maxLines: 40) + provenance))
        }

        guard let feed = bundle.sparkleFeedURL else {
            return .success(Resolver.noForgeDetected)
        }
        return await reader.notes(feed: feed, targetVersion: package.cleanCurrentVersion)
    }

    /// The target version's own section of the bundled changelog, or nil when
    /// the app ships none or has not reached that version yet.
    private func bundledSection(in bundle: InstalledAppBundle, version: String) -> String? {
        guard let html = bundle.releaseNotesHTML else { return nil }
        return VersionSectionExtractor.section(for: version, in: HTMLTextReducer.reduce(html))
    }

    /// Formulae never have one; only casks stage an `.app`.
    private func bundle(for package: OutdatedPackageInfo) -> InstalledAppBundle? {
        guard package.kind == .cask else { return nil }
        return locator.bundle(forCask: package.name, installedVersion: package.installedVersion)
    }
}
