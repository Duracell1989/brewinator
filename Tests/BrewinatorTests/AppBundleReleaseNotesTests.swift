import Foundation
import Testing

@testable import Brewinator

private let feed = URL(string: "https://proton.me/download/drive/macos/appcast.xml")!
private let bundlePath = "/Applications/Proton Drive.app"

private func protonDrive(current: String = "3.0.3", kind: PackageKind = .cask) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "proton-drive", installedVersion: "3.0.2", currentVersion: current, kind: kind)
}

private func locator(html: String?, feedURL: URL?) -> FakeAppBundleLocator {
    var locator = FakeAppBundleLocator()
    locator.register(
        "proton-drive",
        bundle: InstalledAppBundle(path: bundlePath, releaseNotesHTML: html, sparkleFeedURL: feedURL)
    )
    return locator
}

@Suite("AppBundleReleaseNotes")
struct AppBundleReleaseNotesTests {
    @Test("canHandle is false for a formula and for a cask with no notes-bearing bundle")
    func canHandle() throws {
        let html = try Fixture.string("app-bundle-release-notes-sample", extension: "html")
        let source = AppBundleReleaseNotes(locator: locator(html: html, feedURL: nil), httpFetcher: FakeHTTPFetcher())

        #expect(source.canHandle(protonDrive()))
        #expect(!source.canHandle(protonDrive(kind: .formula)))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .cask)))
    }

    // The fetcher has no registered responses, so reaching for the feed here
    // would fail the test rather than quietly return second-best notes.
    @Test("the bundled changelog's matching section wins, without touching the network")
    func bundledSectionWins() async throws {
        let html = try Fixture.string("app-bundle-release-notes-sample", extension: "html")
        let source = AppBundleReleaseNotes(locator: locator(html: html, feedURL: feed), httpFetcher: FakeHTTPFetcher())

        guard case .success(let notes) = await source.fetch(protonDrive()) else {
            Issue.record("expected success")
            return
        }
        #expect(notes.markdown.contains("- Fixes sync after a long period of inactivity"))
        #expect(!notes.markdown.contains("Fixes a crash during app launch"))
        #expect(notes.markdown.contains(bundlePath))
    }

    @Test("the inlined stylesheet never reaches the notes")
    func stylesheetDropped() async throws {
        let html = try Fixture.string("app-bundle-release-notes-sample", extension: "html")
        let source = AppBundleReleaseNotes(locator: locator(html: html, feedURL: nil), httpFetcher: FakeHTTPFetcher())

        guard case .success(let notes) = await source.fetch(protonDrive()) else {
            Issue.record("expected success")
            return
        }
        #expect(!notes.markdown.contains("font-family"))
        #expect(!notes.markdown.contains("HelveticaNeue"))
    }

    @Test("a bundle older than the upgrade falls through to the discovered Sparkle feed")
    func fallsThroughToFeed() async throws {
        let html = try Fixture.string("app-bundle-release-notes-sample", extension: "html")
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feed, data: try Fixture.data("sparkle-appcast-description-sample", extension: "xml"), statusCode: 200)
        let source = AppBundleReleaseNotes(locator: locator(html: html, feedURL: feed), httpFetcher: fetcher)

        guard case .success(let notes) = await source.fetch(protonDrive(current: "6.5.1")) else {
            Issue.record("expected success")
            return
        }
        #expect(notes.markdown.contains("Kill switch no longer leaks on wake"))
    }

    @Test("an app with no bundled changelog resolves through its SUFeedURL alone")
    func feedOnlyBundle() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: feed, data: try Fixture.data("sparkle-appcast-description-sample", extension: "xml"), statusCode: 200)
        let source = AppBundleReleaseNotes(locator: locator(html: nil, feedURL: feed), httpFetcher: fetcher)

        guard case .success(let notes) = await source.fetch(protonDrive(current: "6.5.1")) else {
            Issue.record("expected success")
            return
        }
        #expect(notes.markdown.contains("Kill switch no longer leaks on wake"))
    }

    @Test("no section and no feed lands on the same placeholder as before, not an error")
    func nothingUsableIsThePlaceholder() async throws {
        let html = try Fixture.string("app-bundle-release-notes-sample", extension: "html")
        let source = AppBundleReleaseNotes(locator: locator(html: html, feedURL: nil), httpFetcher: FakeHTTPFetcher())

        guard case .success(let notes) = await source.fetch(protonDrive(current: "9.9.9")) else {
            Issue.record("expected success")
            return
        }
        #expect(notes == Resolver.noForgeDetected)
    }
}
