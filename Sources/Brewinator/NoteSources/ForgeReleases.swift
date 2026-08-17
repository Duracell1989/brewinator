import Foundation

/// GitHub + Gitea-family (Forgejo/Codeberg) releases. Both speak the same
/// unauthenticated releases-list shape (`body`/`html_url`) and the same
/// version-matching rule — only the endpoint URL differs. GitLab's different
/// fields and NEWS-file fallback live in `GitLabReleases`.
struct ForgeReleases: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        guard let repo = ForgeRepoResolver.resolve(package: package, database: database) else { return false }
        return repo.dialect == .github || repo.dialect == .gitea
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let repo = ForgeRepoResolver.resolve(package: package, database: database) else {
            return .success(Resolver.noForgeDetected)
        }

        guard let listURL = releasesListURL(for: repo) else {
            return .success(Resolver.noForgeDetected)
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(listURL)
        } catch {
            return .failure(.transient(reason: "\(package.name) (\(repo.host)/\(repo.ownerRepo)): \(error)"))
        }

        if status == 404 {
            return .success(noMatch(for: repo))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(package.name) (\(repo.host)/\(repo.ownerRepo)): HTTP \(status)"))
        }
        guard !data.isEmpty, let releases = try? JSONDecoder().decode([RawRelease].self, from: data) else {
            return .failure(.transient(reason: "\(package.name) (\(repo.host)/\(repo.ownerRepo)): invalid JSON"))
        }
        guard !releases.isEmpty else {
            return .success(noMatch(for: repo))
        }
        guard let match = VersionMatcher.matchRelease(in: releases, version: package.cleanCurrentVersion) else {
            return .success(noMatch(for: repo))
        }

        let matchBody = match.body ?? ""
        let body = matchBody.isEmpty ? "_(no release description)_" : matchBody
        let link = match.htmlURL ?? "https://\(repo.host)/\(repo.ownerRepo)/releases"
        let markdown = MarkdownSection.body(body, maxLines: 40, link: link, linkLabel: "Full release on \(repo.host)")
        return .success(ReleaseNotes(markdown: markdown))
    }

    private func noMatch(for repo: ForgeRepo) -> ReleaseNotes {
        ReleaseNotes(markdown: "_No matching release found — https://\(repo.host)/\(repo.ownerRepo)/releases_\n\n")
    }

    private func releasesListURL(for repo: ForgeRepo) -> URL? {
        switch repo.dialect {
        case .github:
            return URL(string: "https://api.github.com/repos/\(repo.ownerRepo)/releases")
        case .gitea:
            return URL(string: "https://\(repo.host)/api/v1/repos/\(repo.ownerRepo)/releases")
        case .gitlab:
            return nil
        }
    }
}

private struct RawRelease: Decodable, VersionTagged {
    let tagName: String
    let body: String?
    let htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
        case htmlURL = "html_url"
    }
}
