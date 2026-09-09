import Foundation

/// The API dialect a forge host speaks — drives both the releases endpoint
/// shape and, for GitLab, the extra NEWS-fallback behaviour.
enum ForgeDialect: String, Sendable, Equatable, Codable {
    case github
    case gitlab
    case gitea
}

/// One entry in `ResolutionDatabase.forgeHosts`. One dialect-tagged list rather
/// than a general list plus a GitLab one, so there is no second array to fall
/// out of sync.
struct ForgeHost: Sendable, Equatable, Codable {
    let host: String
    let dialect: ForgeDialect
}

/// One entry in `ResolutionDatabase.downloadHostForges`. Maps a tarball
/// download path to the forge that hosts the same projects, for the families
/// whose formulae name a download host and nothing else.
struct DownloadHostForge: Sendable, Equatable, Codable {
    /// The path prefix a project's tarball URL starts with, host included:
    /// `download.gnome.org/sources/`. The segment straight after it is the
    /// project name.
    let downloadPrefix: String
    /// The forge the project's repo lives on. Must also appear in
    /// `forgeHosts`, or the mapping is skipped.
    let forgeHost: String
    /// The owner every project of this family sits under on that forge.
    let owner: String
}

struct ForgeRepo: Sendable, Equatable {
    let host: String
    let owner: String
    let repo: String
    let dialect: ForgeDialect

    var ownerRepo: String { "\(owner)/\(repo)" }
}

/// Resolves an outdated package to the forge repo its release notes live in.
enum ForgeRepoResolver {
    /// Explicit override first, then a forge-host-prefixed `owner/repo`
    /// pattern scanned out of the package's stable download URL, then its
    /// homepage, then its head URL. Nil means no forge repo could be
    /// determined.
    ///
    /// The head URL comes last because it is the least authoritative of the
    /// three — it names the development remote, which for a fork or a mirror
    /// need not be where the releases are published. It is nonetheless the only
    /// signal for a whole class of formula: projects that host tarballs and
    /// docs on their own domain and name the forge nowhere but `head do`
    /// (poppler, cairo, libpng, libuv, …).
    static func resolve(package: OutdatedPackageInfo, database: ResolutionDatabase) -> ForgeRepo? {
        if let override = database.repoOverrides[package.name] {
            return split(override, hosts: database.forgeHosts)
        }
        for candidate in [package.stableURL, package.homepage, package.headURL] {
            if let candidate, let hit = scan(candidate, hosts: database.forgeHosts) {
                return hit
            }
        }
        if let stableURL = package.stableURL {
            return derive(stableURL, forges: database.downloadHostForges, hosts: database.forgeHosts)
        }
        return nil
    }

    /// Splits a "owner/repo" (github.com assumed) or "host/owner/repo"
    /// reference — the shape `ResolutionDatabase.repoOverrides` values use.
    /// Nil if the shape doesn't parse or the host isn't a known forge host.
    private static func split(_ ref: String, hosts: [ForgeHost]) -> ForgeRepo? {
        var trimmed = ref
        for prefix in ["https://", "http://"] where trimmed.hasPrefix(prefix) {
            trimmed.removeFirst(prefix.count)
        }
        if trimmed.hasSuffix(".git") {
            trimmed.removeLast(4)
        }
        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let host: String
        let repoPath: [String]
        switch segments.count {
        case 2:
            host = "github.com"
            repoPath = segments
        case 3:
            host = segments[0].lowercased()
            repoPath = Array(segments[1...])
        default:
            return nil
        }

        guard let forgeHost = hosts.first(where: { $0.host == host }) else { return nil }
        return ForgeRepo(host: host, owner: repoPath[0], repo: repoPath[1], dialect: forgeHost.dialect)
    }

    /// Finds the first `<forge-host>/<owner>/<repo>` in a download URL or
    /// homepage. Left-boundary anchored so `docs.gitlab.com` doesn't match host
    /// `gitlab.com`; the leading `(?:^|[^A-Za-z0-9.-])` group stands in for a
    /// lookbehind, which Swift `Regex` lacks, and being non-capturing it leaves
    /// the `match.output[1...3]` indices intact.
    private static func scan(_ text: String, hosts: [ForgeHost]) -> ForgeRepo? {
        guard !hosts.isEmpty else { return nil }
        let hostAlternation = hosts.map { NSRegularExpression.escapedPattern(for: $0.host) }.joined(separator: "|")
        guard
            let regex = try? Regex("(?:^|[^A-Za-z0-9.-])(\(hostAlternation))/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)").ignoresCase()
        else { return nil }
        guard let match = text.firstMatch(of: regex),
            let hostSub = match.output[1].substring,
            let ownerSub = match.output[2].substring,
            let repoSub = match.output[3].substring
        else {
            return nil
        }

        let host = String(hostSub).lowercased()
        guard let forgeHost = hosts.first(where: { $0.host == host }) else { return nil }

        var repo = String(repoSub)
        if repo.hasSuffix(".git") {
            repo.removeLast(4)
        }
        return ForgeRepo(host: host, owner: String(ownerSub), repo: repo, dialect: forgeHost.dialect)
    }

    /// Last resort: derive the repo from a download URL that names the project
    /// but no forge at all. GNOME publishes every tarball under
    /// `download.gnome.org/sources/<project>/`, and those formulae carry no
    /// `head do` and a documentation homepage, so `scan` has nothing to find
    /// and they resolved to nothing - `librsvg`, `glib` and `gdk-pixbuf` all
    /// reported "No forge repo detected" while their GitLab publishes real
    /// releases for every version.
    ///
    /// Runs only after `scan` has failed on all three URLs, because a URL that
    /// names a forge outright is always the better answer: `pango` has the same
    /// download URL as these but names its repo in `head do`, and keeps
    /// resolving through that.
    ///
    /// The project segment is assumed to be the repo name. Where a family
    /// breaks that assumption the forge API 404s and the caller falls back to
    /// the same placeholder as before, so a wrong guess costs nothing a missing
    /// mapping did not already cost.
    private static func derive(_ text: String, forges: [DownloadHostForge], hosts: [ForgeHost]) -> ForgeRepo? {
        for forge in forges {
            guard let prefix = text.range(of: forge.downloadPrefix, options: .caseInsensitive),
                let segment = text[prefix.upperBound...].split(separator: "/", omittingEmptySubsequences: true).first,
                segment.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." || $0 == "-" }),
                let forgeHost = hosts.first(where: { $0.host == forge.forgeHost })
            else { continue }
            return ForgeRepo(host: forge.forgeHost, owner: forge.owner, repo: String(segment), dialect: forgeHost.dialect)
        }
        return nil
    }
}
