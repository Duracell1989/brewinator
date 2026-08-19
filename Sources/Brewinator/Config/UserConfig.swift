import Foundation

/// User-owned settings. The default archive is a visible folder in the user's
/// home, not a hidden support directory - it exists to be read by a human.
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
    /// theirs - `config skip add/remove` never touches built-ins.
    var effectiveSkipList: [String] {
        skipList + BuiltInSkipList.patterns
    }

    /// The matcher every skip decision goes through.
    var skipMatcher: SkipMatcher {
        SkipMatcher(effectiveSkipList)
    }

    func isSkipped(_ name: String) -> Bool {
        skipMatcher.matches(name)
    }
}
