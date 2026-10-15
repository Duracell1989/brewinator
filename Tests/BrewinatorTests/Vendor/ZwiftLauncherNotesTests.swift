import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(zwiftForumURL: URL(string: "https://example.test/zwift")!)

private func package(kind: PackageKind = .cask, current: String = "1.1.19,167476") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "zwift", installedVersion: "1.1.18,164972", currentVersion: current, kind: kind)
}

private let searchURL = URL(string: "https://example.test/zwift/search.json?q=Launcher%20for%20macOS%20v%201.1.19")!
private let topicURL = URL(string: "https://example.test/zwift/t/671673.json")!

@Suite("ZwiftLauncherNotes")
struct ZwiftLauncherNotesTests {
    @Test("canHandle matches only the zwift cask")
    func canHandle() {
        let source = ZwiftLauncherNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(package(kind: .formula)))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "zwift-companion", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    @Test("real fixtures: topic found by title, first post reduced to the macOS notes")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: searchURL, data: try Fixture.data("zwift-forum-search-sample", extension: "json"), statusCode: 200)
        fetcher.respond(to: topicURL, data: try Fixture.data("zwift-forum-topic-sample", extension: "json"), statusCode: 200)
        let source = ZwiftLauncherNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Improved stability for macOS versions prior to OS15"))
        #expect(notes.markdown.contains("Mac-only release"))
        #expect(!notes.markdown.contains("<li>"))
        #expect(notes.markdown.contains("[Full post on forums.zwift.com](https://example.test/zwift/t/671673)"))
    }

    @Test("a search with no matching title is transient - the post may not be up yet")
    func noMatchingTopicIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: searchURL, string: #"{"topics":[{"id":1,"title":"Zwift Launcher for macOS v 1.1.190 [October 2026]"}]}"#, statusCode: 200)
        let source = ZwiftLauncherNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("Discourse omits topics when nothing matched")
    func missingTopicsKeyIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: searchURL, string: "{}", statusCode: 200)
        let source = ZwiftLauncherNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a non-200 search is transient")
    func searchHTTPErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: searchURL, data: Data(), statusCode: 503)
        let source = ZwiftLauncherNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("an empty first post is a readable stub")
    func emptyPostIsStub() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: searchURL, string: #"{"topics":[{"id":671673,"title":"Zwift Launcher for macOS v 1.1.19 [October 2026]"}]}"#, statusCode: 200)
        fetcher.respond(to: topicURL, string: #"{"post_stream":{"posts":[{"cooked":""}]}}"#, statusCode: 200)
        let source = ZwiftLauncherNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("no readable text"))
    }
}
