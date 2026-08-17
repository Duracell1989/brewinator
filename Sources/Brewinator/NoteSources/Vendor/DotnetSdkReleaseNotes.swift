import Foundation

/// .NET SDK: a Microsoft CDN cask with no forge. `dotnet/sdk` does publish
/// release bodies, but they're a raw PR dump — the curated notes live in
/// `dotnet/core`, keyed by **runtime** version, which the cask's SDK version
/// (10.0.400) never shows. The channel's `releases.json` is the only
/// mapping: each release lists every SDK carrying its runtime, and its
/// `release-notes` field is the page URL. Only the `### Notable Changes`
/// section is archived out of the ~950-line page.
struct DotnetSdkReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "dotnet-sdk" || package.name.hasPrefix("dotnet-sdk@")
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let clean = package.cleanCurrentVersion
        let channel = VersionMatcher.versionChannel(clean)
        guard let indexURL = URL(string: database.dotnetReleasesURLTemplate.replacingOccurrences(of: "%s", with: channel)) else {
            return .failure(.transient(reason: "\(package.name): invalid release metadata URL"))
        }

        switch await fetchNotesURL(indexURL: indexURL, target: clean, package: package) {
        case .transient(let reason):
            return .failure(.transient(reason: reason))
        case .noMatch:
            return .success(ReleaseNotes(markdown: "_No release matching SDK \(clean) — \(indexURL.absoluteString)_\n\n"))
        case .found(let notesURL):
            return await fetchSection(notesURL: notesURL, package: package)
        }
    }

    private enum IndexOutcome {
        case found(URL)
        case noMatch
        case transient(String)
    }

    private func fetchNotesURL(indexURL: URL, target: String, package: OutdatedPackageInfo) async -> IndexOutcome {
        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(indexURL)
        } catch {
            return .transient("\(package.name): \(error)")
        }
        guard status == 200, !data.isEmpty else {
            return .transient("\(package.name): HTTP \(status)")
        }
        guard let index = try? JSONDecoder().decode(RawDotnetReleasesIndex.self, from: data) else {
            return .transient("\(package.name): invalid release metadata JSON")
        }

        let match = index.releases?.first { release in
            release.sdk?.version == target || (release.sdks ?? []).contains { $0.version == target }
        }
        guard let notesURLString = match?.releaseNotes, let notesURL = URL(string: notesURLString) else {
            return .noMatch
        }
        return .found(notesURL)
    }

    private func fetchSection(notesURL: URL, package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let rawURL = Self.rawURL(from: notesURL) else {
            return .failure(.transient(reason: "\(package.name): could not derive raw notes URL from \(notesURL.absoluteString)"))
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(rawURL)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, let page = String(data: data, encoding: .utf8), !page.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }

        let section = Self.extractHeadingSection(target: database.dotnetNotableChangesHeading, from: page)
        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let headingName = database.dotnetNotableChangesHeading.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            return .success(ReleaseNotes(markdown: "_No \"\(headingName)\" section — \(notesURL.absoluteString)_\n\n"))
        }

        var markdown = ""
        if let title = Self.pageTitle(of: page) {
            markdown += "**\(title)**\n\n"
        }
        markdown += MarkdownSection.body(section, maxLines: 60, link: notesURL.absoluteString, linkLabel: "Full release notes")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// `github.com/.../blob/<ref>/...` -> `raw.githubusercontent.com/.../...`
    private static func rawURL(from notesURL: URL) -> URL? {
        var raw = notesURL.absoluteString.replacingOccurrences(of: "https://github.com/", with: "https://raw.githubusercontent.com/")
        raw = raw.replacingOccurrences(of: "/blob/", with: "/")
        return URL(string: raw)
    }

    /// The page's first `# ` heading, e.g. "# .NET 10.0.11 - August 11,
    /// 2026" — the runtime release this SDK belongs to, not shown by the
    /// cask version.
    private static func pageTitle(of page: String) -> String? {
        for line in page.components(separatedBy: "\n") where line.hasPrefix("# ") {
            return String(line.dropFirst(2))
        }
        return nil
    }

    /// Extracts the Markdown section starting *after* the heading line
    /// matching `target` exactly (dropped) up to the next heading of any
    /// level (also dropped) — fence-aware so a leading `#` inside a code
    /// block can't end the section early. Leading blank lines within the
    /// section are skipped.
    private static func extractHeadingSection(target: String, from text: String) -> String {
        var fence = false
        var capturing = false
        var done = false
        var started = false
        var output: [String] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                fence.toggle()
                if capturing { output.append(line) }
                continue
            }
            if !fence, isHeadingLine(line) {
                if capturing { break }
                if !done, line.hasPrefix(target) {
                    capturing = true
                    done = true
                }
                continue
            }
            if capturing {
                if !started {
                    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                    started = true
                }
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    /// `^#+ ` — one or more `#` followed by a space (not just "starts with
    /// #", which would also match a bare `#` used as a shell/URL fragment).
    private static func isHeadingLine(_ line: String) -> Bool {
        var index = line.startIndex
        var hashCount = 0
        while index < line.endIndex, line[index] == "#" {
            hashCount += 1
            index = line.index(after: index)
        }
        return hashCount > 0 && index < line.endIndex && line[index] == " "
    }
}

private struct RawDotnetSdkVersion: Decodable {
    let version: String?
}

private struct RawDotnetRelease: Decodable {
    let releaseNotes: String?
    let sdk: RawDotnetSdkVersion?
    let sdks: [RawDotnetSdkVersion]?

    enum CodingKeys: String, CodingKey {
        case releaseNotes = "release-notes"
        case sdk
        case sdks
    }
}

private struct RawDotnetReleasesIndex: Decodable {
    let releases: [RawDotnetRelease]?
}
