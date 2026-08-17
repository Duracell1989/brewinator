struct Resolver: Sendable {
    static let noForgeDetected = ReleaseNotes(
        markdown: "_No forge repo detected — check the package's homepage manually._\n"
    )

    private let sources: [NoteSource]

    init(sources: [NoteSource]) {
        self.sources = sources
    }

    /// First matching source's result is the result — no fallback to the next
    /// source on failure; this is an early-return contract. No match at all
    /// resolves to a fixed cacheable placeholder.
    func resolve(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        for source in sources where source.canHandle(package) {
            return await source.fetch(package)
        }
        return .success(Self.noForgeDetected)
    }
}
