import Foundation
import Testing

@testable import Brewinator

private let template = "https://example.test/notes/%s.html"
private let pageURL = URL(string: "https://example.test/notes/1.2.3.html")!

private func fetch(
    _ fetcher: FakeHTTPFetcher,
    slug: String = "1.2.3",
    notFound: VersionedNotesPage.NotFoundPolicy = .transient,
    template: String = template
) async -> VersionedNotesPage.Outcome {
    await VersionedNotesPage.fetch(
        template: template,
        versionSlug: slug,
        packageName: "pkg",
        notFound: notFound,
        httpFetcher: fetcher
    )
}

@Suite("VersionedNotesPage")
struct VersionedNotesPageTests {
    @Test("the version fills the template and a 200 returns the page with its URL")
    func successReturnsPageAndURL() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, string: "<html>notes</html>", statusCode: 200)

        guard case .page(let html, let url) = await fetch(fetcher) else {
            Issue.record("expected a page")
            return
        }
        #expect(html == "<html>notes</html>")
        #expect(url == pageURL)
    }

    /// The reason each upstream states its own policy: Mozilla publishes pages
    /// late, VideoLAN never publishes one for a four-component point release.
    @Test("a 404 is transient under .transient and a stub under .cacheableStub")
    func notFoundFollowsThePolicy() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, data: Data(), statusCode: 404)

        guard case .failure = await fetch(fetcher, notFound: .transient) else {
            Issue.record("expected a transient failure")
            return
        }

        guard case .stub(let notes) = await fetch(fetcher, notFound: .cacheableStub("No page for this version")) else {
            Issue.record("expected a stub")
            return
        }
        #expect(notes.markdown.contains("No page for this version"))
        #expect(notes.markdown.contains(pageURL.absoluteString))
    }

    @Test("a non-404 error status is transient and names the status")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: pageURL, data: Data(), statusCode: 500)

        guard case .failure(.transient(let reason)) = await fetch(fetcher, notFound: .cacheableStub("unused")) else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(reason.contains("HTTP 500"))
    }

    @Test("a transport error is transient")
    func transportErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.fail(pageURL)

        guard case .failure = await fetch(fetcher) else {
            Issue.record("expected a transient failure")
            return
        }
    }

    /// The whole point of splitting these off the status guard: reporting an
    /// undecodable body as "HTTP 200" hides the real cause in the one line a
    /// failed fetch ever surfaces.
    @Test("an undecodable or empty 200 body names itself rather than the status")
    func bodyProblemsNameThemselves() async {
        var undecodable = FakeHTTPFetcher()
        undecodable.respond(to: pageURL, data: Data([0xFF, 0xFE, 0xFF]), statusCode: 200)
        guard case .failure(.transient(let utf8Reason)) = await fetch(undecodable) else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(utf8Reason.contains("UTF-8"))
        #expect(!utf8Reason.contains("HTTP 200"))

        var empty = FakeHTTPFetcher()
        empty.respond(to: pageURL, string: "", statusCode: 200)
        guard case .failure(.transient(let emptyReason)) = await fetch(empty) else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(emptyReason.contains("empty"))
    }

    /// `ResolutionDatabase.testDefaults` leaves every template empty, so an
    /// unconfigured source reaches here with nothing to fill - it must say so
    /// rather than trap on a force-unwrapped URL.
    @Test("a template that cannot form a URL fails transiently instead of trapping")
    func invalidTemplateFails() async {
        guard case .failure(.transient(let reason)) = await fetch(FakeHTTPFetcher(), template: "") else {
            Issue.record("expected a transient failure")
            return
        }
        #expect(reason.contains("invalid release notes URL"))
    }
}
