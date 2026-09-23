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
/// A **404 is permanent, not transient** - the opposite of `FirefoxReleaseNotes`,
/// and the distinction matters. VideoLAN publishes a page per *release*, and its
/// four-component point releases never get one: `3.0.17.3`, `3.0.17.4` and
/// `3.0.11.1` are all 404 today while `3.0.16` and `3.0.18` are 200. A version
/// like that is missing a page as a permanent property, so retrying it means
/// re-fetching the same 404 on every daily run and never archiving anything -
/// strictly worse than the "No forge repo detected" placeholder it replaced,
/// which at least archived once and stopped. Every other non-200 stays
/// transient, since a mirror serving a real page late should cost a retry.
struct VLCReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    /// Casks only. `vlc` is a cask here, and a formula that happened to share
    /// the name would otherwise be sent to a videolan.org URL built from its
    /// own version - the first claimant takes the whole result, so it would
    /// never reach its real notes.
    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "vlc" && package.kind == .cask
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let outcome = await VersionedNotesPage.fetch(
            template: database.vlcNotesURLTemplate,
            versionSlug: package.cleanCurrentVersion,
            packageName: package.name,
            notFound: .cacheableStub("VideoLAN published no release page for this version"),
            httpFetcher: httpFetcher
        )

        let html: String
        let url: URL
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .stub(let notes):
            return .success(notes)
        case .page(let pageHTML, let pageURL):
            html = pageHTML
            url = pageURL
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
                if line.lowercased().contains("bigtitle") { continue }
                capturing = true
                // An empty heading means the `<h1>` opened here but its text is
                // on a later line. Start capturing anyway rather than skipping:
                // skipping would hand the block to the next `<h1>`, which is the
                // evergreen "3.0 Highlights" marketing section - archived once as
                // that version's release notes and never revisited, since a
                // non-empty result is a success.
                if !heading.isEmpty {
                    output.append("### \(heading)")
                    output.append("")
                }
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

    /// The text between an `<h1 ...>` and its `</h1>` when both sit on this
    /// line, an empty string when the line opens an `<h1>` whose text or
    /// closing tag is elsewhere, and nil when the line opens no heading.
    ///
    /// Matched case-insensitively and allowing a tab after the tag name, the
    /// way `HTMLTextReducer.containsOpen` already does - the two halves of the
    /// same parsing job should not disagree about what opens a tag. Reading
    /// only the element's own text, rather than stripping the whole line, keeps
    /// a sibling on the same line (`<h1>3.0.25</h1> released 2026-10-01`) out
    /// of the heading. Every index comes from `line` itself: lowercasing can
    /// change a string's length, so indices taken from a lowercased copy are
    /// not safe to use against the original.
    private static func headingText(in line: String) -> String? {
        let openings = ["<h1>", "<h1 ", "<h1\t"]
        let found = openings.compactMap { line.range(of: $0, options: .caseInsensitive) }
        guard let open = found.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        guard let tagEnd = line[open.lowerBound...].firstIndex(of: ">") else { return "" }

        let contentStart = line.index(after: tagEnd)
        guard let close = line.range(of: "</h1>", options: .caseInsensitive, range: contentStart..<line.endIndex) else {
            return ""
        }

        let inner = String(line[contentStart..<close.lowerBound])
        let stripped = HTMLTextReducer.removingTags(inner)
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}
