import Foundation

/// Fetches an upstream's raw `NEWS` file and extracts the version range between
/// the installed and the current version.
///
/// The niche it fills: projects that write genuinely good release notes but
/// publish them nowhere a forge API can reach — either because their canonical
/// host isn't a supported forge, or because the GitHub repo is a read-only
/// mirror with an empty releases tab. Every package in
/// `ResolutionDatabase.newsFileSources` is in the second category.
///
/// Sits above `ForgeReleases` in the source list, which matters: for a mirrored
/// package both would claim it, and `Resolver` gives the first claimant the
/// whole result with no fallback.
struct NewsFileChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.newsFileSources[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let spec = database.newsFileSources[package.name] else {
            return .success(Resolver.noForgeDetected)
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(spec.url)
        } catch {
            return .failure(.transient(reason: "\(package.name) NEWS \(spec.url): \(error)"))
        }
        guard status == 200, !data.isEmpty, let news = String(data: data, encoding: .utf8) else {
            return .failure(.transient(reason: "\(package.name) NEWS \(spec.url): HTTP \(status)"))
        }

        var section = NewsRangeExtractor.extract(
            from: news,
            newest: package.cleanCurrentVersion,
            oldest: package.cleanInstalledVersion,
            style: spec.headingStyle
        )
        if section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section = NewsRangeExtractor.extract(from: news, newest: package.cleanCurrentVersion, oldest: "", style: spec.headingStyle)
        }
        // Deliberately no newest-section fallback, unlike `MarkdownChangelog`:
        // the top section of a GnuPG NEWS file is the unreleased one, so
        // falling back to it would present in-development notes as the
        // release's own.
        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No NEWS entry for \(package.cleanCurrentVersion) — \(spec.url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(section, maxLines: 60, link: spec.url.absoluteString, linkLabel: "Full NEWS")
        return .success(ReleaseNotes(markdown: markdown))
    }
}
