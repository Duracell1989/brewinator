import Foundation

/// Fetches a raw `CHANGELOG.md`-style page and extracts the `## <version>`
/// section (bare version headers, no `v` prefix; newest section as
/// fallback). Reusable for any cask/formula whose notes are a plain
/// Markdown changelog in this shape — `claude-code` is the only current
/// consumer via `ResolutionDatabase.markdownChangelogSources`.
struct MarkdownChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.markdownChangelogSources[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let url = database.markdownChangelogSources[package.name] else {
            return .success(Resolver.noForgeDetected)
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name) changelog \(url): \(error)"))
        }
        guard status == 200, !data.isEmpty, let page = String(data: data, encoding: .utf8) else {
            return .failure(.transient(reason: "\(package.name) changelog \(url): HTTP \(status)"))
        }

        var section = Self.extractSection(from: page, target: package.cleanCurrentVersion)
        if section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            section = Self.extractSection(from: page, target: "")
        }
        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No changelog entry found — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(section, maxLines: 60, link: url.absoluteString, linkLabel: "Full changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Extracts one `"## <version>"` section: starts at the heading matching
    /// `target` (or the first heading if `target` is empty) and stops at the
    /// next `"## "` heading of any version. The heading line itself is
    /// included in the output.
    private static func extractSection(from markdown: String, target: String) -> String {
        var capturing = false
        var done = false
        var output: [String] = []

        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                let version = String(line.dropFirst(3))
                capturing = false
                if !done && (target.isEmpty || version == target) {
                    capturing = true
                    done = true
                    output.append(line)
                }
                continue
            }
            if capturing {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }
}
