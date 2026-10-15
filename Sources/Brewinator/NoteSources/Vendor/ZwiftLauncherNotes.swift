import Foundation

/// Zwift: no forge repo, and the release notes are a forum post. The cask
/// tracks the **Launcher** (`1.1.19,167476`), which Zwift announces on its
/// Discourse forum under "Zwift Launcher for macOS v 1.1.19 [October 2026]".
/// The title carries the month, so the URL cannot be built from the version;
/// the search endpoint finds the topic and its first post is the note.
///
/// Casks only, and the cask must be `zwift` itself.
struct ZwiftLauncherNotes: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        package.name == "zwift" && package.kind == .cask
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        let version = package.cleanCurrentVersion
        guard let searchURL = searchURL(version: version) else {
            return .failure(.transient(reason: "\(package.name): invalid search URL"))
        }

        let search: ForumSearch
        switch await decode(ForumSearch.self, from: searchURL, package: package) {
        case .failure(let error): return .failure(error)
        case .success(let value): search = value
        }

        // The trailing space keeps `1.1.1` from matching `1.1.19`.
        guard let topic = search.topics.first(where: { $0.title.contains("Launcher for macOS v \(version) ") }) else {
            return .failure(.transient(reason: "\(package.name): no forum topic for launcher \(version) yet"))
        }

        let topicURL = database.zwiftForumURL.appendingPathComponent("t/\(topic.id)")
        guard let postsURL = URL(string: topicURL.absoluteString + ".json") else {
            return .failure(.transient(reason: "\(package.name): invalid topic URL"))
        }

        let thread: ForumTopic
        switch await decode(ForumTopic.self, from: postsURL, package: package) {
        case .failure(let error): return .failure(error)
        case .success(let value): thread = value
        }

        let text = HTMLTextReducer.reduce(thread.postStream.posts.first?.cooked ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return .success(ReleaseNotes(markdown: "_Forum post had no readable text — \(topicURL.absoluteString)_\n\n"))
        }
        let markdown = MarkdownSection.body(text, maxLines: 40, link: topicURL.absoluteString, linkLabel: "Full post on forums.zwift.com")
        return .success(ReleaseNotes(markdown: markdown))
    }

    private func searchURL(version: String) -> URL? {
        var components = URLComponents(url: database.zwiftForumURL.appendingPathComponent("search.json"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "q", value: "Launcher for macOS v \(version)")]
        return components?.url
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL, package: OutdatedPackageInfo) async -> Result<T, FetchError> {
        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "\(package.name): \(error)"))
        }
        guard status == 200 else {
            return .failure(.transient(reason: "\(package.name): HTTP \(status)"))
        }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else {
            return .failure(.transient(reason: "\(package.name): invalid JSON"))
        }
        return .success(value)
    }
}

private struct ForumSearch: Decodable {
    struct Topic: Decodable {
        let id: Int
        let title: String
    }

    // Discourse omits `topics` entirely when nothing matched.
    let topics: [Topic]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topics = try container.decodeIfPresent([Topic].self, forKey: .topics) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case topics
    }
}

private struct ForumTopic: Decodable {
    struct Post: Decodable {
        let cooked: String
    }

    struct PostStream: Decodable {
        let posts: [Post]
    }

    let postStream: PostStream

    enum CodingKeys: String, CodingKey {
        case postStream = "post_stream"
    }
}
