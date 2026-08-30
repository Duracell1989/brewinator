import Foundation

/// NSS: one Sphinx-rendered page per exact version at
/// firefox-source-docs.mozilla.org, no forge repo - the source lives in
/// Mozilla's Mercurial tree, never mirrored to a GitHub/GitLab/Gitea host
/// `ForgeRepoResolver` recognises. The URL embeds the version with dots
/// swapped for underscores (`3.128` -> `nss_3_128.html`); a 404 is
/// **transient**, matching `FirefoxReleaseNotes`, since the doc build can lag
/// the actual release by a day or two.
struct NSSReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "nss"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let slug = package.cleanCurrentVersion.replacingOccurrences(of: ".", with: "_")
        guard let url = URL(string: database.nssNotesURLTemplate.replacingOccurrences(of: "%s", with: slug)) else {
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

        let changes = Self.extractSection(heading: "<h2>Changes in NSS", from: html)
        guard !changes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_No \"Changes in NSS\" section — \(url.absoluteString)_\n\n"))
        }

        var markdown = ""
        let intro = HTMLTextReducer.reduce(Self.extractSection(heading: "<h2>Introduction", from: html))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !intro.isEmpty {
            markdown += "**\(intro)**\n\n"
        }
        markdown += MarkdownSection.body(HTMLTextReducer.reduce(changes), maxLines: 60, link: url.absoluteString, linkLabel: "Full release notes")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Captures the `<div class="docutils container">` immediately following
    /// the first line containing `heading`, up to its matching top-level
    /// `</div>` - every section on this page nests exactly one such div with
    /// no div of its own inside it, true from NSS 3.90 through 3.128.
    private static func extractSection(heading: String, from html: String) -> String {
        var foundHeading = false
        var capturing = false
        var output: [String] = []

        for line in html.components(separatedBy: "\n") {
            if line.contains(heading) {
                foundHeading = true
                continue
            }
            if foundHeading, line.contains(#"<div class="docutils container">"#) {
                capturing = true
                foundHeading = false
                continue
            }
            if capturing, line.trimmingCharacters(in: .whitespaces) == "</div>" {
                break
            }
            if capturing {
                output.append(line)
            }
        }

        return output.joined(separator: "\n")
    }
}
