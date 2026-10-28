import Foundation

/// Microsoft Build of OpenJDK: one Microsoft Learn page holds every release as
/// an `<h3 id="openjdk-...">OpenJDK 21.0.13.0.2</h3>` section, grouped under an
/// `<h2>` per major line. The casks name only an `aka.ms` download redirect and
/// `microsoft.com/openjdk`, and the source branches on github.com/microsoft are
/// not published as release objects, so no forge ever resolves.
///
/// Matches `microsoft-openjdk` and every version-pinned `microsoft-openjdk@N`
/// cask. The heading carries the cask version verbatim, including the
/// four-component respins (`21.0.12.1`, `21.0.13.0.2`), so matching is exact.
///
/// A missing section is **transient**: the page is edited by hand and can trail
/// the cask by a day, and archiving a stub would freeze that gap in place.
struct MicrosoftOpenJDKReleaseNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.kind == .cask && (package.name == "microsoft-openjdk" || package.name.hasPrefix("microsoft-openjdk@"))
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let pageURL = database.microsoftOpenJDKReleaseNotesURL

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(pageURL)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            return .failure(.transient(reason: "\(package.name): release notes page was empty or not valid UTF-8"))
        }

        guard let section = Self.extractSection(version: package.cleanCurrentVersion, from: html) else {
            return .failure(.transient(reason: "\(package.name): no OpenJDK \(package.cleanCurrentVersion) section on the release notes page yet"))
        }

        let text = HTMLTextReducer.reduce(section.body)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Release notes section had no readable text — \(pageURL.absoluteString)_\n\n"))
        }

        let link = section.anchor.map { "\(pageURL.absoluteString)#\($0)" } ?? pageURL.absoluteString
        let body = "### OpenJDK \(package.cleanCurrentVersion)\n\n" + text
        return .success(ReleaseNotes(markdown: MarkdownSection.body(body, maxLines: 40, link: link, linkLabel: "Full release notes")))
    }

    /// From the matching `<h3>` to the next `<h2>`/`<h3>`, stopping early at the
    /// `<table>` of build platforms: boot JDK and compiler versions are build
    /// provenance, not notes.
    private static func extractSection(version: String, from html: String) -> (anchor: String?, body: String)? {
        var capturing = false
        var anchor: String?
        var output: [String] = []

        for line in html.components(separatedBy: "\n") {
            if !capturing {
                guard let open = line.range(of: "<h3"), let close = line.range(of: "</h3>", range: open.upperBound..<line.endIndex) else {
                    continue
                }
                let heading = HTMLTextReducer.removingTags(String(line[open.lowerBound..<close.lowerBound])).trimmingCharacters(in: .whitespaces)
                guard heading == "OpenJDK \(version)" else { continue }
                capturing = true
                anchor = idAttribute(in: String(line[open.lowerBound..<close.lowerBound]))
                continue
            }
            if line.contains("<h2") || line.contains("<h3") || line.contains("<table") { break }
            output.append(line)
        }

        return capturing ? (anchor, output.joined(separator: "\n")) : nil
    }

    private static func idAttribute(in tag: String) -> String? {
        guard let start = tag.range(of: #"id=""#), let end = tag.range(of: "\"", range: start.upperBound..<tag.endIndex) else { return nil }
        return String(tag[start.upperBound..<end.lowerBound])
    }
}
