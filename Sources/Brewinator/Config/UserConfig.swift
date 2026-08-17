import Darwin

/// User-owned settings — deliberately has no baked-in default archive path;
/// Ben's Vault path can't ship in the public repo (see the plan's Config-split
/// section), so an absent config file is a first-run condition the loader
/// must surface, not silently paper over.
struct UserConfig: Codable, Sendable, Equatable {
    var archiveDirectory: String
    var skipList: [String]
    var notify: Bool

    /// Exact-name or `*`-glob match against the skip list.
    func isSkipped(_ name: String) -> Bool {
        skipList.contains { fnmatch($0, name, 0) == 0 }
    }
}
