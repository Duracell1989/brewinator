import Foundation

/// Obsidian: the repo is resolvable, but every release body is nothing but
/// a bare link to the real changelog page on obsidian.md. The repo is a
/// hardcoded constant (`ResolutionDatabase.obsidianRepo`), not resolved via
/// `ForgeRepoResolver` — it never goes through the override/scan machinery
/// `ForgeReleases` uses, so this source does its own small GitHub releases
/// fetch rather than sharing one.
struct ObsidianChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "obsidian"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let releasesURL = "https://github.com/\(database.obsidianRepo)/releases"
        guard let listURL = URL(string: "https://api.github.com/repos/\(database.obsidianRepo)/releases") else {
            return .failure(.transient(reason: "\(package.name): invalid releases URL"))
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(listURL)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        if status == 404 {
            return .success(Self.noMatch(releasesURL))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }
        guard !data.isEmpty, let releases = try? JSONDecoder().decode([RawObsidianRelease].self, from: data) else {
            return .failure(.transient(reason: "\(package.name): invalid JSON"))
        }
        guard !releases.isEmpty, let match = VersionMatcher.matchRelease(in: releases, version: package.cleanCurrentVersion) else {
            return .success(Self.noMatch(releasesURL))
        }

        let body = match.body ?? ""
        guard let changelogURL = Self.firstChangelogURL(in: body) else {
            let content = body.isEmpty ? "_(no release description)_" : body
            let markdown = MarkdownSection.body(content, maxLines: 40, link: releasesURL, linkLabel: "Full release on github.com")
            return .success(ReleaseNotes(markdown: markdown))
        }

        return await fetchChangelogPage(changelogURL, package: package)
    }

    private func fetchChangelogPage(_ changelogURL: URL, package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(changelogURL)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }

        let content = Self.scopedContent(of: html)
        let text = HTMLTextReducer.reduce(content)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Changelog page had no readable text — \(changelogURL.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(text, maxLines: 40, link: changelogURL.absoluteString, linkLabel: "Full changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    private static func noMatch(_ releasesURL: String) -> ReleaseNotes {
        ReleaseNotes(markdown: "_No matching release found — \(releasesURL)_\n\n")
    }

    private static func firstChangelogURL(in body: String) -> URL? {
        let pattern = #"https://obsidian\.md/[A-Za-z0-9._/-]*changelog[A-Za-z0-9._/-]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        guard let match = regex.firstMatch(in: body, range: range), let matchRange = Range(match.range, in: body) else {
            return nil
        }
        return URL(string: String(body[matchRange]))
    }

    /// Isolates the version-entry content, dropping the header/social bar
    /// (whose links would dominate) and anything past the footer. Tries the
    /// content wrapper, then the older changelog-container class, then the
    /// whole page as a last resort.
    private static func scopedContent(of html: String) -> String {
        if let scoped = scan(html, openMarker: #"<div class="py-16 flex flex-col"#, closeMarker: "<footer"), !scoped.isEmpty {
            return scoped
        }
        if let scoped = scan(html, openMarker: #"<div class="container changelog">"#, closeMarker: "<footer"), !scoped.isEmpty {
            return scoped
        }
        return html
    }

    private static func scan(_ html: String, openMarker: String, closeMarker: String) -> String? {
        var capturing = false
        var output: [String] = []
        for line in html.components(separatedBy: "\n") {
            if line.contains(closeMarker) {
                if capturing { break }
                continue
            }
            if line.contains(openMarker) {
                capturing = true
            }
            if capturing {
                output.append(line)
            }
        }
        return output.isEmpty ? nil : output.joined(separator: "\n")
    }
}

private struct RawObsidianRelease: Decodable, VersionTagged {
    let tagName: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body
    }
}
