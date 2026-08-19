/// Replaces the `brew outdated --verbose` call `brewcheck` used to make - the
/// set is already computed here to decide what to fetch.
enum OutdatedListing {
    static func render(_ packages: [OutdatedPackageInfo]) -> String {
        guard !packages.isEmpty else { return "Nothing outdated." }

        let labels = packages.map { "\($0.name) (\($0.kind.rawValue))" }
        let width = labels.map(\.count).max() ?? 0

        let rows = zip(labels, packages).map { label, package in
            let padding = String(repeating: " ", count: width - label.count)
            // Cleaned versions read better but collapse build-id-only bumps
            // (android-studio) into a nonsense "X -> X" row.
            let sameWhenCleaned = package.cleanInstalledVersion == package.cleanCurrentVersion
            let installed = sameWhenCleaned ? package.installedVersion : package.cleanInstalledVersion
            let current = sameWhenCleaned ? package.currentVersion : package.cleanCurrentVersion
            return "  \(label)\(padding)  \(installed) -> \(current)"
        }

        return (["Outdated (\(packages.count)):"] + rows).joined(separator: "\n")
    }
}
