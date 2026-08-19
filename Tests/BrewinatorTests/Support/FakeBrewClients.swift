import Foundation

@testable import Brewinator

struct FakeBrewClient: BrewClient {
    let result: OutdatedResult
    var formulaURLInfo: [String: PackageURLInfo] = [:]
    var caskURLInfo: [String: PackageURLInfo] = [:]

    func update() async throws {}
    func outdated() async throws -> OutdatedResult { result }
    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] { formulaURLInfo }
    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] { caskURLInfo }
}

/// The join key the sync queries `brew info` with isn't observable from its result.
final class NameRecordingBrewClient: BrewClient, @unchecked Sendable {
    let result: OutdatedResult
    var formulaNames: [String] = []
    var caskNames: [String] = []

    init(result: OutdatedResult) {
        self.result = result
    }

    func update() async throws {}
    func outdated() async throws -> OutdatedResult { result }

    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] {
        formulaNames = names
        return [:]
    }

    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] {
        caskNames = names
        return [:]
    }
}

/// Echoes the package it was handed back into the note body — lets a test
/// assert what `BrewNotesSync` actually passed to the resolver (e.g. the
/// merged `stableURL`) without shared mutable state across an async boundary.
struct EchoingNoteSource: NoteSource {
    func canHandle(_ package: OutdatedPackageInfo) -> Bool { true }
    func fetch(_ package: OutdatedPackageInfo) async -> Result<ReleaseNotes, FetchError> {
        .success(ReleaseNotes(markdown: "stableURL=\(package.stableURL ?? "nil")\n"))
    }
}
