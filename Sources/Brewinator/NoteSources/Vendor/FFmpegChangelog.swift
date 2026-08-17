import Foundation

/// FFmpeg: the GitHub mirror publishes zero Releases, but every branch
/// carries a `Changelog` of `version X:` sections. Point releases (8.1.2)
/// exist only on the release branch's own copy; `master` only has minor
/// headings (8.1) with nothing below them. `release/<channel>` is tried
/// first, `master` is the fallback for a version whose branch isn't cut yet.
/// A 404 on an attempt tries the next ref; any other failure is transient
/// immediately, without a fallback attempt.
struct FFmpegChangelog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "ffmpeg" || package.name.hasPrefix("ffmpeg@")
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let clean = package.cleanCurrentVersion
        let channel = VersionMatcher.versionChannel(clean)
        let refs = ["release/\(channel)", "master"]

        var section = ""
        var lastRef = refs[0]
        for ref in refs {
            lastRef = ref
            guard let url = changelogURL(for: ref) else {
                return .failure(.transient(reason: "\(package.name): invalid Changelog URL for ref \(ref)"))
            }

            let data: Data
            let status: Int
            do {
                (data, status) = try await httpFetcher.fetch(url)
            } catch {
                return .failure(.transient(reason: "\(package.name): \(error)"))
            }

            if status == 404 { continue }
            guard status == 200, let page = String(data: data, encoding: .utf8), !page.isEmpty else {
                return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
            }

            section = Self.extractSection(target: clean, from: page)
            if !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
        }

        guard let finalURL = changelogURL(for: lastRef) else {
            return .failure(.transient(reason: "\(package.name): invalid Changelog URL for ref \(lastRef)"))
        }

        guard !section.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No Changelog section for \(clean) — \(finalURL.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(section, maxLines: 60, link: finalURL.absoluteString, linkLabel: "Full Changelog")
        return .success(ReleaseNotes(markdown: markdown))
    }

    private func changelogURL(for ref: String) -> URL? {
        URL(string: database.ffmpegChangelogURLTemplate.replacingOccurrences(of: "%s", with: ref))
    }

    /// Extracts the single `version <target>:` section (header line dropped)
    /// from a Changelog on the given text, stopping at the next `version `
    /// line. Only the first match wins — the file is newest-first.
    private static func extractSection(target: String, from text: String) -> String {
        var capturing = false
        var done = false
        var output: [String] = []

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("version ") {
                var version = String(line.dropFirst("version ".count))
                if version.hasSuffix(":") { version.removeLast() }
                version = version.trimmingCharacters(in: .whitespaces)
                capturing = !done && version == target
                if capturing { done = true }
                continue
            }
            if capturing {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }
}
