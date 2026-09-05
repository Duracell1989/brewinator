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
    func update() async throws
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

    /// The one mutating call here - everything else only reads Homebrew state,
    /// which is why this is opt-in behind `--update`.
    func update() async throws {
        _ = try run(arguments: ["update", "--quiet"])
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

    /// Absolute executable path, never a PATH lookup, plus an explicitly
    /// augmented PATH for whatever `brew` shells out to - the rewrite exists to
    /// kill the launchd-PATH-gap bug class and must not reintroduce it.
    ///
    /// Internal rather than `private` so tests can drive it against arbitrary
    /// executables; the deadlock and exit-status bugs below only reproduce
    /// through `run` itself.
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

        // Drain stderr concurrently with stdout: a child that writes past the
        // ~64KB pipe buffer blocks, and so does this thread, forever.
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

    /// Pure and testable without `Process`. A garbled or empty result must
    /// never read as "nothing outdated".
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
                    name: Self.shortFormulaName($0.name),
                    installedVersion: $0.installedVersions.first ?? "",
                    currentVersion: $0.currentVersion,
                    kind: .formula,
                    fullName: $0.name
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

    /// `brew outdated` reports formulae by `full_name` (`cmd/outdated.rb:195`),
    /// so a tapped one arrives as "owner/tap/name" and everything downstream
    /// wants the last component. Casks never take this path.
    private static func shortFormulaName(_ name: String) -> String {
        guard let slash = name.lastIndex(of: "/") else { return name }
        let short = String(name[name.index(after: slash)...])
        // A trailing slash is malformed input; keep the raw string rather than
        // hand the rest of the pipeline an empty package name.
        return short.isEmpty ? name : short
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

/// A single malformed entry must only cost that one package's notes, not abort
/// the whole decode and produce zero notes for the entire run.
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

/// The only three fields `ForgeRepoResolver` needs out of `brew info`'s
/// ~200-field payload.
struct PackageURLInfo: Sendable, Equatable {
    let stableURL: String?
    let homepage: String?

    /// `urls.head.url` — the git remote the formula's `head do` block builds
    /// from. Formula-only: casks have no head URL and always leave this nil.
    let headURL: String?

    init(stableURL: String?, homepage: String?, headURL: String? = nil) {
        self.stableURL = stableURL
        self.homepage = homepage
        self.headURL = headURL
    }
}

/// One `urls.<channel>` entry. `stable` and `head` carry the same `url` field,
/// so one type covers both.
private struct RawFormulaURL: Decodable {
    let url: String?
}

private struct RawFormulaURLs: Decodable {
    let stable: RawFormulaURL?
    let head: RawFormulaURL?
}

private struct RawFormulaEntry: Decodable {
    let name: String
    /// Optional as insurance against older/trimmed `brew info` output; for a
    /// core formula it equals `name` anyway.
    let fullName: String?
    let homepage: String?
    let urls: RawFormulaURLs?

    enum CodingKeys: String, CodingKey {
        case name
        case fullName = "full_name"
        case homepage
        case urls
    }
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
    /// Keyed by `.full_name`, not `.name` - `brew info` reports a tapped
    /// formula's `name` short while `brew outdated` reports it qualified, so the
    /// full name is the only string the two commands agree on.
    ///
    /// Lenient: unlike `outdated()`, garbled output here must never abort the
    /// sync, only cost forge resolution for the packages it covers.
    static func parseFormulaInfo(_ data: Data) -> [String: PackageURLInfo] {
        guard !data.isEmpty, let decoded = try? JSONDecoder().decode(RawInfoResponse.self, from: data) else {
            return [:]
        }
        return Dictionary(
            uniqueKeysWithValues: decoded.formulae.map { entry in
                (
                    entry.fullName ?? entry.name,
                    PackageURLInfo(stableURL: entry.urls?.stable?.url, homepage: entry.homepage, headURL: entry.urls?.head?.url)
                )
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
