import Foundation

enum BrewClientError: Error, Sendable, Equatable {
    case invalidOutdatedOutput
    case processFailed(exitCode: Int32)
}

struct OutdatedResult: Sendable, Equatable {
    let formulae: [OutdatedPackageInfo]
    let casks: [OutdatedPackageInfo]
}

protocol BrewClient: Sendable {
    func outdated() async throws -> OutdatedResult
    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo]
    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo]
}

final class ProcessBrewClient: BrewClient {
    private let brewPath: String

    /// Defaults to the Apple Silicon Homebrew prefix — this machine's arch.
    /// Injectable for Intel (`/usr/local/bin/brew`) and for tests.
    init(brewPath: String = "/opt/homebrew/bin/brew") {
        self.brewPath = brewPath
    }

    func outdated() async throws -> OutdatedResult {
        let data = try run(arguments: ["outdated", "--greedy", "--json=v2"])
        return try Self.parseOutdated(data)
    }

    func formulaInfo(names: [String]) async throws -> [String: PackageURLInfo] {
        guard !names.isEmpty else { return [:] }
        let data = try run(arguments: ["info", "--json=v2", "--"] + names)
        return Self.parseFormulaInfo(data)
    }

    func caskInfo(names: [String]) async throws -> [String: PackageURLInfo] {
        guard !names.isEmpty else { return [:] }
        let data = try run(arguments: ["info", "--cask", "--json=v2", "--"] + names)
        return Self.parseCaskInfo(data)
    }

    /// Runs `brew` with an absolute executable path (not PATH-lookup) and an
    /// explicitly augmented PATH for whatever `brew` itself shells out to —
    /// the whole rewrite exists to kill the launchd-PATH-gap bug class, so
    /// this must not reintroduce a dependency on inherited PATH.
    ///
    /// Internal (not `private`) so `BrewClientRunTests` can exercise it
    /// directly against arbitrary executables/arguments — the deadlock and
    /// exit-status bugs this guards against only reproduce through `run`
    /// itself, not through the three fixed-argument callers above.
    func run(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: brewPath)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "")
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        // Drain stderr concurrently with stdout: if the child writes more
        // than the OS pipe buffer (~64KB) to stderr, it blocks writing while
        // this thread blocks reading stdout, and neither side can make
        // progress unless both pipes are drained in parallel.
        let stderrQueue = DispatchQueue(label: "brewinator.brewclient.stderr")
        stderrQueue.async {
            _ = stderr.fileHandleForReading.readDataToEndOfFile()
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BrewClientError.processFailed(exitCode: process.terminationStatus)
        }
        return data
    }

    /// Pure, unit-testable independent of `Process` — a garbled/empty result
    /// must never read as "nothing outdated".
    static func parseOutdated(_ data: Data) throws -> OutdatedResult {
        guard !data.isEmpty else {
            throw BrewClientError.invalidOutdatedOutput
        }

        let decoded: RawOutdatedResponse
        do {
            decoded = try JSONDecoder().decode(RawOutdatedResponse.self, from: data)
        } catch {
            throw BrewClientError.invalidOutdatedOutput
        }

        return OutdatedResult(
            formulae: decoded.formulae.compactMap(\.value).map {
                OutdatedPackageInfo(
                    name: $0.name,
                    installedVersion: $0.installedVersions.first ?? "",
                    currentVersion: $0.currentVersion,
                    kind: .formula
                )
            },
            casks: decoded.casks.compactMap(\.value).map {
                OutdatedPackageInfo(
                    name: $0.name,
                    installedVersion: $0.installedVersions.first ?? "",
                    currentVersion: $0.currentVersion,
                    kind: .cask
                )
            }
        )
    }
}

private struct RawOutdatedEntry: Decodable {
    let name: String
    let installedVersions: [String]
    let currentVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case installedVersions = "installed_versions"
        case currentVersion = "current_version"
    }
}

/// Decodes one array element leniently: a single malformed entry (missing
/// field, wrong type) must only cost that one package's release notes, not
/// abort the whole `brew outdated` decode and produce zero notes for
/// everything else in the run.
private struct LenientOutdatedEntry: Decodable {
    let value: RawOutdatedEntry?

    init(from decoder: Decoder) throws {
        value = try? RawOutdatedEntry(from: decoder)
    }
}

private struct RawOutdatedResponse: Decodable {
    let formulae: [LenientOutdatedEntry]
    let casks: [LenientOutdatedEntry]
}

/// The `.urls.stable.url` / `.homepage` (formula) or `.url` / `.homepage`
/// (cask) pair `ForgeRepoResolver` needs — everything else in `brew info`'s
/// ~200-field payload is irrelevant here.
struct PackageURLInfo: Sendable, Equatable {
    let stableURL: String?
    let homepage: String?
}

private struct RawFormulaStableURL: Decodable {
    let url: String?
}

private struct RawFormulaURLs: Decodable {
    let stable: RawFormulaStableURL?
}

private struct RawFormulaEntry: Decodable {
    let name: String
    let homepage: String?
    let urls: RawFormulaURLs?
}

private struct RawCaskEntry: Decodable {
    let token: String
    let url: String?
    let homepage: String?
}

/// Both `brew info --json=v2` and `brew info --cask --json=v2` share this
/// top-level shape — the non-requested kind's array just comes back empty.
private struct RawInfoResponse: Decodable {
    let formulae: [RawFormulaEntry]
    let casks: [RawCaskEntry]
}

extension ProcessBrewClient {
    /// Keyed by `.name`. Lenient by design: empty/garbled `brew info` output
    /// means every package in it just fails forge-repo resolution and falls
    /// through to "no forge repo detected" — unlike `outdated()`, this must
    /// never abort the whole sync.
    static func parseFormulaInfo(_ data: Data) -> [String: PackageURLInfo] {
        guard !data.isEmpty, let decoded = try? JSONDecoder().decode(RawInfoResponse.self, from: data) else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: decoded.formulae.map { entry in
                (entry.name, PackageURLInfo(stableURL: entry.urls?.stable?.url, homepage: entry.homepage))
            }
        )
    }

    /// Keyed by `.token`, not `.name` — casks index differently in `brew
    /// info`'s response.
    static func parseCaskInfo(_ data: Data) -> [String: PackageURLInfo] {
        guard !data.isEmpty, let decoded = try? JSONDecoder().decode(RawInfoResponse.self, from: data) else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: decoded.casks.map { entry in
                (entry.token, PackageURLInfo(stableURL: entry.url, homepage: entry.homepage))
            }
        )
    }
}
