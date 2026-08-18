/// Renders the outdated set the way `brew outdated --verbose` used to in
/// `brewcheck` — brewinator already computes this set to decide what to
/// fetch, so printing it removes the second `brew` call from the workflow.
enum OutdatedListing {
    static func render(_ packages: [OutdatedPackageInfo]) -> String {
        guard !packages.isEmpty else { return "Nothing outdated." }

        let labels = packages.map { "\($0.name) (\($0.kind.rawValue))" }
        let width = labels.map(\.count).max() ?? 0

        let rows = zip(labels, packages).map { label, package in
            let padding = String(repeating: " ", count: width - label.count)
            // Cleaned versions read better, but they collapse build-id-only
            // bumps (android-studio ships those) into a nonsense "X -> X"
            // row — fall back to the raw pair when that happens.
            let sameWhenCleaned = package.cleanInstalledVersion == package.cleanCurrentVersion
            let installed = sameWhenCleaned ? package.installedVersion : package.cleanInstalledVersion
            let current = sameWhenCleaned ? package.currentVersion : package.cleanCurrentVersion
            return "  \(label)\(padding)  \(installed) -> \(current)"
        }

        return (["Outdated (\(packages.count)):"] + rows).joined(separator: "\n")
    }
}
