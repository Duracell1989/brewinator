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
            return "  \(label)\(padding)  \(package.cleanInstalledVersion) -> \(package.cleanCurrentVersion)"
        }

        return (["Outdated (\(packages.count)):"] + rows).joined(separator: "\n")
    }
}
