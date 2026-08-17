import Foundation

/// Firefox: one page per exact version, no release list — the cask's plain
/// `firefox` maps straight into the URL (`@esr`/`@beta` never match this
/// source's `canHandle`). A 404 stays **transient** (Mozilla sometimes
/// publishes the page after the build ships) rather than a cacheable stub.
struct FirefoxReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "firefox"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let url = URL(string: database.firefoxNotesURLTemplate.replacingOccurrences(of: "%s", with: package.cleanCurrentVersion)) else {
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

        let notes = Self.extractNoteBlocks(from: html)
        guard !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No release notes found — \(url.absoluteString)_\n\n"))
        }

        let text = HTMLTextReducer.reduce(notes)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Release notes page had no readable text — \(url.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(text, maxLines: 60, link: url.absoluteString, linkLabel: "Full release notes")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Each note lives in a non-nested `<div class="release-note-content">`
    /// closed by a standalone `</div>` line. Its section heading sits in a
    /// sidebar `<span class="fl-c-release-notes-heading">` a few lines
    /// *before* the notes it applies to, past a decorative icon span — the
    /// scan for the heading text gives up after 10 lines so a markup change
    /// can't run away. Emits "### Heading" lines plus the raw note HTML,
    /// both safe to pipe through `HTMLTextReducer.reduce`.
    private static func extractNoteBlocks(from html: String) -> String {
        var pending = false
        var skipped = 0
        var capturing = false
        var output: [String] = []

        for line in html.components(separatedBy: "\n") {
            if line.contains(#"<span class="fl-c-release-notes-heading">"#) {
                pending = true
                skipped = 0
                continue
            }

            if pending {
                skipped += 1
                if skipped > 10 {
                    pending = false
                } else {
                    let stripped = stripTags(line).trimmingCharacters(in: .whitespaces)
                    if !stripped.isEmpty {
                        output.append("")
                        output.append("### \(stripped)")
                        output.append("")
                        pending = false
                    }
                    continue
                }
            }

            if line.contains(#"<div class="release-note-content">"#) {
                capturing = true
                continue
            }
            if capturing, line.trimmingCharacters(in: .whitespaces) == "</div>" {
                capturing = false
                output.append("")
                continue
            }
            if capturing {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }

    private static func stripTags(_ line: String) -> String {
        line.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
    }
}
