import Foundation

/// User-owned settings. The shipped default deliberately points at a visible
/// folder in the user's home rather than a hidden support directory — the
/// archive's whole purpose is Markdown a human reads. Ben's own Vault path
/// stays out of the repo (see the plan's Config-split section); it's just a
/// value in his config file like anyone else's.
struct UserConfig: Codable, Sendable, Equatable {
    var archiveDirectory: String
    var skipList: [String]
    var notify: Bool

    /// Written on first run when no config file exists yet.
    static var `default`: UserConfig {
        UserConfig(
            archiveDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Brew Release Notes")
                .path,
            skipList: [],
            notify: false
        )
    }

    /// The user's own entries plus the shipped ones. `skipList` stays purely
    /// theirs - `brewinator config skip add/remove` never touches built-ins.
    var effectiveSkipList: [String] {
        skipList + BuiltInSkipList.patterns
    }

    /// The single matcher every skip decision goes through, so no caller has to
    /// pick between `skipList` and `effectiveSkipList` by hand.
    var skipMatcher: SkipMatcher {
        SkipMatcher(effectiveSkipList)
    }

    /// Exact-name or `*`-glob match against the effective skip list.
    func isSkipped(_ name: String) -> Bool {
        skipMatcher.matches(name)
    }
}
