enum PackageKind: String, Codable, Sendable {
    case formula
    case cask
}

/// A formula and a cask can share the same bare name (e.g. "node" the
/// formula vs a hypothetical "node" cask) — `kind` is what keeps their
/// archived files from being conflated when deciding what to prune.
struct ArchivePackageIdentity: Sendable, Equatable, Hashable {
    let name: String
    let kind: PackageKind
}

struct OutdatedPackageInfo: Sendable, Equatable {
    /// Short name, tap-installed or not — what skip matching, `NoteSource`
    /// predicates and archive filenames all key on.
    let name: String

    /// Tap-qualified name; equals `name` for core formulae and all casks. Sole
    /// consumer is the `brew info` join in `BrewNotesSync.enrich`.
    let fullName: String

    let installedVersion: String
    let currentVersion: String
    let kind: PackageKind

    /// Populated from `brew info --json=v2` (formula: `.urls.stable.url`,
    /// cask: `.url`) — nil until `BrewNotesSync` merges it in. Feeds forge
    /// repo resolution (`ForgeRepoResolver`).
    var stableURL: String?

    /// Populated from `brew info --json=v2`'s `.homepage` — the fallback
    /// forge-repo signal when `stableURL` doesn't expose it.
    var homepage: String?

    var cleanInstalledVersion: String { VersionMatcher.cleanVersion(installedVersion) }
    var cleanCurrentVersion: String { VersionMatcher.cleanVersion(currentVersion) }
    var archiveIdentity: ArchivePackageIdentity { ArchivePackageIdentity(name: name, kind: kind) }

    init(
        name: String,
        installedVersion: String,
        currentVersion: String,
        kind: PackageKind,
        fullName: String? = nil,
        stableURL: String? = nil,
        homepage: String? = nil
    ) {
        self.name = name
        self.fullName = fullName ?? name
        self.installedVersion = installedVersion
        self.currentVersion = currentVersion
        self.kind = kind
        self.stableURL = stableURL
        self.homepage = homepage
    }
}
