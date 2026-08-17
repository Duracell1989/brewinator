import Foundation

/// Android Studio: a Google CDN blog, no forge. Post titles use codenames
/// ("Android Studio Quail 3 now available"), and the codename is embedded
/// only in the cask's **raw** version field (`2026.1.3.7,quail3,AI-261…`) —
/// `VersionMatcher.cleanVersion` strips that field, so this must read
/// `package.currentVersion`, not `cleanCurrentVersion`. Newest post is the
/// fallback when the codename can't be extracted or doesn't match any
/// title.
struct AndroidStudioBlog: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "android-studio"
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let url = database.androidStudioFeedURL

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200, !data.isEmpty else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }
        guard let feed = try? JSONDecoder().decode(RawBloggerFeed.self, from: data) else {
            return .failure(.transient(reason: "\(package.name): invalid JSON"))
        }

        let entries = feed.feed.entry ?? []
        var content: String = ""
        var link: String?

        if let codename = Self.codename(from: package.currentVersion) {
            let targetTitle = "Android Studio \(codename) now available"
            if let matched = entries.first(where: { $0.title?.text == targetTitle }) {
                content = matched.content?.text ?? ""
                link = matched.link?.first { $0.rel == "alternate" }?.href
            }
        }

        if content.isEmpty {
            content = entries.first?.content?.text ?? ""
            link = entries.first?.link?.first { $0.rel == "alternate" }?.href
        }

        guard !content.isEmpty else {
            return .success(ReleaseNotes(markdown: "_No matching post found — https://androidstudio.googleblog.com/_\n\n"))
        }

        var markdown = ""
        let text = HTMLTextReducer.reduce(content)
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText {
            markdown += text.firstLines(40)
            markdown += "\n\n"
        }
        if let link, !link.isEmpty {
            markdown += "[Full announcement](\(link))\n\n"
        } else if !hasText {
            // Matches JetBrainsProducts' equivalent fallback: an image-only
            // post with no alternate link would otherwise reduce to empty
            // markdown, which ArchiveStore.write() no-ops on — the post
            // would then be silently re-fetched and re-skipped every day.
            markdown += "_No readable content in the matched post — https://androidstudio.googleblog.com/_\n\n"
        }
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Extracts a codename field (e.g. `quail3`, `quail2-patch1`) from a
    /// comma-separated raw cask version and normalises it to the blog's
    /// title form ("Quail 3", "Quail 2 Patch 1"). Nil if no field matches.
    private static func codename(from rawVersion: String) -> String? {
        guard let token = rawVersion.components(separatedBy: ",").first(where: isCodenameField) else { return nil }

        let spaced = token.replacingOccurrences(of: "-", with: " ")
        let withDigitSplit = spaced.replacingOccurrences(of: #"([A-Za-z])([0-9])"#, with: "$1 $2", options: .regularExpression)

        let words = withDigitSplit.split(separator: " ")
        let titled = words.map { word -> String in
            if word.lowercased() == "rc" { return "RC" }
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst().lowercased()
        }
        return titled.joined(separator: " ")
    }

    private static func isCodenameField(_ field: String) -> Bool {
        let pattern = #"^[A-Za-z]+[0-9]+(-[A-Za-z]+[0-9]*)*$"#
        return field.range(of: pattern, options: .regularExpression) != nil
    }
}

private struct RawBloggerText: Decodable {
    let text: String?

    enum CodingKeys: String, CodingKey {
        case text = "$t"
    }
}

private struct RawBloggerLink: Decodable {
    let rel: String?
    let href: String?
}

private struct RawBloggerEntry: Decodable {
    let title: RawBloggerText?
    let content: RawBloggerText?
    let link: [RawBloggerLink]?
}

private struct RawBloggerFeedBody: Decodable {
    let entry: [RawBloggerEntry]?
}

private struct RawBloggerFeed: Decodable {
    let feed: RawBloggerFeedBody
}
