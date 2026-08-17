import Testing

@testable import Brewinator

private struct FakeNoteSource: NoteSource {
    let handles: Set<String>
    let result: Result<ReleaseNotes, FetchError>

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        handles.contains(package.name)
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        result
    }
}

private func package(_ name: String) -> OutdatedPackageInfo {
    OutdatedPackageInfo(name: name, installedVersion: "1.0.0", currentVersion: "1.1.0", kind: .formula)
}

@Suite("Resolver")
struct ResolverTests {
    @Test("no matching source falls back to the fixed placeholder")
    func noMatchFallsBackToPlaceholder() async {
        let resolver = Resolver(sources: [])
        let result = await resolver.resolve(package("unknown"))
        #expect(result == .success(Resolver.noForgeDetected))
    }

    @Test("first matching source wins, later sources are never consulted")
    func firstMatchWins() async {
        let first = FakeNoteSource(handles: ["node"], result: .success(ReleaseNotes(markdown: "first")))
        let second = FakeNoteSource(handles: ["node"], result: .success(ReleaseNotes(markdown: "second")))
        let resolver = Resolver(sources: [first, second])
        let result = await resolver.resolve(package("node"))
        #expect(result == .success(ReleaseNotes(markdown: "first")))
    }

    @Test("a matched source's failure is returned as-is, no fallback to later sources")
    func matchedSourceFailureIsNotRetried() async {
        let failing = FakeNoteSource(handles: ["node"], result: .failure(.transient(reason: "network down")))
        let fallback = FakeNoteSource(handles: ["node"], result: .success(ReleaseNotes(markdown: "should not be used")))
        let resolver = Resolver(sources: [failing, fallback])
        let result = await resolver.resolve(package("node"))
        #expect(result == .failure(.transient(reason: "network down")))
    }

    @Test("sources that don't match are skipped in order")
    func skipsNonMatchingSources() async {
        let irrelevant = FakeNoteSource(handles: ["other"], result: .success(ReleaseNotes(markdown: "wrong")))
        let relevant = FakeNoteSource(handles: ["node"], result: .success(ReleaseNotes(markdown: "right")))
        let resolver = Resolver(sources: [irrelevant, relevant])
        let result = await resolver.resolve(package("node"))
        #expect(result == .success(ReleaseNotes(markdown: "right")))
    }
}
