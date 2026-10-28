import Foundation
import Testing

@testable import Brewinator

private let testDatabase = ResolutionDatabase.testDefaults.with(
    microsoftOpenJDKReleaseNotesURL: URL(string: "https://example.test/openjdk")!
)

private let pageURL = URL(string: "https://example.test/openjdk")!

private func package(name: String = "microsoft-openjdk@21", version: String = "21.0.13.0.2", kind: PackageKind = .cask) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: name, installedVersion: "21.0.12.1", currentVersion: version, kind: kind)
}

@Suite("MicrosoftOpenJDKReleaseNotes")
struct MicrosoftOpenJDKReleaseNotesTests {
    @Test("canHandle matches the unversioned and every pinned cask, nothing else")
    func canHandle() {
        let source = MicrosoftOpenJDKReleaseNotes(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package(name: "microsoft-openjdk")))
        #expect(source.canHandle(package(name: "microsoft-openjdk@21")))
        #expect(source.canHandle(package(name: "microsoft-openjdk@25")))
        #expect(!source.canHandle(package(kind: .formula)))
        #expect(!source.canHandle(package(name: "openjdk@21")))
    }

    @Test("real fixture: the exact respin section, advisories kept, build table and neighbours dropped")
    func realFixtureSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, data: try Fixture.data("microsoft-openjdk-release-notes-sample", extension: "html"), statusCode: 200)
        let source = MicrosoftOpenJDKReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("### OpenJDK 21.0.13.0.2"))
        #expect(notes.markdown.contains("After respins"))
        #expect(notes.markdown.contains("OpenJDK Vulnerability Advisory - Oct. 20"))
        #expect(!notes.markdown.contains("Boot JDK"))
        #expect(!notes.markdown.contains("21.0.12.1+1-LTS"))
        #expect(!notes.markdown.contains("Other major line"))
        #expect(notes.markdown.contains("[Full release notes](\(pageURL.absoluteString)#openjdk-2101302)"))
    }

    @Test("a version with no section yet is transient")
    func missingSectionIsTransient() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, data: try Fixture.data("microsoft-openjdk-release-notes-sample", extension: "html"), statusCode: 200)
        let source = MicrosoftOpenJDKReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package(version: "21.0.99"))
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("a non-200 status is transient")
    func badStatusIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, data: Data(), statusCode: 503)
        let source = MicrosoftOpenJDKReleaseNotes(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }
}
