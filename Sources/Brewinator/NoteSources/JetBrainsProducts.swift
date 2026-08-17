import Foundation

/// JetBrains products/releases notes — one JSON endpoint covers every
/// product. Matches the release with `.version == clean` (newest/first as
/// fallback), reduces `whatsnew` to text, appends `notesLink`.
struct JetBrainsProducts: NoteSource {
    private let httpFetcher: HTTPFetching
    private let database: ResolutionDatabase

    init(httpFetcher: HTTPFetching, database: ResolutionDatabase) {
        self.httpFetcher = httpFetcher
        self.database = database
    }

    func canHandle(_ package: OutdatedPackageInfo) -> Bool {
        database.jetbrainsCodes[package.name] != nil
    }

    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        guard let code = database.jetbrainsCodes[package.name] else {
            return .success(Resolver.noForgeDetected)
        }
        guard let url = URL(string: "https://data.services.jetbrains.com/products/releases?code=\(code)") else {
            return .success(Resolver.noForgeDetected)
        }

        let data: Data
        let status: Int
        do {
            (data, status) = try await httpFetcher.fetch(url)
        } catch {
            return .failure(.transient(reason: "JetBrains code \(code): \(error)"))
        }
        guard status == 200, !data.isEmpty,
            let decoded = try? JSONDecoder().decode([String: [RawJetBrainsRelease]].self, from: data)
        else {
            return .failure(.transient(reason: "JetBrains code \(code): HTTP \(status)"))
        }

        let releases = decoded[code] ?? []
        guard let match = releases.first(where: { $0.version == package.cleanCurrentVersion }) ?? releases.first else {
            return .success(ReleaseNotes(markdown: "_No matching release in the JetBrains feed (code \(code))._\n\n"))
        }

        let text = HTMLTextReducer.reduce(match.whatsnew ?? "")
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let notesLink = (match.notesLink?.isEmpty == false) ? match.notesLink : nil

        var markdown = ""
        if hasText {
            markdown += text.firstLines(40) + "\n\n"
        }
        if let notesLink {
            markdown += "[Full release notes](\(notesLink))\n\n"
        } else if !hasText {
            markdown += "_No release notes published for this version._\n\n"
        }
        return .success(ReleaseNotes(markdown: markdown))
    }
}

private struct RawJetBrainsRelease: Decodable {
    let version: String?
    let whatsnew: String?
    let notesLink: String?
}
