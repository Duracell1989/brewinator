import Foundation

/// GitLab releases: different fields than GitHub/Gitea (`description` /
/// `_links.self`), plus the NEWS-file fallback for GNOME-style stub
/// descriptions ("The 1.58.2 release.").
struct GitLabReleases: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        ForgeRepoResolver.resolve(package: package, database: database)?.dialect == .gitlab
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let repo = ForgeRepoResolver.resolve(package: package, database: database) else {
            return .success(Resolver.noForgeDetected)
        }
        let base = "https://\(repo.host)/\(repo.ownerRepo)"

        switch await matchedRelease(for: package, repo: repo, base: base) {
        case .transient(let reason):
            return .failure(.transient(reason: reason))
        case .cacheable(let notes):
            return .success(notes)
        case .matched(let match):
            return await buildMarkdown(match: match, repo: repo, base: base, package: package)
        }
    }

    private enum MatchOutcome {
        case matched(RawGitLabRelease)
        case cacheable(ReleaseNotes)
        case transient(String)
    }

    private func matchedRelease(for package: OutdatedPackageInfo, repo: ForgeRepo, base: String) async -> MatchOutcome {
        guard let listURL = releasesListURL(for: repo) else {
            return .cacheable(Resolver.noForgeDetected)
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(listURL)
        } catch {
            return .transient("\(package.name) (\(repo.host)/\(repo.ownerRepo)): \(error)")
        }

        if status == 404 {
            return .cacheable(ReleaseNotes(markdown: "_No releases published — \(base)/-/releases_\n\n"))
        }
        guard status == 200 else {
            return .transient("\(package.name) (\(repo.host)/\(repo.ownerRepo)): HTTP \(status)")
        }
        guard !data.isEmpty, let releases = try? JSONDecoder().decode([RawGitLabRelease].self, from: data) else {
            return .transient("\(package.name) (\(repo.host)/\(repo.ownerRepo)): invalid JSON")
        }
        guard !releases.isEmpty else {
            return .cacheable(ReleaseNotes(markdown: "_No releases published — \(base)/-/releases_\n\n"))
        }
        // Matched on the *cleaned* current version, same as the generic
        // forge path.
        guard let match = VersionMatcher.matchRelease(in: releases, version: package.cleanCurrentVersion) else {
            return .cacheable(ReleaseNotes(markdown: "_No matching release found — \(base)/-/releases_\n\n"))
        }
        return .matched(match)
    }

    /// Tries the NEWS-file fallback when the description is a stub, then
    /// falls back to the description itself (real or stub) either way.
    private func buildMarkdown(
        match: RawGitLabRelease,
        repo: ForgeRepo,
        base: String,
        package: OutdatedPackageInfo
    ) async -> Result<ReleaseNotes, FetchError> {
        let tag = match.tagName
        let description = match.description ?? ""
        let rawSelfLink = match.links?.selfLink ?? ""
        let selfLink = rawSelfLink.isEmpty ? "\(base)/-/releases" : rawSelfLink

        if Self.isStub(description, database: database) {
            for file in database.gitlabNewsFiles {
                if let section = await newsSection(base: base, tag: tag, file: file, package: package) {
                    let markdown =
                        MarkdownSection.body(section, maxLines: 60)
                        + "[\(file) at \(tag)](\(base)/-/blob/\(tag)/\(file)) · [Release on \(repo.host)](\(selfLink))\n\n"
                    return .success(ReleaseNotes(markdown: markdown))
                }
            }
        }

        let finalDescription = description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "_(no release description)_" : description
        let markdown = MarkdownSection.body(finalDescription, maxLines: 40, link: selfLink, linkLabel: "Full release on \(repo.host)")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Fetches one candidate NEWS file at the release tag and extracts the
    /// version range. Nil if the file is missing or the range is empty; either
    /// way the caller tries the next candidate.
    private func newsSection(base: String, tag: String, file: String, package: OutdatedPackageInfo) async -> String? {
        guard let url = URL(string: "\(base)/-/raw/\(tag)/\(file)"),
            let (newsData, newsStatus) = try? await httpFetcher.fetch(url),
            newsStatus == 200,
            let news = String(data: newsData, encoding: .utf8),
            !news.isEmpty
        else {
            return nil
        }

        var section = NewsRangeExtractor.extract(from: news, newest: package.cleanCurrentVersion, oldest: package.cleanInstalledVersion)
        if section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section = NewsRangeExtractor.extract(from: news, newest: package.cleanCurrentVersion, oldest: "")
        }
        return section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : section
    }

    /// True if a GitLab release description is a placeholder rather than
    /// real notes: empty, matching the configured stub regex (checked
    /// lowercased), or shorter than the configured minimum length.
    private static func isStub(_ description: String, database: ResolutionDatabase) -> Bool {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }

        if let regex = try? NSRegularExpression(pattern: database.gitlabStubPattern) {
            let lowered = trimmed.lowercased()
            let range = NSRange(lowered.startIndex..<lowered.endIndex, in: lowered)
            if regex.firstMatch(in: lowered, range: range) != nil { return true }
        }

        return trimmed.count < database.gitlabStubMaxLength
    }

    private func releasesListURL(for repo: ForgeRepo) -> URL? {
        let encodedRepo = repo.ownerRepo.replacingOccurrences(of: "/", with: "%2F")
        return URL(string: "https://\(repo.host)/api/v4/projects/\(encodedRepo)/releases")
    }
}

private struct RawGitLabReleaseLinks: Decodable {
    let selfLink: String?

    enum CodingKeys: String, CodingKey {
        case selfLink = "self"
    }
}

private struct RawGitLabRelease: Decodable, VersionTagged {
    let tagName: String
    let description: String?
    let links: RawGitLabReleaseLinks?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case description
        case links = "_links"
    }
}

/// Extracts a *range* of "Overview of changes..." sections from a GNOME-style
/// NEWS file, from `newest` down to `oldest` (exclusive). The range matters:
/// pango 1.58.2 says only "No changes" and the substance is in 1.58.1.
private enum NewsRangeExtractor {
    static func extract(from text: String, newest: String, oldest: String) -> String {
        var started = false
        var output: [String] = []

        for line in text.components(separatedBy: "\n") {
            if let version = headingVersion(of: line) {
                if !started {
                    if newest.isEmpty || version == newest {
                        started = true
                    } else {
                        continue
                    }
                } else if !oldest.isEmpty && version == oldest {
                    break
                }
            }
            if started {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// Headings vary ("...in 1.58.2, 05-08-2026", "...in GLib 2.88.0",
    /// "...leading to 11.0.0"), so the version is the last whitespace-separated
    /// token once the prefix and any trailing ", <date>" are stripped.
    private static func headingVersion(of line: String) -> String? {
        let pattern = #"^Overview of [Cc]hanges (in|leading to)[ \t]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), let matchRange = Range(match.range, in: line) else {
            return nil
        }

        var rest = String(line[matchRange.upperBound...])
        if let commaIndex = rest.firstIndex(of: ",") {
            rest = String(rest[rest.startIndex..<commaIndex])
        }
        let tokens = rest.split(whereSeparator: { $0 == " " || $0 == "\t" })
        return tokens.last.map(String.init)
    }
}
