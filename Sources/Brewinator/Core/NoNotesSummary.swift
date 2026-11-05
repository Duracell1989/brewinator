/// The one archive file that answers "why is there no note for X?": it lists
/// every outdated package that is skipped, with the reason. Without it a
/// skipped package is indistinguishable from a fetch that silently failed.
enum NoNotesSummary {
    /// Has no " (<kind>) - " part, so `FileArchiveStore.prune` never treats it
    /// as a package's note. The leading underscore sorts it above every package
    /// note in an alphabetical file listing (Obsidian's explorer, Finder).
    static let filename = "_Skipped - no release notes.md"

    private static let userReason = "on your skip list"

    /// Nil when no outdated package is skipped, which removes a stale file.
    static func markdown(for packages: [OutdatedPackageInfo], config: UserConfig) -> String? {
        let skipped = packages.filter { config.isSkipped($0.name) }.sorted { ($0.name, $0.kind.rawValue) < ($1.name, $1.kind.rawValue) }
        guard !skipped.isEmpty else { return nil }

        let lines = skipped.map { package in
            let reason = BuiltInSkipList.reason(for: package.name) ?? userReason
            return "- \(package.name) (\(package.kind.rawValue)) \(package.installedVersion) → \(package.currentVersion) - \(reason)"
        }
        return "## Skipped packages - no release notes\n\nOutdated but skipped on purpose - there is nothing to read for them.\n\n"
            + lines.joined(separator: "\n") + "\n"
    }
}
