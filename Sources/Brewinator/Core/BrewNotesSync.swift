import Foundation

struct SyncResult: Sendable, Equatable {
    struct NewItem: Sendable, Equatable {
        let name: String
        let version: String
    }

    let newItems: [NewItem]
    let trashedFiles: [URL]
}

/// Ties BrewClient + ArchiveStore + Resolver + UserConfig together. A
/// failed/garbled `brew outdated` result propagates straight out of
/// `outdated()` and aborts the whole sync before either prune or fetch runs,
/// so the archive is never wiped by a broken snapshot.
struct BrewNotesSync: Sendable {
    let brewClient: BrewClient
    let archiveStore: ArchiveStore
    let resolver: Resolver
    let config: UserConfig
    // `var`, not `let`: a `let` stored property with a default value is
    // dropped entirely from Swift's synthesized memberwise initializer, so
    // tests could never override it with a `RecordingLogger`.
    var logger: SyncLogger = StderrLogger()

    func run() async throws -> SyncResult {
        let outdated = try await brewClient.outdated()

        // `brew info` failing/being empty must not abort the sync the way a
        // broken `outdated()` does — it only costs forge-repo resolution for
        // the affected packages, which fall through to "no forge repo
        // detected".
        let formulaInfo = (try? await brewClient.formulaInfo(names: outdated.formulae.map(\.name))) ?? [:]
        let caskInfo = (try? await brewClient.caskInfo(names: outdated.casks.map(\.name))) ?? [:]

        let allPackages =
            outdated.formulae.map { Self.enrich($0, with: formulaInfo) }
            + outdated.casks.map { Self.enrich($0, with: caskInfo) }

        // Deliberately the *unfiltered* outdated set — a still-outdated but
        // newly-skip-listed package still gets trashed, since this is
        // computed before skip filtering.
        let outdatedIdentities = Set(allPackages.map(\.archiveIdentity))
        let trashed = try archiveStore.prune(keeping: outdatedIdentities, skipList: config.skipList)

        var newItems: [SyncResult.NewItem] = []
        for package in allPackages {
            guard !config.isSkipped(package.name) else { continue }
            guard !archiveStore.existingFile(for: package) else { continue }

            switch await resolver.resolve(package) {
            case .success(let notes):
                let markdown = Self.markdown(for: package, body: notes.markdown)
                do {
                    try archiveStore.write(ReleaseNotes(markdown: markdown), for: package)
                    newItems.append(SyncResult.NewItem(name: package.name, version: package.cleanCurrentVersion))
                } catch {
                    // A write failure (disk full, permission denied, ...)
                    // must only cost this one package, not the rest of the
                    // batch — `newItems`/`trashedFiles` already computed for
                    // other packages must still make it back to the caller.
                    logger.warn("\(package.name): failed to write release notes — \(error)")
                }
            case .failure(let error):
                // Otherwise silent: nothing else in the CLI surfaces a fetch
                // failure, so a transient blip for N packages would complete
                // the run looking clean with no trace of what's missing.
                logger.warn("\(package.name): \(error)")
            }
        }

        return SyncResult(newItems: newItems, trashedFiles: trashed)
    }

    /// Cask lookups are keyed by `package.name`, which for casks is safe to
    /// compare against `brew info`'s `.token` key: Homebrew's own
    /// `cmd/outdated.rb` populates `brew outdated --json=v2`'s cask `name`
    /// field directly from `c.token` (`name: c.token`, confirmed against
    /// `/opt/homebrew/Library/Homebrew/cmd/outdated.rb:205` on 2026-08-17) —
    /// the two are the same value by construction, not just by convention.
    private static func enrich(_ package: OutdatedPackageInfo, with info: [String: PackageURLInfo]) -> OutdatedPackageInfo {
        guard let match = info[package.name] else { return package }
        var enriched = package
        enriched.stableURL = match.stableURL
        enriched.homepage = match.homepage
        return enriched
    }

    /// Prepends the `## name (installed → current)` header before any
    /// handler's body — every `NoteSource` returns body content only, so the
    /// header is the orchestrator's job. Uses the **raw** versions.
    private static func markdown(for package: OutdatedPackageInfo, body: String) -> String {
        "## \(package.name) (\(package.installedVersion) → \(package.currentVersion))\n\n" + body
    }
}
