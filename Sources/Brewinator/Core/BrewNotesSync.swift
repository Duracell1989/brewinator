import Foundation

struct SyncResult: Sendable, Equatable {
    struct NewItem: Sendable, Equatable {
        let name: String
        let version: String
    }

    /// The *unfiltered* outdated set, skip-listed packages included - it stands
    /// in for `brew outdated --verbose`, which ignored the skip list too.
    let outdated: [OutdatedPackageInfo]
    let newItems: [NewItem]
    let trashedFiles: [URL]
}

/// Ties BrewClient + ArchiveStore + Resolver + UserConfig together. A garbled
/// `brew outdated` throws out of `outdated()` before prune or fetch, so the
/// archive is never wiped by a broken snapshot.
struct BrewNotesSync: Sendable {
    let brewClient: BrewClient
    let archiveStore: ArchiveStore
    let resolver: Resolver
    let config: UserConfig
    // `var`, not `let`: a `let` with a default value is dropped from the
    // synthesized memberwise initializer, so tests could never inject a fake.
    var logger: SyncLogger = StderrLogger()

    /// `onOutdated` fires before prune and before the first fetch, so the CLI's
    /// listing appears immediately rather than after every network round trip.
    func run(onOutdated: ([OutdatedPackageInfo]) -> Void = { _ in }) async throws -> SyncResult {
        let outdated = try await brewClient.outdated()

        // Unlike `outdated()`, a failed `brew info` must not abort the sync - it
        // only costs forge-repo resolution for the packages it covers. Queried
        // by full name so a tapped formula can't be shadowed by a core one.
        let formulaInfo = (try? await brewClient.formulaInfo(names: outdated.formulae.map(\.fullName))) ?? [:]
        let caskInfo = (try? await brewClient.caskInfo(names: outdated.casks.map(\.name))) ?? [:]

        let allPackages =
            outdated.formulae.map { Self.enrich($0, with: formulaInfo) }
            + outdated.casks.map { Self.enrich($0, with: caskInfo) }

        onOutdated(allPackages)

        // Computed before skip filtering, so a still-outdated but newly
        // skip-listed package is trashed rather than kept.
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
                    // A write failure must cost this package only; the rest of
                    // the batch still has to reach the caller.
                    logger.warn("\(package.name): failed to write release notes - \(error)")
                }
            case .failure(let error):
                // Nothing else surfaces a fetch failure, so without this the run
                // completes looking clean with no trace of what's missing.
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
        enriched.headURL = match.headURL
        return enriched
    }

    /// Every `NoteSource` returns body content only, so the header is the
    /// orchestrator's job. Uses the **raw** versions, not the cleaned ones.
    private static func markdown(for package: OutdatedPackageInfo, body: String) -> String {
        "## \(package.name) (\(package.installedVersion) → \(package.currentVersion))\n\n" + body
    }
}
