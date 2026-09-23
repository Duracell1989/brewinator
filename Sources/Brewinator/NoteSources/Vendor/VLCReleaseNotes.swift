import Foundation

/// VLC: one page per exact version on videolan.org, holding a short
/// hand-written block for the release followed by the same evergreen "3.0
/// Highlights"/"3.0 Features" marketing sections on every page.
///
/// Deliberately not a forge source and deliberately not the in-tree `NEWS`
/// file, both of which live on code.videolan.org. That host publishes zero
/// release objects for `videolan/vlc` - the releases API returns `[]` - so
/// resolving the forge could only ever report "No releases published", the
/// same trade as poppler and the GnuPG mirrors. Worse, it sits behind an
/// Anubis proof-of-work wall: raw `NEWS` fetches succeed a few times and then
/// start coming back as challenge pages, which makes it unfit for a source
/// that runs unattended every day. www.videolan.org is not gated.
///
/// A non-200 stays **transient**: VideoLAN publishes the release page with the
/// build, but a mirror serving it late should cost a retry, not a permanent
/// stub in the archive.
struct VLCReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "vlc"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let url = URL(string: database.vlcNotesURLTemplate.replacingOccurrences(of: "%s", with: package.cleanCurrentVersion)) else {
            return .failure(.transient(reason: "\(package.name): invalid release notes URL"))
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }

        let block = Self.extractReleaseBlock(from: html)
        guard !block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No release notes found — \(url.absoluteString)_\n\n"))
        }

        let text = HTMLTextReducer.reduce(block)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Release notes page had no readable text — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(text, maxLines: 60, link: url.absoluteString, linkLabel: "Full release notes")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// The release-specific block is the first `<h1>` inside the page body that
    /// is not the banner title, through to the `<h1>` that opens the next
    /// section.
    ///
    /// Anchoring on position rather than on the heading text is the whole
    /// point: the heading is not stable. 3.0.24 titles its block "3.0.24
    /// Highlights", 3.0.23 titles the same block "3.0.22/3.0.23 Fixes", and
    /// the 3.0.21 page never updated its heading past "3.0.19/3.0.20 Fixes" at
    /// all. Matching "<version> Highlights" would have missed three of those
    /// four pages. The heading is emitted verbatim as `### ...` so a stale one
    /// is visible in the archive instead of being silently relabelled.
    ///
    /// The banner is told apart by its `bigtitle` class - it is the only `<h1>`
    /// above the sections and carries no notes.
    private static func extractReleaseBlock(from html: String) -> String {
        var capturing = false
        var output: [String] = []

        for line in html.components(separatedBy: "\n") {
            if let heading = headingText(in: line) {
                if capturing { break }
                if line.contains("bigtitle") || heading.isEmpty { continue }
                capturing = true
                output.append("### \(heading)")
                output.append("")
                continue
            }
            guard capturing else { continue }
            // A page with only one section heading would otherwise run into the
            // footer; the enclosing `</section>` closes the notes either way.
            if line.lowercased().contains("</section>") { break }
            output.append(line)
        }

        return output.joined(separator: "\n")
    }

    /// The text of an `<h1>` opened and closed on one line, or nil when the
    /// line opens no heading.
    private static func headingText(in line: String) -> String? {
        guard line.contains("<h1>") || line.contains("<h1 ") else { return nil }
        let stripped = line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}
