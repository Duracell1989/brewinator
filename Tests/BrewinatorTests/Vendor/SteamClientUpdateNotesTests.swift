import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(
    steamClientNewsURL: URL(string: "https://example.test/steam")!
)

private let feedURL = URL(string: "https://example.test/steam")!

private func package(buildTime: String = "1791918634", name: String = "steam", kind: PackageKind = .cask) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: name, installedVersion: "6.0", currentVersion: "6.1,\(buildTime),984652b88a9737e3f4e77c656d9ffa67d5042c2c", kind: kind)
}

private func source(status: Int = 200) throws -> SteamClientUpdateNotes {
    var fetcher = FakeHTTPFetcher()
    fetcher.respond(to: feedURL, data: try Fixture.data("steam-client-news-sample", extension: "json"), statusCode: status)
    return SteamClientUpdateNotes(httpFetcher: fetcher, database: testDatabase)
}

@Suite("SteamClientUpdateNotes")
struct SteamClientUpdateNotesTests {
    @Test("canHandle matches only the steam cask")
    func canHandle() throws {
        let steam = try source()
        #expect(steam.canHandle(package()))
        #expect(!steam.canHandle(package(kind: .formula)))
        #expect(!steam.canHandle(package(name: "steamcmd")))
    }

    @Test("real fixture: the first post at or after the build time, BBCode rendered, media dropped")
    func realFixtureSucceeds() async throws {
        let result = await (try source()).fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### Steam Client Update - October 13th"))
        #expect(notes.markdown.contains("**Homescreen - Big Picture Mode**"))
        #expect(notes.markdown.contains("- Added Personal Calendar"))
        #expect(!notes.markdown.contains("[p]"))
        #expect(!notes.markdown.contains("[img"))
        #expect(!notes.markdown.contains("STEAM_CLAN_LOC_IMAGE"))
        #expect(!notes.markdown.contains("October 21st"))
        #expect(notes.markdown.contains("[Full post]("))
    }

    @Test("nested lists indent")
    func nestedListsIndent() {
        let text = SteamBBCode.markdown(from: "[list][*][p]Outer[/p][list][*][p]Inner[/p][/*][/list][/*][/list]")
        #expect(text == "- Outer\n  - Inner")
    }

    @Test("a build older than any post, with the next post beyond the window, is a permanent stub")
    func unannouncedBuildIsStub() async throws {
        // Two days after the October 13th post, before the October 21st one.
        let result = await (try source()).fetch(package(buildTime: "1792100000"))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Valve posted no Steam Client Update"))
    }

    @Test("a build newer than every post is transient - the post is not up yet")
    func newestBuildIsTransient() async throws {
        let result = await (try source()).fetch(package(buildTime: "1799999999"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a version without a timestamp archives a stub")
    func noTimestampIsStub() async throws {
        let result = await (try source()).fetch(OutdatedPackageInfo(name: "steam", installedVersion: "6.0", currentVersion: "6.1", kind: .cask))
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("no build timestamp"))
    }

    @Test("a non-200 status is transient")
    func badStatusIsTransient() async throws {
        let result = await (try source(status: 503)).fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
