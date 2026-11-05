import Foundation

/// Fetches a raw `CHANGELOG.md`-style page and extracts one release's
/// section. Two registrations feed it through `ResolutionDatabase`:
/// `markdownChangelogSources` (`claude-code`, `proton-pass`) is one fixed page
/// that falls back to its newest section when the target version has no entry,
/// because the page always describes the latest release. `taggedChangelogURLTemplates`
/// (`rustup`) reads the page at the target's own git tag, so a missing section
/// means that tag's changelog was not updated and is reported as such - the
/// newest section there would be a *different* release. A fixed URL wins when a
/// package is registered in both.
struct MarkdownChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.markdownChangelogSources[package.name] != nil || database.taggedChangelogURLTemplates[package.name] != nil
    }

    /// A fixed URL wins; otherwise the per-version template, with `%s` replaced
    /// by the exact target version (the tag name).
    private func changelogURL(for package: OutdatedPackageInfo) -> URL? {
        if let fixed = database.markdownChangelogSources[package.name] { return fixed }
        guard let template = database.taggedChangelogURLTemplates[package.name] else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: package.cleanCurrentVersion))
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let isTagged = database.markdownChangelogSources[package.name] == nil
        guard database.markdownChangelogSources[package.name] != nil || database.taggedChangelogURLTemplates[package.name] != nil else {
            return .success(Resolver.noForgeDetected)
        }
        guard let url = changelogURL(for: package) else {
            return .failure(.transient(reason: "\(package.name) changelog: invalid URL for version \(package.cleanCurrentVersion)"))
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

        // A tagged changelog covers installed..target, so upgrading across
        // releases does not hide an intermediate one (a security fix, say).
        var section = Self.extractSection(
            from: page,
            target: package.cleanCurrentVersion,
            until: isTagged ? package.cleanInstalledVersion : nil
        )
        if section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isTagged {
            section = Self.extractSection(from: page, target: "")
        }
        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No changelog entry found — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(section, maxLines: 60, link: url.absoluteString, linkLabel: "Full changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Extracts a version section: starts at the heading matching `target` (or
    /// the first real release if `target` is empty, which skips `[Unreleased]`)
    /// and stops at the next version heading. The heading line is included.
    ///
    /// With `installed`, the extraction continues through every older release
    /// down to, but excluding, that version - or to the end of the file when it
    /// is not in there, which the caller's line cap then trims from the old end.
    private static func extractSection(from markdown: String, target: String, until installed: String? = nil) -> String {
        var capturing = false
        var started = false
        var output: [String] = []

        for line in markdown.components(separatedBy: "\n") {
            guard let version = headingVersion(of: line) else {
                if capturing { output.append(line) }
                continue
            }
            if started {
                guard let installed else { break }
                if isUnreleased(version) {
                    capturing = false
                    continue
                }
                guard version != installed else { break }
                capturing = true
                output.append(line)
                continue
            }
            if version == target || (target.isEmpty && !isUnreleased(version)) {
                capturing = true
                started = true
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    /// `[Unreleased]` and prerelease (`1.30.0-beta.1`) blocks are not releases
    /// anyone installs, so a range steps over them instead of listing them.
    private static func isUnreleased(_ version: String) -> Bool {
        version == "Unreleased" || version.contains("-")
    }

    /// Compiled once, and checked by the compiler: a `try?` around a runtime
    /// pattern would turn a typo into every package reporting "no entry".
    ///
    /// Two shapes: Keep a Changelog's bracketed `## [1.29.3] - 2026-11-03`
    /// (the brackets are one group, so `## [1.2.3` is not a heading; anything
    /// after the closing bracket is allowed, which covers dates and `[YANKED]`;
    /// prerelease versions and `[Unreleased]` match too, purely so they end the
    /// section before them), and the bare `## 2.1.231` / `### Version 1.40.2`.
    ///
    /// `nonisolated(unsafe)`: `Regex` is not `Sendable`, but this one is immutable and only ever matched.
    private nonisolated(unsafe) static let headingPattern =
        #/^#{2,3}\s+(?:[Vv]ersion\s+)?(?:\[(\d+(?:\.\d+)+[0-9A-Za-z.+\-]*|Unreleased)\](?:\s+-\s+.*)?|(\d+(?:\.\d+)+))$/#

    /// The version a heading line announces, or nil when the line is not a
    /// version heading.
    ///
    /// One pattern rather than a per-source style enum like
    /// `NewsFileSpec.headingStyle`: the `NEWS` files that enum serves differ
    /// structurally (prose headings), whereas markdown changelog headings vary
    /// only on depth, one optional word, and Keep a Changelog's brackets.
    ///
    /// Deliberately narrow beyond that: the whole line must be the marker, the
    /// optional word and a dotted version, so neither a bullet mentioning a
    /// version nor a non-version subheading (`### Breaking changes`) can be
    /// read as a heading and cut a section short. A `v` prefix is not accepted
    /// - add it when a source that needs it turns up, with a test.
    private static func headingVersion(of line: String) -> String? {
        guard let match = line.trimmingCharacters(in: .whitespaces).wholeMatch(of: headingPattern) else { return nil }
        return String(match.output.1 ?? match.output.2 ?? "")
    }
}
