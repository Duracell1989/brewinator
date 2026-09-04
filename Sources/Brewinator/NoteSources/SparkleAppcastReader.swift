import Foundation

/// Fetches a Sparkle appcast and turns the item matching a target version into
/// notes. Shared by `SparkleAppcast`, which reads the feed address from
/// `ResolutionDatabase`, and `AppBundleReleaseNotes`, which discovers it from
/// the installed app's `SUFeedURL` - the two differ only in where the address
/// comes from.
///
/// Sparkle publishes notes two ways and both are read: a
/// `sparkle:releaseNotesLink` pointing at an HTML page (Vivaldi), or the notes
/// inlined in the item's `<description>` as CDATA HTML (ProtonVPN, QLMarkdown,
/// Telegram). The link wins when an item carries both - it is the canonical
/// copy, and it is linkable from the archive.
struct SparkleAppcastReader: Sendable {
    /// One `<item>`, reduced to the three fields that matter. Items carrying
    /// neither kind of notes never become one.
    struct Item: Sendable, Equatable {
        let version: String
        let notesLink: String?
        let descriptionHTML: String?
    }

    private let httpFetcher: HTTPFetching

    init(httpFetcher: HTTPFetching) {
        self.httpFetcher = httpFetcher
    }

    func notes(feed: URL, targetVersion: String) async -> Result<ReleaseNotes, FetchError> {
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

        let items = Self.items(in: appcast)
        guard let match = VersionMatcher.matchRelease(in: items, version: targetVersion) else {
            return .success(ReleaseNotes(markdown: "_No release notes in the Sparkle feed — \(feed.absoluteString)_\n\n"))
        }

        if let link = match.notesLink, let notesURL = URL(string: link) {
            return await notesFromPage(notesURL)
        }
        guard let html = match.descriptionHTML else {
            return .success(ReleaseNotes(markdown: "_No release notes in the Sparkle feed — \(feed.absoluteString)_\n\n"))
        }

        let text = HTMLTextReducer.reduce(html)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .success(ReleaseNotes(markdown: "_Release notes in the Sparkle feed had no readable text — \(feed.absoluteString)_\n\n"))
        }
        return .success(ReleaseNotes(markdown: MarkdownSection.body(text, maxLines: 40)))
    }

    private func notesFromPage(_ notesURL: URL) async -> Result<ReleaseNotes, FetchError> {
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
        return .success(ReleaseNotes(markdown: MarkdownSection.body(text, maxLines: 40, link: notesURL.absoluteString, linkLabel: "Full release notes")))
    }

    /// Records are split on `</item>`, then cut back to the last `<item` in
    /// each - the text before the first `</item>` is the channel header *plus*
    /// the first item, and a channel-level `<title>`/`<description>` (ProtonVPN
    /// has one) would otherwise be read as that item's own.
    static func items(in appcast: String) -> [Item] {
        appcast.components(separatedBy: "</item>").compactMap { chunk in
            guard let start = chunk.range(of: "<item", options: .backwards) else { return nil }
            let record = String(chunk[start.lowerBound...])

            let link = tagValue(in: record, tag: "sparkle:releaseNotesLink").trimmingCharacters(in: .whitespacesAndNewlines)
            let description = (elementContent(in: record, tag: "description") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !link.isEmpty || !description.isEmpty else { return nil }

            return Item(
                version: version(in: record),
                notesLink: link.isEmpty ? nil : link,
                descriptionHTML: description.isEmpty ? nil : description
            )
        }
    }

    /// Child elements first, then the same two names as `<enclosure>`
    /// attributes - Telegram and ProtonVPN publish the version only there -
    /// and `<title>` last, run through the changelog-heading reader so a
    /// "Version 6.5.1" title still compares as "6.5.1".
    private static func version(in record: String) -> String {
        let candidates = [
            tagValue(in: record, tag: "sparkle:shortVersionString"),
            tagValue(in: record, tag: "sparkle:version"),
            attributeValue(in: record, name: "sparkle:shortVersionString"),
            attributeValue(in: record, name: "sparkle:version"),
        ]
        if let found = candidates.first(where: { !$0.isEmpty }) {
            return found.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let title = tagValue(in: record, tag: "title").trimmingCharacters(in: .whitespacesAndNewlines)
        return VersionSectionExtractor.headingVersion(of: title) ?? title
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
        guard let open = openTagRange(in: text, tag: tag) else { return "" }
        let afterOpen = text[open.upperBound...]
        if let closeIndex = afterOpen.firstIndex(of: "<") {
            return String(afterOpen[afterOpen.startIndex..<closeIndex])
        }
        return String(afterOpen)
    }

    /// Multi-line element content, up to the matching `</tag>`, with a CDATA
    /// wrapper unwrapped - that is how every appcast that inlines its notes
    /// writes them, and `tagValue` would stop at the first `<` inside the HTML.
    private static func elementContent(in text: String, tag: String) -> String? {
        guard let open = openTagRange(in: text, tag: tag) else { return nil }
        let rest = text[open.upperBound...]
        guard let close = rest.range(of: "</\(tag)>") else { return nil }
        var content = String(rest[rest.startIndex..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

        if content.hasPrefix("<![CDATA["), let end = content.range(of: "]]>", options: .backwards) {
            let body = content.dropFirst("<![CDATA[".count)
            content = String(body[body.startIndex..<end.lowerBound])
        }
        return content
    }

    /// The range of a `<tag ...>` opening element, skipping same-prefix false
    /// matches - the shared half of `tagValue` and `elementContent`.
    private static func openTagRange(in text: String, tag: String) -> Range<String.Index>? {
        let openPrefix = "<\(tag)"
        var searchRange = text.startIndex..<text.endIndex
        while let prefixRange = text.range(of: openPrefix, range: searchRange) {
            let afterPrefix = prefixRange.upperBound
            searchRange = afterPrefix..<text.endIndex
            guard afterPrefix < text.endIndex else { continue }
            let boundary = text[afterPrefix]
            guard boundary == ">" || boundary.isWhitespace else { continue }
            guard let tagCloseIndex = text[afterPrefix...].firstIndex(of: ">") else { return nil }
            return prefixRange.lowerBound..<text.index(after: tagCloseIndex)
        }
        return nil
    }

    /// An XML attribute's value anywhere in the record, single or double
    /// quoted. Empty string when absent, matching `tagValue`.
    private static func attributeValue(in text: String, name: String) -> String {
        let pattern = "\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*[\"']([^\"']*)[\"']"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range), let valueRange = Range(match.range(at: 1), in: text) else {
            return ""
        }
        return String(text[valueRange])
    }
}

/// Lets the appcast items reuse the same match-or-fall-back-to-newest rule the
/// forge sources use, rather than a second version-matching implementation.
extension SparkleAppcastReader.Item: VersionTagged {
    var tagName: String { version }
}
