import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(
    sqliteNotesURLTemplate: "https://example.test/sqlite/%s.html"
)

private func package(kind: PackageKind = .formula) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "sqlite", installedVersion: "3.53.4", currentVersion: "3.54.0", kind: kind)
}

private let notesURL = URL(string: "https://example.test/sqlite/3_54_0.html")!

@Suite("SQLiteReleaseNotes")
struct SQLiteReleaseNotesTests {
    @Test("canHandle matches only the sqlite formula")
    func canHandle() {
        let source = SQLiteReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(package(kind: .cask)))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "sqlite-utils", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("real fixture: dots become underscores, heading kept, notes reduced, hashes and page chrome dropped")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: try Fixture.data("sqlite-release-notes-sample", extension: "html"), statusCode: 200)
        let source = SQLiteReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### SQLite Release 3.54.0 On 2026-10-09"))
        #expect(notes.markdown.contains("diskused()"))
        #expect(notes.markdown.contains("CLI prompt strings may contain"))
        #expect(notes.markdown.contains("Drop support for WindowsXP"))
        #expect(notes.markdown.contains("About 4% faster"))
        #expect(!notes.markdown.contains("SQLITE_SOURCE_ID"))
        #expect(!notes.markdown.contains("SHA3-256"))
        #expect(!notes.markdown.contains("toggle_div"))
        #expect(notes.markdown.contains("[Full release notes](\(notesURL.absoluteString))"))
    }

    @Test("a 404 is transient - the formula can be bumped before the release log is published")
    func notFoundIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, data: Data(), statusCode: 404)
        let source = SQLiteReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a 200 page with no release heading is a cacheable stub")
    func noHeadingIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: notesURL, string: "<html><body><p>Nothing here.</p></body></html>", statusCode: 200)
        let source = SQLiteReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No release notes found"))
        #expect(notes.markdown.contains(notesURL.absoluteString))
    }
}
