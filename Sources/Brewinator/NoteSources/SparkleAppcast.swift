import Foundation

/// Sparkle-appcast notes — generic and reusable for any Sparkle-updated cask.
/// Matches the `<item>` by `sparkle:shortVersionString` / `sparkle:version` /
/// `<title>` (newest item as fallback), fetches its `releaseNotesLink` page,
/// and reduces it to text.
struct SparkleAppcast: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.sparkleFeeds[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let feed = database.sparkleFeeds[package.name] else {
            return .success(Resolver.noForgeDetected)
        }

        let appcastData: Data
        let appcastStatus: Int
        do {
            (appcastData, appcastStatus) = try await httpFetcher.fetch(feed)
        } catch {
            return .failure(.transient(reason: "Sparkle feed \(feed): \(error)"))
        }
        guard appcastStatus == 200, !appcastData.isEmpty, let appcast = String(data: appcastData, encoding: .utf8) else {
            return .failure(.transient(reason: "Sparkle feed \(feed): HTTP \(appcastStatus)"))
        }

        guard let notesURL = Self.matchedNotesLink(in: appcast, targetVersion: package.cleanCurrentVersion) else {
            return .success(ReleaseNotes(markdown: "_No release-notes link in the Sparkle feed — \(feed.absoluteString)_\n\n"))
        }

        let notesData: Data
        let notesStatus: Int
        do {
            (notesData, notesStatus) = try await httpFetcher.fetch(notesURL)
        } catch {
            return .failure(.transient(reason: "Sparkle notes page \(notesURL): \(error)"))
        }
        guard notesStatus == 200, !notesData.isEmpty, let html = String(data: notesData, encoding: .utf8) else {
            return .failure(.transient(reason: "Sparkle notes page \(notesURL): HTTP \(notesStatus)"))
        }

        let text = HTMLTextReducer.reduce(html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Release-notes page had no readable text — \(notesURL.absoluteString)_\n\n"))
        }

        let markdown = MarkdownSection.body(text, maxLines: 40, link: notesURL.absoluteString, linkLabel: "Full release notes")
        return .success(ReleaseNotes(markdown: markdown))
    }

    /// Records are split on `</item>`; the matched item's (or first item
    /// with a notes link's) `sparkle:releaseNotesLink` wins.
    private static func matchedNotesLink(in appcast: String, targetVersion: String) -> URL? {
        var first: String?
        var want: String?

        for item in appcast.components(separatedBy: "</item>") {
            let link = tagValue(in: item, tag: "sparkle:releaseNotesLink")
            guard !link.isEmpty else { continue }

            var version = tagValue(in: item, tag: "sparkle:shortVersionString")
            if version.isEmpty { version = tagValue(in: item, tag: "sparkle:version") }
            if version.isEmpty { version = tagValue(in: item, tag: "title") }

            if first == nil { first = link }
            if version == targetVersion && want == nil { want = link }
        }

        guard let resolved = (want ?? first)?.trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty else {
            return nil
        }
        return URL(string: resolved)
    }

    /// A single-line element's text content, e.g. `<title>Foo</title>` ->
    /// `"Foo"`, also matching a tag carrying attributes (e.g.
    /// `<sparkle:releaseNotesLink xml:lang="en">`, a documented, common
    /// Sparkle appcast pattern) — not just the bare `<tag>` form. Loops past
    /// same-prefix false matches (e.g. `title` inside `titleFoo`) by requiring
    /// the character right after the tag name to be `>` or whitespace. Empty
    /// string if the tag isn't present — treats "not found" and "found but
    /// empty" the same way.
    private static func tagValue(in text: String, tag: String) -> String {
        let openPrefix = "<\(tag)"
        var searchRange = text.startIndex..<text.endIndex
        while let prefixRange = text.range(of: openPrefix, range: searchRange) {
            let afterPrefix = prefixRange.upperBound
            searchRange = afterPrefix..<text.endIndex
            guard afterPrefix < text.endIndex else { continue }
            let boundary = text[afterPrefix]
            guard boundary == ">" || boundary.isWhitespace else { continue }
            guard let tagCloseIndex = text[afterPrefix...].firstIndex(of: ">") else { return "" }
            let afterOpen = text[text.index(after: tagCloseIndex)...]
            if let closeIndex = afterOpen.firstIndex(of: "<") {
                return String(afterOpen[afterOpen.startIndex..<closeIndex])
            }
            return String(afterOpen)
        }
        return ""
    }
}
