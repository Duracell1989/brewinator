import Foundation

/// Steam: the cask version is `6.1,<build unix timestamp>,<sha1>`, and Valve
/// announces every client build as a "Steam Client Update - <Month> <day>"
/// post on the Steam Client news feed (app 593110, tag `patchnotes`). Neither
/// the cask nor the homepage names a forge, and the post title carries no
/// version, so the post is matched by time: the first one published at or after
/// the build timestamp, within `postWindow`.
///
/// No post inside the window means one of two things, told apart by the feed
/// itself rather than by a clock: when a *later* post exists, Valve shipped this
/// build without announcing it and the stub is permanent; otherwise the post is
/// simply not up yet and the fetch is transient.
///
/// The post body is Steam BBCode, converted to Markdown by `SteamBBCode`.
struct SteamClientUpdateNotes: NoteSource {
    /// Valve posts the same day or the next; three days leaves slack for a
    /// weekend without letting a later build's post be claimed by an earlier one.
    private static let postWindow = 3 * 24 * 60 * 60

    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "steam" && package.kind == .cask
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let feedURL = database.steamClientNewsURL

        guard let buildTime = Self.buildTimestamp(of: package.currentVersion) else {
            return .success(ReleaseNotes(markdown: "_Steam cask version carries no build timestamp — \(package.currentVersion)_\n\n"))
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(feedURL)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }
        guard let feed = try? JSONDecoder().decode(SteamNewsFeed.self, from: data) else {
            return .failure(.transient(reason: "\(package.name): news feed was not the expected JSON"))
        }

        let posts = feed.appnews.newsitems.sorted { $0.date < $1.date }
        guard let post = posts.first(where: { $0.date >= buildTime }) else {
            return .failure(.transient(reason: "\(package.name): no Steam Client Update post since build \(buildTime) yet"))
        }
        guard post.date - buildTime <= Self.postWindow else {
            return .success(ReleaseNotes(markdown: "_Valve posted no Steam Client Update for this build — \(feedURL.absoluteString)_\n\n"))
        }

        let text = SteamBBCode.markdown(from: post.contents)
        guard !text.isEmpty else {
            return .success(ReleaseNotes(markdown: "_Steam Client Update post had no readable text — \(post.url)_\n\n"))
        }
        return .success(ReleaseNotes(markdown: MarkdownSection.body("### \(post.title)\n\n" + text, maxLines: 80, link: post.url, linkLabel: "Full post")))
    }

    /// The second comma-separated component of `6.1,1791918634,<sha1>`.
    private static func buildTimestamp(of version: String) -> Int? {
        let parts = version.split(separator: ",")
        guard parts.count >= 2 else { return nil }
        return Int(parts[1])
    }
}

private struct SteamNewsFeed: Decodable {
    let appnews: AppNews

    struct AppNews: Decodable {
        let newsitems: [SteamNewsPost]
    }
}

private struct SteamNewsPost: Decodable {
    let title: String
    let url: String
    let contents: String
    let date: Int
}
