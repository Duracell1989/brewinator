import Foundation
import Testing

@testable import Brewinator

private let compareURL = URL(string: "https://api.github.com/repos/sharkdp/bat/compare/v0.25.0...v0.26.0")!
private let commitsURL = URL(string: "https://api.github.com/repos/sharkdp/bat/commits?sha=v0.26.0&per_page=20")!

private let testDatabase = ResolutionDatabase.testDefaults.with(
    tagCompareSpecs: [
        "bat-notes": TagCompareSpec(repo: "sharkdp/bat", tagTemplate: "v%s", subpath: nil)
    ]
)

private func package(current: String = "0.26.0", installed: String = "0.25.0") -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "bat-notes", installedVersion: installed, currentVersion: current, kind: .formula)
}

private let gitlabCompareURL = URL(
    string: "https://gitlab.freedesktop.org/api/v4/projects/xorg%2Fproto%2Fxorgproto/repository/compare?from=xorgproto-2025.1&to=xorgproto-2026.1"
)!
private let gitlabCommitsURL = URL(
    string: "https://gitlab.freedesktop.org/api/v4/projects/xorg%2Fproto%2Fxorgproto/repository/commits?ref_name=xorgproto-2026.1&per_page=20"
)!

private let gitlabDatabase = ResolutionDatabase.testDefaults.with(
    tagCompareSpecs: [
        "xorgproto": TagCompareSpec(
            repo: "xorg/proto/xorgproto",
            tagTemplate: "xorgproto-%s",
            subpath: nil,
            gitlabHost: "gitlab.freedesktop.org"
        )
    ]
)

private func gitlabPackage() -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: "xorgproto", installedVersion: "2025.1", currentVersion: "2026.1", kind: .formula)
}

@Suite("TagCompare")
struct TagCompareTests {
    @Test("canHandle is true only for a name registered in tagCompareSpecs")
    func canHandle() {
        let source = TagCompare(httpFetcher: FakeHTTPFetcher(), database: testDatabase)
        #expect(source.canHandle(package()))
        #expect(!source.canHandle(OutdatedPackageInfo(name: "other", installedVersion: "1", currentVersion: "2", kind: .formula)))
    }

    @Test("compare API succeeds: real fixture decodes to a bulleted, deduped commit list with a diff link")
    func compareSucceedsWithRealFixture() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, data: try Fixture.data("github-compare-sample", extension: "json"), statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("- "))
        #expect(notes.markdown.contains("[Full diff on GitHub](https://github.com/sharkdp/bat/compare/v0.25.0...v0.26.0)"))
    }

    @Test("more than 40 deduped subjects are capped, with a truncation notice referencing total_commits")
    func truncatesPast40WithNotice() async {
        let messages = (1...45).map { "Fix issue number \($0)" }
        let commits = messages.map { #"{"commit": {"message": "\#($0)"}}"# }.joined(separator: ",")
        let json = #"{"total_commits": 100, "commits": ["# + commits + "]}"
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, string: json, statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("Showing 40 of 45 commits (100 in range, whole repo)"))
        #expect(notes.markdown.contains("- Fix issue number 1\n"))
        #expect(!notes.markdown.contains("Fix issue number 41"))
    }

    @Test("a 404 on compare falls back to the commit list at the current tag")
    func compareNotFoundFallsBackToCommits() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, data: Data(), statusCode: 404)
        fetcher.respond(to: commitsURL, data: try Fixture.data("github-commits-sample", extension: "json"), statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("[Full diff on GitHub](https://github.com/sharkdp/bat/commits/v0.26.0)"))
    }

    @Test("a 404 on both compare and the commits fallback is a cacheable no-tag-found message")
    func bothNotFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, data: Data(), statusCode: 404)
        fetcher.respond(to: commitsURL, data: Data(), statusCode: 404)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No tag found for 0.26.0"))
    }

    @Test("a 500 on compare is transient")
    func serverErrorIsTransient() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, data: Data(), statusCode: 500)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .failure = result else {
            Issue.record("expected failure, got \(result)")
            return
        }
    }

    @Test("merge commits and version-bump noise are filtered out, duplicates collapsed")
    func noiseFilteredAndDeduped() async {
        let json = """
            {
              "total_commits": 4,
              "commits": [
                {"commit": {"message": "Merge branch 'main' into feature"}},
                {"commit": {"message": "Fix crash on empty input"}},
                {"commit": {"message": "Fix crash on empty input"}},
                {"commit": {"message": "Bump version to 0.26.0"}}
              ]
            }
            """
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: compareURL, string: json, statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: testDatabase)

        let result = await source.fetch(package())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("- Fix crash on empty input"))
        #expect(!notes.markdown.contains("Merge branch"))
        #expect(!notes.markdown.contains("Bump version"))
        #expect(notes.markdown.components(separatedBy: "Fix crash on empty input").count == 2)
    }

    @Test("GitLab: nested project path is one percent-encoded segment, fixture decodes, link names the host")
    func gitlabCompareSucceeds() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: gitlabCompareURL, data: try Fixture.data("gitlab-compare-sample", extension: "json"), statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: gitlabDatabase)

        let result = await source.fetch(gitlabPackage())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("- keysyms: Add keys from kernel 7.0"))
        #expect(notes.markdown.contains("- Randr: RRGetOutputPrimary: add missing padding to reply"))
        #expect(
            notes.markdown.contains(
                "[Full diff on gitlab.freedesktop.org](https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/compare/xorgproto-2025.1...xorgproto-2026.1)"
            )
        )
    }

    @Test("GitLab: a 404 on compare falls back to ref_name commits, which carry the message at the top level")
    func gitlabFallsBackToCommits() async throws {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: gitlabCompareURL, data: Data(), statusCode: 404)
        fetcher.respond(to: gitlabCommitsURL, data: try Fixture.data("gitlab-commits-sample", extension: "json"), statusCode: 200)
        let source = TagCompare(httpFetcher: fetcher, database: gitlabDatabase)

        let result = await source.fetch(gitlabPackage())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("- "))
        #expect(
            notes.markdown.contains(
                "[Full diff on gitlab.freedesktop.org](https://gitlab.freedesktop.org/xorg/proto/xorgproto/-/commits/xorgproto-2026.1)"
            )
        )
    }

    @Test("GitLab: a 404 on both is a cacheable no-tag-found message")
    func gitlabBothNotFoundIsCacheable() async {
        var fetcher = FakeHTTPFetcher()
        fetcher.respond(to: gitlabCompareURL, data: Data(), statusCode: 404)
        fetcher.respond(to: gitlabCommitsURL, data: Data(), statusCode: 404)
        let source = TagCompare(httpFetcher: fetcher, database: gitlabDatabase)

        let result = await source.fetch(gitlabPackage())
        guard case .success(let notes) = result else {
            Issue.record("expected success, got \(result)")
            return
        }
        #expect(notes.markdown.contains("No tag found for 2026.1"))
    }

    @Test("the production database registers xorgproto against gitlab.freedesktop.org")
    func liveDatabaseRegistersXorgproto() {
        let spec = ResolutionDatabase.live.tagCompareSpecs["xorgproto"]
        #expect(spec?.repo == "xorg/proto/xorgproto")
        #expect(spec?.gitlabHost == "gitlab.freedesktop.org")
        #expect(spec?.tagTemplate == "xorgproto-%s")
    }

    @Test(
        "the production database registers the X.Org client libraries with their mixed-case tags",
        arguments: [
            ("libx11", "xorg/lib/libx11", "libX11-%s"),
            ("libxrender", "xorg/lib/libxrender", "libXrender-%s"),
        ]
    )
    func liveDatabaseRegistersXorgLibraries(name: String, repo: String, tagTemplate: String) {
        let spec = ResolutionDatabase.live.tagCompareSpecs[name]
        #expect(spec?.repo == repo)
        #expect(spec?.gitlabHost == "gitlab.freedesktop.org")
        #expect(spec?.tagTemplate == tagTemplate)
    }
}
