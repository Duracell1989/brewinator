import Foundation

struct SyncResult: Sendable, Equatable {
    struct NewItem: Sendable, Equatable {
        let name: String
        let version: String
    }

    /// The *unfiltered* outdated set, skip-listed packages included — the CLI
    /// prints it in place of `brew outdated --verbose`, which never knew about
    /// the skip list either.
    let outdated: [OutdatedPackageInfo]
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

    /// `onOutdated` fires as soon as the set is known, before prune and before
    /// the first network fetch. The CLI prints the outdated listing from it:
    /// waiting for `run()` to return would put that listing *after* every fetch,
    /// making it strictly slower to appear than the `brew outdated --verbose`
    /// call it replaced.
    func run(onOutdated: ([OutdatedPackageInfo]) -> Void = { _ in }) async throws -> SyncResult {
        let outdated = try await brewClient.outdated()

        // `brew info` failing/being empty must not abort the sync the way a
        // broken `outdated()` does — it only costs forge-repo resolution for
        // the affected packages, which fall through to "no forge repo
        // detected".
        // Queried by full name so a tapped formula can't be shadowed by a
        // same-named core one.
        let formulaInfo = (try? await brewClient.formulaInfo(names: outdated.formulae.map(\.fullName))) ?? [:]
        let caskInfo = (try? await brewClient.caskInfo(names: outdated.casks.map(\.name))) ?? [:]

        let allPackages =
            outdated.formulae.map { Self.enrich($0, with: formulaInfo) }
            + outdated.casks.map { Self.enrich($0, with: caskInfo) }

        onOutdated(allPackages)

        // Deliberately the *unfiltered* outdated set — a still-outdated but
        // newly-skip-listed package still gets trashed, since this is
        // computed before skip filtering.
        let outdatedIdentities = Set(allPackages.map(\.archiveIdentity))
        let trashed = try archiveStore.prune(keeping: outdatedIdentities, skippedBy: config.skipMatcher)

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
                    logger.warn("\(package.name): failed to write release notes - \(error)")
                }
            case .failure(let error):
                // Otherwise silent: nothing else in the CLI surfaces a fetch
                // failure, so a transient blip for N packages would complete
                // the run looking clean with no trace of what's missing.
                logger.warn("\(package.name): \(error)")
            }
        }

        return SyncResult(outdated: allPackages, newItems: newItems, trashedFiles: trashed)
    }

    /// Joined on `fullName`, which both kinds' info dictionaries are keyed by:
    /// formulae by `full_name`, casks by `.token` (`outdated.rb:205` emits
    /// `name: c.token`, so a cask's `fullName` is that same token).
    private static func enrich(_ package: OutdatedPackageInfo, with info: [String: PackageURLInfo]) -> OutdatedPackageInfo {
        guard let match = info[package.fullName] else { return package }
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
