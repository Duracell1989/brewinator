import Darwin

/// Patterns plus the matching rule, so `fnmatch` lives in one place and callers
/// can't pass the wrong one of two near-identically named string arrays.
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
