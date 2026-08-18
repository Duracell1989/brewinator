import Darwin

/// Owns both the patterns and the matching rule, so the `fnmatch` call lives in
/// one place instead of being reimplemented at every site that needs to ask
/// "is this package skipped?".
///
/// Taking this instead of a bare `[String]` also removes a trap: callers used
/// to have to remember `effectiveSkipList` rather than `skipList` - one word
/// apart, only one correct, and nothing to catch the mistake.
struct SkipMatcher: Sendable, Equatable {
    let patterns: [String]

    init(_ patterns: [String]) {
        self.patterns = patterns
    }

    static let none = SkipMatcher([])

    /// Exact-name or `*`-glob match.
    func matches(_ name: String) -> Bool {
        patterns.contains { fnmatch($0, name, 0) == 0 }
    }
}
