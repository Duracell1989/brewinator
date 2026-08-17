struct ReleaseNotes: Sendable, Equatable {
    let markdown: String
}

enum FetchError: Error, Sendable, Equatable {
    case transient(reason: String)
}

protocol NoteSource: Sendable {
    func canHandle(_ package: OutdatedPackageInfo) -> Bool
    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError>
}
