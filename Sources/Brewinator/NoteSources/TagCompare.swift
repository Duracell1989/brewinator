import Foundation

/// Reconstructs notes from a GitHub commit log for tag-but-no-release-body
/// upstreams (see `ResolutionDatabase.tagCompareSpecs`). Prefers the compare
/// API between the installed and current version tags; falls back to the
/// recent commit list at the current tag (path-scoped when the spec supplies
/// one) if the installed tag no longer exists.
struct TagCompare: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.tagCompareSpecs[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let spec = database.tagCompareSpecs[package.name] else {
            return .success(Resolver.noForgeDetected)
        }

        switch await fetchCommitData(spec: spec, package: package) {
        case .cacheable(let notes):
            return .success(notes)
        case .transient(let reason):
            return .failure(.transient(reason: reason))
        case .data(let data, let link):
            return Self.buildMarkdown(data: data, link: link, spec: spec, package: package)
        }
    }

    private enum RawFetchOutcome {
        case data(Data, link: String)
        case cacheable(ReleaseNotes)
        case transient(String)
    }

    /// Compare API between the installed/current tags; on a 404 (installed
    /// tag gone), falls back to the recent commit list at the current tag.
    private func fetchCommitData(spec: TagCompareSpec, package: OutdatedPackageInfo) async -> RawFetchOutcome {
        let baseTag = spec.tagTemplate.replacingOccurrences(of: "%s", with: package.cleanInstalledVersion)
        let headTag = spec.tagTemplate.replacingOccurrences(of: "%s", with: package.cleanCurrentVersion)
        // Only '@' needs escaping for a GitHub API path segment here.
        let encodedBaseTag = baseTag.replacingOccurrences(of: "@", with: "%40")
        let encodedHeadTag = headTag.replacingOccurrences(of: "@", with: "%40")

        let compareLink = "https://github.com/\(spec.repo)/compare/\(encodedBaseTag)...\(encodedHeadTag)"
        guard let compareURL = URL(string: "https://api.github.com/repos/\(spec.repo)/compare/\(encodedBaseTag)...\(encodedHeadTag)") else {
            return .cacheable(Resolver.noForgeDetected)
        }

        let compareData: Data
        let compareStatus: Int
        do {
            (compareData, compareStatus) = try await httpFetcher.fetch(compareURL)
        } catch {
            return .transient("\(spec.repo) tag compare: \(error)")
        }

        guard compareStatus == 404 else {
            guard compareStatus == 200 else {
                return .transient("\(spec.repo) tag compare: HTTP \(compareStatus)")
            }
            return .data(compareData, link: compareLink)
        }

        var fallback = "https://api.github.com/repos/\(spec.repo)/commits?sha=\(encodedHeadTag)&per_page=20"
        if let subpath = spec.subpath, !subpath.isEmpty {
            fallback += "&path=\(subpath)"
        }
        let commitsLink = "https://github.com/\(spec.repo)/commits/\(encodedHeadTag)"
        guard let commitsURL = URL(string: fallback) else {
            return .cacheable(Resolver.noForgeDetected)
        }

        let commitsData: Data
        let commitsStatus: Int
        do {
            (commitsData, commitsStatus) = try await httpFetcher.fetch(commitsURL)
        } catch {
            return .transient("\(spec.repo) commits: \(error)")
        }
        if commitsStatus == 404 {
            return .cacheable(ReleaseNotes(markdown: "_No tag found for \(package.cleanCurrentVersion) — \(commitsLink)_\n\n"))
        }
        guard commitsStatus == 200 else {
            return .transient("\(spec.repo) tag compare: HTTP \(commitsStatus)")
        }
        return .data(commitsData, link: commitsLink)
    }

    /// Decodes either JSON shape (`{commits: [...]}` from the compare
    /// endpoint, or a bare array from the commits-fallback endpoint) and
    /// renders the deduped/capped subject list.
    private static func buildMarkdown(
        data: Data,
        link: String,
        spec: TagCompareSpec,
        package: OutdatedPackageInfo
    ) -> Result<ReleaseNotes, FetchError> {
        let messages: [String]
        let total: Int?
        if let compare = try? JSONDecoder().decode(RawCompareResponse.self, from: data) {
            messages = compare.commits.map(\.commit.message)
            total = compare.totalCommits
        } else if let commits = try? JSONDecoder().decode([RawCommit].self, from: data) {
            messages = commits.map(\.commit.message)
            total = nil
        } else {
            return .failure(.transient(reason: "\(spec.repo) tag compare: invalid JSON"))
        }

        let subjects = dedupedSubjects(from: messages)
        guard !subjects.isEmpty else {
            return .success(
                ReleaseNotes(
                    markdown: "_No commits between \(package.cleanInstalledVersion) and \(package.cleanCurrentVersion) — \(link)_\n\n"
                )
            )
        }

        var markdown = subjects.prefix(40).joined(separator: "\n") + "\n\n"
        if subjects.count > 40 {
            let totalSuffix = total.map { " (\($0) in range, whole repo)" } ?? ""
            markdown += "_Showing 40 of \(subjects.count) commits\(totalSuffix)._\n\n"
        }
        markdown += "[Full diff on GitHub](\(link))\n\n"
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// First line of each commit message, noise-filtered (merges, version
    /// bumps) and deduplicated preserving order, prefixed as a bullet.
    private static func dedupedSubjects(from messages: [String]) -> [String] {
        var seen = Set<String>()
        var subjects: [String] = []
        for message in messages {
            let subject = message.components(separatedBy: "\n").first ?? message
            guard !isNoise(subject), seen.insert(subject).inserted else { continue }
            subjects.append("- " + subject)
        }
        return subjects
    }

    private static func isNoise(_ subject: String) -> Bool {
        let pattern = #"^(Merge (branch|pull|remote)|[Uu]pdate package\.json|chore\(release\)|[Bb]ump version)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(subject.startIndex..<subject.endIndex, in: subject)
        return regex.firstMatch(in: subject, range: range) != nil
    }
}

private struct RawCommit: Decodable {
    let commit: CommitDetail

    struct CommitDetail: Decodable {
        let message: String
    }
}

private struct RawCompareResponse: Decodable {
    let commits: [RawCommit]
    let totalCommits: Int?

    enum CodingKeys: String, CodingKey {
        case commits
        case totalCommits = "total_commits"
    }
}
