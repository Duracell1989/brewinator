import Foundation

/// SQLite: one hand-written page per exact version at sqlite.org, no forge
/// repo - the source lives in Fossil, which `ForgeRepoResolver` does not speak,
/// and the formula names only the sqlite.org tarball and homepage. The URL
/// embeds the version with dots swapped for underscores (`3.54.0` ->
/// `3_54_0.html`).
///
/// A **404 is transient**: Homebrew can bump a formula before the release log
/// page is up, and archiving a stub would freeze that gap in place.
///
/// Formulae only, for the same reason as `VLCReleaseNotes`: the first claimant
/// takes the whole result, so a cask sharing the name would never reach its
/// real notes.
struct SQLiteReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "sqlite" && package.kind == .formula
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let outcome = await VersionedNotesPage.fetch(
            template: database.sqliteNotesURLTemplate,
            versionSlug: package.cleanCurrentVersion.replacingOccurrences(of: ".", with: "_"),
            packageName: package.name,
            notFound: .transient,
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
        let text = HTMLTextReducer.reduce(block).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .success(ReleaseNotes(markdown: "_No release notes found — \(url.absoluteString)_\n\n"))
        }

        return .success(ReleaseNotes(markdown: MarkdownSection.body(text, maxLines: 60, link: url.absoluteString, linkLabel: "Full release notes")))
    }

    /// From the `<h2>` that titles the release through to the `Hashes:` footer.
    ///
    /// The `<h2>` shares its line with the opening `<ol>`, so only its own text
    /// is kept (as `### ...`) and the rest of that line is dropped; the list
    /// items start on the next line. The hashes - `SQLITE_SOURCE_ID` and the
    /// SHA3 of `sqlite3.c` - are build provenance, not notes, and the page's
    /// own `</ol>` follows them, so the footer marker is the end of the block.
    private static func extractReleaseBlock(from html: String) -> String {
        var capturing = false
        var output: [String] = []

        for line in html.components(separatedBy: "\n") {
            if !capturing {
                if let open = line.range(of: "<h2>"), let close = line.range(of: "</h2>", range: open.upperBound..<line.endIndex) {
                    let heading = HTMLTextReducer.removingTags(String(line[open.upperBound..<close.lowerBound]))
                        .trimmingCharacters(in: .whitespaces)
                    capturing = true
                    if !heading.isEmpty {
                        output.append("### \(heading)")
                        output.append("")
                    }
                }
                continue
            }
            if line.contains("<b>Hashes:</b>") { break }
            output.append(line)
        }

        return output.joined(separator: "\n")
    }
}
