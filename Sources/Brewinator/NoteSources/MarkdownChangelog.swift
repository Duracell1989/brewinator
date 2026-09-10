import Foundation

/// Fetches a raw `CHANGELOG.md`-style page and extracts one release's
/// section, falling back to the newest section when the target version has
/// no entry. Reusable for any cask/formula whose notes are a plain Markdown
/// changelog with one version heading per release — `claude-code` and
/// `proton-pass` are the current consumers via
/// `ResolutionDatabase.markdownChangelogSources`.
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

    /// Extracts one version section: starts at the heading matching `target`
    /// (or the first heading if `target` is empty) and stops at the next
    /// version heading. The heading line itself is included in the output.
    private static func extractSection(from markdown: String, target: String) -> String {
        var capturing = false
        var done = false
        var output: [String] = []

        for line in markdown.components(separatedBy: "\n") {
            guard let version = headingVersion(of: line) else {
                if capturing { output.append(line) }
                continue
            }
            capturing = false
            if !done && (target.isEmpty || version == target) {
                capturing = true
                done = true
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// The version a heading line announces, or nil when the line is not a
    /// version heading.
    ///
    /// Both shapes in use are covered by one pattern rather than a per-source
    /// style enum like `NewsFileSpec.headingStyle`: the `NEWS` files that enum
    /// serves differ structurally (prose headings), whereas markdown changelog
    /// headings vary only on depth and one optional word — `## 2.1.231`
    /// (claude-code) against `### Version 1.40.2` (proton-pass).
    ///
    /// Deliberately narrow beyond that: the whole line must be the marker, the
    /// optional word and a dotted version, so neither a bullet mentioning a
    /// version nor a non-version subheading (`### Breaking changes`) can be
    /// read as a heading and cut a section short. A `v` prefix is not accepted
    /// — add it when a source that needs it turns up, with a test.
    private static func headingVersion(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"^#{2,3}\s+(?:[Vv]ersion\s+)?\d+(?:\.\d+)+$"#, options: .regularExpression) != nil else {
            return nil
        }
        guard let start = trimmed.range(of: #"\d"#, options: .regularExpression) else { return nil }
        return String(trimmed[start.lowerBound...])
    }
}
