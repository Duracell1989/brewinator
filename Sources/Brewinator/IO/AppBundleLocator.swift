import Foundation

/// What an installed `.app` can contribute to release notes, read eagerly so
/// no filesystem access leaks into the note sources.
struct InstalledAppBundle: Sendable, Equatable {
    /// Absolute path of the resolved bundle - the provenance line in the
    /// archived note.
    let path: String

    /// `Contents/Resources/ReleaseNotes.html`: the cumulative, version-headed
    /// changelog Sparkle renders in its update dialog. Nil when the app ships
    /// none.
    let releaseNotesHTML: String?

    /// `SUFeedURL` from `Contents/Info.plist`: the app's own Sparkle appcast,
    /// discovered from the bundle rather than configured in
    /// `ResolutionDatabase.sparkleFeeds`.
    let sparkleFeedURL: URL?

    /// Nothing to say is the same as not being there - the locator returns nil
    /// rather than an empty bundle.
    var hasNotes: Bool { releaseNotesHTML != nil || sparkleFeedURL != nil }
}

protocol AppBundleLocating: Sendable {
    /// Nil when the cask stages no `.app`, or when the one it stages carries
    /// neither bundled notes nor a Sparkle feed.
    func bundle(forCask token: String, installedVersion: String) -> InstalledAppBundle?
}

/// Finds a cask's installed app through the Caskroom, which keeps a symlink to
/// wherever the app artifact was moved (`/Applications/Foo.app`, `~/Applications`,
/// a renamed target) - so no `brew info` artifact parsing is needed, and a cask
/// whose app lives outside `/Applications` still resolves.
struct CaskroomAppBundleLocator: AppBundleLocating {
    private let caskroomPath: String

    /// Defaults to the Apple Silicon Homebrew prefix, matching
    /// `ProcessBrewClient.brewPath`. Injectable for Intel (`/usr/local`) and
    /// for tests.
    init(caskroomPath: String = "/opt/homebrew/Caskroom") {
        self.caskroomPath = caskroomPath
    }

    func bundle(forCask token: String, installedVersion: String) -> InstalledAppBundle? {
        for directory in versionDirectories(forCask: token, installedVersion: installedVersion) {
            for app in appBundles(in: directory) {
                let bundle = read(app)
                if bundle.hasNotes { return bundle }
            }
        }
        return nil
    }

    /// The installed version's staging directory first - that is the one whose
    /// app is actually linked into place. Other versions follow only as a
    /// fallback for a Caskroom left inconsistent by an interrupted upgrade.
    private func versionDirectories(forCask token: String, installedVersion: String) -> [String] {
        let root = "\(caskroomPath)/\(token)"
        let installed = "\(root)/\(installedVersion)"
        let others = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .filter { !$0.hasPrefix(".") && $0 != installedVersion }
            .sorted(by: >)
            .map { "\(root)/\($0)" }
        return [installed] + others
    }

    private func appBundles(in directory: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [])
            .filter { $0.hasSuffix(".app") }
            .sorted()
            .map { "\(directory)/\($0)" }
    }

    /// Reads through the Caskroom symlink to the real bundle, so the recorded
    /// path is the app's actual location rather than the staging alias.
    private func read(_ appPath: String) -> InstalledAppBundle {
        let resolved = URL(fileURLWithPath: appPath).resolvingSymlinksInPath()
        let notes = try? String(contentsOf: resolved.appendingPathComponent("Contents/Resources/ReleaseNotes.html"), encoding: .utf8)
        return InstalledAppBundle(
            path: resolved.path,
            releaseNotesHTML: notes,
            sparkleFeedURL: sparkleFeedURL(inInfoPlistAt: resolved.appendingPathComponent("Contents/Info.plist"))
        )
    }

    /// `SUFeedURL` is Sparkle's own key, present in every Sparkle-updated app
    /// and absent everywhere else - which makes it both the feed address and
    /// the test for "does this app self-update through Sparkle at all".
    private func sparkleFeedURL(inInfoPlistAt plistURL: URL) -> URL? {
        guard let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let feed = plist["SUFeedURL"] as? String
        else {
            return nil
        }
        return URL(string: feed.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
