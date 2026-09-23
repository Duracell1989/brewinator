import Foundation

/// The preamble every "one page per exact version" vendor source repeats: fill
/// a `%s` template with the version, fetch it, and turn a transport error, a
/// bad status or an undecodable body into the right `Result` before any of
/// them reaches the source's own parsing.
///
/// Deliberately only the preamble. `FirefoxReleaseNotes`, `NSSReleaseNotes` and
/// `VLCReleaseNotes` had this block verbatim three times over, down to the
/// shared "invalid release notes URL" string, but they diverge completely after
/// it - NSS composes two extracted sections into one body with its own stub
/// wording, the other two each have their own extractor and, since 0.12.2,
/// different 404 policies. Folding the whole `fetch` into one generic helper
/// would mean a parameter for each of those differences; folding in only what
/// is actually identical leaves each source's real work legible in its own
/// file.
enum VersionedNotesPage {
    /// What a 404 means for this upstream, which is not the same everywhere.
    enum NotFoundPolicy: Sendable {
        /// The page can appear later, so retry: Mozilla publishes Firefox and
        /// NSS pages after the build ships often enough that archiving a stub
        /// would freeze the gap in place.
        case transient

        /// The page is never coming, so archive once and stop. VideoLAN
        /// publishes a page per *release* and its four-component point
        /// releases never get one; retrying means the same 404 every day and
        /// no archive file, forever. The string is the stub body, and the
        /// fetched URL is appended to it.
        case cacheableStub(String)
    }

    enum Outcome: Sendable {
        case page(html: String, url: URL)
        case stub(ReleaseNotes)
        case failure(FetchError)
    }

    static func fetch(
        template: String,
        versionSlug: String,
        packageName: String,
        notFound: NotFoundPolicy,
        httpFetcher: HTTPFetching
    ) async -> Outcome {
        guard let url = URL(string: template.replacingOccurrences(of: "%s", with: versionSlug)) else {
            return .failure(.transient(reason: "\(packageName): invalid release notes URL"))
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(packageName): \(error)"))
        }

        if status == 404, case .cacheableStub(let message) = notFound {
            return .stub(ReleaseNotes(markdown: "_\(message) — \(url.absoluteString)_\n\n"))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(packageName): HTTP \(status)"))
        }

        // Named apart from the status: an undecodable or empty body is not an
        // HTTP failure, and reporting it as "HTTP 200" hides the real cause in
        // the one line a failed fetch ever surfaces.
        guard let html = String(data: data, encoding: .utf8) else {
            return .failure(.transient(reason: "\(packageName): release notes page is not valid UTF-8"))
        }
        guard !html.isEmpty else {
            return .failure(.transient(reason: "\(packageName): release notes page was empty"))
        }

        return .page(html: html, url: url)
    }
}
